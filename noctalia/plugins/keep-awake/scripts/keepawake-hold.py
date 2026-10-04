#!/usr/bin/env python3
"""keepawake-hold: long-lived inhibit holder for the muty/keep-awake Noctalia v5 plugin.

Scopes
  partial  logind Inhibit("sleep:handle-lid-switch", block)            system stays up, idle chain runs
  full     org.freedesktop.ScreenSaver.Inhibit (served by Noctalia)     nothing fires
           + logind Inhibit("idle:sleep:handle-lid-switch", block)

Both gates land in Noctalia's single idle-suppression counter (ScreenSaverService counts
D-Bus cookies and +1 while logind BlockInhibited contains "idle"); holding both in full
scope keeps working if either route is ever removed upstream.

Lifetime: --seconds N (0/omitted = forever); SIGTERM/SIGINT/SIGHUP -> release, exit 0;
parent (Noctalia) gone -> release, exit 0 (PR_SET_PDEATHSIG delivers SIGTERM at once, the
heartbeat's ppid check is the portable backstop; a closed stdout is also honoured but is
not relied on: processes Noctalia forks later inherit the pipe's read end);
nothing could be held -> exit 1. Noctalia restart: the ScreenSaver cookie is re-acquired
from the new owner.

stdout line protocol (flushed; consumed by noctalia.runStream):
  held scope=<s> screensaver=<0|1> cookie=<n|-> logind=<what|-> pid=<n> until=<epoch|0> session=<id>
  alive until=<epoch|0>                    every --heartbeat seconds (default 15)
  reacquired cookie=<n> | lost-owner       ScreenSaver owner changed
  error <what>: <message>
  released reason=<expired|sigterm|sigint|sighup|stdout-closed|parent-gone|nothing-held>
"""
import argparse
import os
import signal
import sys
import time

try:
    import gi

    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
except (ImportError, ValueError) as exc:
    # python-gobject missing: report on stdout (the only channel the plugin reads) instead
    # of a traceback on stderr, so the failure notification carries the real cause.
    sys.stdout.write(f"error import: {exc}\nreleased reason=nothing-held\n")
    sys.stdout.flush()
    sys.exit(1)

try:
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLibUnix  # noqa: E402

    def unix_signal_add(sig, cb, *args):
        return GLibUnix.signal_add(GLib.PRIORITY_HIGH, sig, cb, *args)
except (ValueError, ImportError):
    def unix_signal_add(sig, cb, *args):
        return GLib.unix_signal_add(GLib.PRIORITY_HIGH, sig, cb, *args)

SS_NAME = "org.freedesktop.ScreenSaver"
SS_PATH = "/org/freedesktop/ScreenSaver"
SS_IFACE = "org.freedesktop.ScreenSaver"
LOGIND_NAME = "org.freedesktop.login1"
LOGIND_PATH = "/org/freedesktop/login1"
LOGIND_IFACE = "org.freedesktop.login1.Manager"
WHAT_BY_SCOPE = {"partial": "sleep:handle-lid-switch", "full": "idle:sleep:handle-lid-switch"}


class Holder:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.loop = GLib.MainLoop()
        self.session: Gio.DBusConnection | None = None
        self.cookie: int | None = None
        self.watch_id = 0
        self.logind_fd: int | None = None
        self.logind_what: str | None = None
        self.released = False
        self.stdout_dead = False
        self.parent_pid = os.getppid()  # Noctalia (sh exec's us, so the pid chain is direct)
        self.deadline = int(time.time() + args.seconds) if args.seconds > 0 else 0

    # -- stdout protocol -------------------------------------------------------------
    def say(self, line: str) -> None:
        if self.stdout_dead:
            return
        try:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, OSError):
            # The reader (Noctalia's stream worker) is gone: nobody can stop us any more,
            # so drop every lock and exit instead of holding a sleep block forever.
            self.stdout_dead = True
            try:
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
            except OSError:
                pass
            self.release("stdout-closed")

    # -- ScreenSaver (session bus, served by Noctalia) --------------------------------
    def inhibit(self) -> bool:
        if self.cookie is not None or self.session is None:
            return self.cookie is not None
        try:
            reply = self.session.call_sync(
                SS_NAME, SS_PATH, SS_IFACE, "Inhibit",
                GLib.Variant("(ss)", (self.args.app, self.args.reason)),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 2000, None,
            )
        except GLib.Error as exc:
            self.say(f"error inhibit-failed: {exc.message}")
            return False
        self.cookie = reply.unpack()[0]
        return True

    def uninhibit(self) -> None:
        if self.cookie is None or self.session is None:
            return
        cookie, self.cookie = self.cookie, None
        try:
            self.session.call(
                SS_NAME, SS_PATH, SS_IFACE, "UnInhibit",
                GLib.Variant("(u)", (cookie,)), None,
                Gio.DBusCallFlags.NONE, 2000, None, None,
            )
            self.session.flush_sync(None)
        except GLib.Error as exc:
            self.say(f"error uninhibit-failed: {exc.message}")

    def on_name_appeared(self, _conn, _name, _owner) -> None:
        if self.released:
            return
        if self.cookie is None and self.inhibit():
            self.say(f"reacquired cookie={self.cookie}")

    def on_name_vanished(self, _conn, _name) -> None:
        if self.cookie is not None:
            self.cookie = None
            self.say("lost-owner")

    # -- logind (system bus, fd-lifetime) ---------------------------------------------
    def acquire_logind(self, what: str) -> bool:
        try:
            system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
            reply, fdlist = system.call_with_unix_fd_list_sync(
                LOGIND_NAME, LOGIND_PATH, LOGIND_IFACE, "Inhibit",
                GLib.Variant("(ssss)", (what, self.args.app, self.args.reason, "block")),
                GLib.VariantType("(h)"), Gio.DBusCallFlags.NONE, 2000, None, None,
            )
        except GLib.Error as exc:
            self.say(f"error logind-inhibit-failed: {exc.message}")
            return False
        index = reply.unpack()[0]
        fds = fdlist.steal_fds()
        self.logind_fd = fds[index]
        for i, fd in enumerate(fds):
            if i != index:
                os.close(fd)
        self.logind_what = what
        return True

    def release_logind(self) -> None:
        fd, self.logind_fd = self.logind_fd, None
        if fd is not None:
            os.close(fd)

    # -- lifecycle ---------------------------------------------------------------------
    def heartbeat(self) -> bool:
        if os.getppid() != self.parent_pid:
            # Noctalia is gone (we were reparented): nobody can stop us any more.
            return self.release("parent-gone")
        self.say(f"alive until={self.deadline}")
        return not self.released  # keep the source while alive

    def arm_parent_watch(self) -> None:
        # Immediate path: the kernel sends SIGTERM when the thread that forked us exits.
        # Noctalia's stream worker forks, reads and reaps in one thread that lives exactly
        # as long as this child (process.cpp runAsync -> runSyncProcess), so that thread
        # ending while we run means Noctalia died. Best effort; heartbeat() covers the rest.
        try:
            import ctypes

            ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)  # PR_SET_PDEATHSIG
        except (OSError, AttributeError):
            pass
        if os.getppid() != self.parent_pid:
            self.release("parent-gone")  # already orphaned before the watch was armed

    def release(self, reason: str) -> bool:
        if self.released:
            self.loop.quit()  # idempotent: a second signal must still end the loop
            return False
        self.released = True
        try:
            if self.watch_id:
                Gio.bus_unwatch_name(self.watch_id)
                self.watch_id = 0
            self.uninhibit()
            self.release_logind()
        except Exception as exc:  # noqa: BLE001
            self.say(f"error release: {exc!r}")
        finally:
            self.say(f"released reason={reason}")
            self.loop.quit()
        return False

    def run(self) -> int:
        want_ss = self.args.scope == "full"
        if want_ss:
            try:
                self.session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            except GLib.Error as exc:
                self.say(f"error session-bus: {exc.message}")
                want_ss = False
        ss_ok = want_ss and self.inhibit()
        logind_ok = self.acquire_logind(WHAT_BY_SCOPE[self.args.scope])
        if not ss_ok and not logind_ok:
            self.say("released reason=nothing-held")
            return 1
        if want_ss:
            self.watch_id = Gio.bus_watch_name(
                Gio.BusType.SESSION, SS_NAME, Gio.BusNameWatcherFlags.NONE,
                self.on_name_appeared, self.on_name_vanished,
            )
        self.say(
            f"held scope={self.args.scope} screensaver={int(ss_ok)} "
            f"cookie={self.cookie if ss_ok else '-'} "
            f"logind={self.logind_what if logind_ok else '-'} "
            f"pid={os.getpid()} until={self.deadline} session={self.args.session}"
        )
        self.arm_parent_watch()
        if self.released:
            # The held line hit EPIPE or the parent was already gone: everything was released
            # in place, and loop.quit() before loop.run() would not stop the loop.
            return 0
        for sig, name in ((signal.SIGTERM, "sigterm"), (signal.SIGINT, "sigint"), (signal.SIGHUP, "sighup")):
            unix_signal_add(sig, self.release, name)
        if self.args.seconds > 0:
            # Second granularity (32-bit seconds, ~136 years) — timeout_add's ms argument is a
            # guint32 and overflows at ~49.7 days.
            GLib.timeout_add_seconds(max(1, int(self.args.seconds)), self.release, "expired")
        if self.args.heartbeat > 0:
            GLib.timeout_add(int(self.args.heartbeat * 1000), self.heartbeat)
        self.loop.run()
        return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scope", choices=("partial", "full"), required=True)
    ap.add_argument("--seconds", type=float, default=0.0, help="release after N seconds (0 = forever)")
    ap.add_argument("--session", default="-", help="opaque id echoed in 'held' and visible in argv (for pkill -f)")
    ap.add_argument("--heartbeat", type=float, default=15.0, help="seconds between 'alive' lines (0 = off)")
    ap.add_argument("--app", default="keep-awake", help="ScreenSaver application_name / logind who")
    ap.add_argument("--reason", default="Keep Awake", help="ScreenSaver reason / logind why")
    return Holder(ap.parse_args()).run()


if __name__ == "__main__":
    sys.exit(main())
