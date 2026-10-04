# muty/keep-awake

Timed keep-awake for Noctalia v5 — the Luau port of the v4 QML plugin
`keep-awake-plus`. Pick a duration (or ∞) and a scope, get a countdown pill in the
bar, a control-center tile and a panel; extend with one click; the last choice is
remembered; a running session survives a Noctalia restart or plugin reload.

Served by the `dotfiles` path source. Plugin id `muty/keep-awake`.

| Entry | Type string | What |
|---|---|---|
| service | `muty/keep-awake:service` | owns the session, the holder process, notifications, IPC |
| bar | `muty/keep-awake:bar` | coffee pill, visible only while a session runs |
| tile | `muty/keep-awake:tile` | control-center shortcut tile |
| panel | `muty/keep-awake:panel` | duration grid · scope toggle · extend / turn on-off |

## Scopes

| Scope | Holds | Effect |
|---|---|---|
| **partial** (default) | logind `Inhibit("sleep:handle-lid-switch", block)` | System stays up: auto-suspend is refused by logind. Dim, screen-off and lock still run (v4 semantics). |
| **full** ("Keep display awake") | `org.freedesktop.ScreenSaver.Inhibit` cookie (served by Noctalia) **and** logind `Inhibit("idle:sleep:handle-lid-switch", block)` | Every idle behaviour is suppressed — dim, screen-off, lock, lock-and-suspend — and external suspend / lid close are blocked. |

Both scopes hold a sleep block, so a manual `systemctl suspend` (or the session panel's
suspend) is refused while a session runs — same as v4. Turn Keep Awake off first, or use
`systemctl suspend -i`.

Partial-scope caveat carried over from v4: when Noctalia's `lock_and_suspend` behaviour
fires during a partial session, it locks and then launches `systemctl suspend`, which
logind refuses silently. The machine stays locked and awake with the monitors off (the
intended behaviour). v5-only side effect: Noctalia has already armed its
"skip lock before sleep" flag for that attempt, so the *next* external suspend after such
a refusal skips lock-before-sleep once. The plugin cannot clear that flag.

## Bar pill

Hidden when off. While a session runs: coffee glyph tinted **primary** (full) or
**secondary** (partial), the remaining time beside it ("29m", "1h05m", "<1m", "∞";
`show_remaining_text`), and a tooltip with scope, remaining and the end time.

| Gesture | Action |
|---|---|
| Left | Open the panel — or re-activate the last choice when `activate_on_left_click` is on |
| Right | Turn off |
| Middle | Toggle the last choice (30 min · default scope when nothing was chosen yet) |

Any gesture can be overridden per widget instance, e.g.
`[widget.keep-awake.actions] left = "plugin muty/keep-awake:service all toggle"`.

## Control-center tile

Left opens the panel, right turns the session off (v4 parity). Active while a session
runs; the label shows the remaining time.

## Panel

Header with status line · 3-column duration grid (`durations`, plus ∞ when
`include_unlimited`) · "Keep display awake" toggle (= full scope) · `+Nm` quick-extend
(timed sessions only) and **Turn on / Turn off**.

While a session runs, clicking a duration tile restarts it with that duration at once and
flipping the scope toggle restarts it with the remaining time preserved. A restart spawns
the replacement holder first and releases the old one only after the new one holds, so
the inhibit never lapses and no idle countdown re-arms mid-session.

## Settings (Settings → Plugins)

| Key | Default | Notes |
|---|---|---|
| `default_scope` | `partial` | preselected scope when off; toggle fallback |
| `durations` | `30, 60, 120, 240, 480` | minutes, in tile order (strings — there is no int list type) |
| `include_unlimited` | `true` | show the ∞ tile |
| `show_remaining_text` | `true` | countdown beside the bar glyph |
| `activate_on_left_click` | `false` | off: left click opens the panel |
| `quick_extend_minutes` | `30` | 5–240; the `+Nm` button, `extend` without payload |
| `notify` | `true` | desktop notifications on on/off/expired/extended (v5 has no plugin toast API); error notifications ignore this |

Panel placement / position / open-near-click are injected by the host as usual. The
manifest asks for `attached`; an attached panel inherits the bar's background opacity
(0 here), so if it renders see-through switch `panel_placement` to `floating`.

## IPC

The service is a singleton, so the target is always `all`:

```
noctalia msg plugin muty/keep-awake:service all toggle              # last choice on/off
noctalia msg plugin muty/keep-awake:service all on [duration] [scope]
noctalia msg plugin muty/keep-awake:service all off
noctalia msg plugin muty/keep-awake:service all extend [minutes]
noctalia msg plugin muty/keep-awake:service all scope <partial|full>
noctalia msg plugin muty/keep-awake:service all status              # log line (+ notification when notify is on)
noctalia msg panel-toggle muty/keep-awake:panel                     # built-in, no plugin code
```

`duration` = `30m` · `2h` · `1h30m` · `90s` · `unlimited` | `inf` | `∞` · bare seconds.
`on` without a duration uses the last choice, else the first configured duration; without
a scope the last choice, else `default_scope`. `on` while running restarts with the new
values. `scope` while off only preselects the panel toggle for this shell lifetime.

## Wiring (config.toml, done by hand)

```toml
[plugins]
enabled = [..., "muty/keep-awake"]

# bar: replace the interim "caffeine" entry
end = [..., "muty/keep-awake:bar", ...]

# control center: replace the interim caffeine tile
[[control_center.shortcuts]]
type = "muty/keep-awake:tile"
```

## How it works

`service.luau` spawns `scripts/keepawake-hold.py` (python3 + PyGObject) through
`noctalia.runStream("exec python3 … --scope … --seconds … --session <nonce>")`. The
holder acquires the inhibits, prints one `held …` line, heartbeats `alive` every 15 s and
prints `released reason=…` as its last line. Timed sessions expire inside the holder
(GLib timer); the service's own deadline check is only a backstop.

Nothing can leak: the holder is a child of the plugin runtime (the host SIGTERMs it on
reload, disable, uninstall and shutdown), the ScreenSaver cookie is dropped by Noctalia
when the holder's bus name vanishes, the logind inhibit dies with its fd, and the holder
self-releases when its parent disappears (a SIGKILLed or crashed shell): immediately via
`PR_SET_PDEATHSIG`, and at the latest at its next heartbeat (≤ 15 s) through a ppid check.
A closed stdout is honoured too but not relied on — processes Noctalia forks after the
holder (launcher apps, exec actions, the replacement holder of a restart) inherit the
pipe's read end, so EPIPE alone would not be a reliable orphan signal.
Early stops are `pkill -TERM -f '^\S*python3\S* \S*keepawake-hold\.py .*--session <nonce>( |$)'`
(argv form, never through a shell); no `held` line within 10 s of a spawn (the holder's
own D-Bus timeouts are 2 s + 2 s, plus a possible cold polkitd start) or 40 s without a
heartbeat marks the holder dead and the session ends with an error notification.

Suspend / resume and clock steps: the service's timeouts run on the wall clock, so the
first tick after a resume (or an NTP step) sees one oversized gap. It is forgiven — the
holder's own timers are monotonic and did not advance — instead of being mistaken for a
dead holder. A timed session that ran out while suspended ends with "Keep Awake ended"
within ~10 s of the resume.

State lives in two files, exactly like v4:

- `$XDG_RUNTIME_DIR/noctalia-keep-awake/session.json` — the live session. A Noctalia
  restart or plugin reload respawns the holder silently with the remaining time; logout
  wipes it. Disabling or uninstalling the plugin deletes it.
- `<pluginDataDir>/last.json` — `{ duration_seconds, scope, duration_label }`, rewritten
  on every user-initiated start (not on extend). On first run the v4 file
  `~/.local/state/system-awake/last.json` is imported when present.

The service is the only clock: it ticks once a second while a session runs and publishes
the remaining-time string only when it changes (≤ 1/min). Bar, tile and panel never tick.

## Built-in caffeine

Left untouched: the plugin neither toggles nor reads it (no plugin API exposes its state,
and toggling it would add OSD noise and a second visible owner). Full scope already
reaches the same idle-suppression counter through logind's `BlockInhibited`, so caffeine
is redundant while a full session runs and must not be on during a partial one if you
want the display to sleep. Retire the interim caffeine bar widget and tile once this
plugin is wired in.

## Requirements

`python3`, `python-gobject` (Gio/GLib), `pkill` (procps). The service refuses to start a
session and shows an error when `python3` or `pkill` is missing; a missing
`python-gobject` surfaces as "Keep Awake could not start — import: No module named 'gi'".

## Development notes

- Editing `service.luau` (or `lib/format.luau`) restarts the service runtime: the host
  kills the holder, the new runtime resumes the session from `session.json`. Bar / tile /
  panel edits reload only their own VM.
- `noctalia plugins lint <plugin dir>` cross-checks the settings; the holder protocol can
  be exercised from a shell: `scripts/keepawake-hold.py --scope full --seconds 3`.
- Log observation: Noctalia's file sink buffers INFO/DEBUG lines; trigger another log line
  before grepping for the holder's `screensaver inhibit` / `systemd idle inhibit` entries.
