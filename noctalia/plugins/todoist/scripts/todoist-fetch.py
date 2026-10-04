#!/usr/bin/env python3
"""
Backend for the noctalia-todoist plugin.

Subcommands:
  fetch              — emit grouped tasks JSON on stdout
  complete <id>      — close a task
  reschedule <id> <when>  — set due_string (today/tomorrow/YYYY-MM-DD/…)

Auth via libsecret (`secret-tool lookup uuid todoist_api_token`), matching
the existing waybar setup so no extra config is needed.
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone

from todoist_api_python.api import TodoistAPI

CACHE = pathlib.Path.home() / ".cache" / "noctalia-todoist.json"


def _load_cache() -> dict:
    try:
        if CACHE.exists():
            return json.loads(CACHE.read_text())
    except Exception:
        pass
    return {
        "ok": False,
        "last_sync": None,
        "overdue": [],
        "today": [],
        "upcoming": [],
        "error": "no cache yet",
    }


def _save_cache(payload: dict) -> None:
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(payload))
    except Exception:
        pass


def _token() -> str:
    try:
        r = subprocess.run(
            ["secret-tool", "lookup", "uuid", "todoist_api_token"],
            capture_output=True,
            text=True,
            timeout=0.6,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _project_map(api: TodoistAPI) -> dict[str, str]:
    try:
        out: dict[str, str] = {}
        for page in api.get_projects():
            for p in page:
                out[p.id] = p.name
        return out
    except Exception:
        return {}


def _task_dict(t, projects: dict[str, str]) -> dict:
    due = getattr(t, "due", None)
    raw = getattr(due, "date", None) if due else None
    # SDK 4.0 stores the due in `Due.date`: a datetime when the task is timed,
    # a plain date otherwise. There is no separate `Due.datetime` attribute.
    if isinstance(raw, datetime):
        due_dt = raw
        due_date = raw.date()
    else:
        due_dt = None
        due_date = raw
    due_str = getattr(due, "string", None) if due else None
    return {
        "id": t.id,
        "content": t.content,
        "priority": int(getattr(t, "priority", 1) or 1),
        "project": projects.get(getattr(t, "project_id", ""), ""),
        "url": getattr(t, "url", "") or "",
        "due_date": due_date.isoformat() if hasattr(due_date, "isoformat") else (str(due_date) if due_date else None),
        "due_datetime": due_dt.isoformat() if hasattr(due_dt, "isoformat") else (str(due_dt) if due_dt else None),
        "due_string": due_str or "",
    }


def _classify(items, projects):
    today = datetime.now().astimezone().date()
    cats = {"overdue": [], "today": [], "upcoming": []}
    for t in items:
        due = getattr(t, "due", None)
        d = getattr(due, "date", None) if due else None
        if d is None:
            continue
        # `Due.date` is a datetime for timed tasks; compare on the date part only.
        if isinstance(d, datetime):
            d = d.date()
        bucket = "overdue" if d < today else ("today" if d == today else "upcoming")
        cats[bucket].append(_task_dict(t, projects))
    # Sort: overdue oldest-first; today by datetime then priority; upcoming by date.
    cats["overdue"].sort(key=lambda x: (x["due_date"] or "", -x["priority"]))
    cats["today"].sort(key=lambda x: (x["due_datetime"] or "9", -x["priority"]))
    cats["upcoming"].sort(key=lambda x: (x["due_date"] or "", -x["priority"]))
    return cats


def cmd_fetch(args: list[str]) -> int:
    token = _token()
    if not token:
        print(json.dumps(_load_cache()), flush=True)
        return 0

    api = TodoistAPI(token)
    try:
        projects = _project_map(api)
        # Filter expression support: `fetch --filter "today | overdue"` etc.
        filter_expr = None
        if "--filter" in args:
            i = args.index("--filter")
            if i + 1 < len(args):
                filter_expr = args[i + 1]

        tasks: list = []
        if filter_expr:
            for page in api.filter_tasks(query=filter_expr, limit=200):
                tasks.extend(page)
        else:
            for page in api.get_tasks(limit=200):
                tasks.extend(page)

        cats = _classify(tasks, projects)
        payload = {
            "ok": True,
            "last_sync": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "error": None,
            **cats,
        }
        print(json.dumps(payload), flush=True)
        _save_cache(payload)
        return 0
    except Exception as e:
        cached = _load_cache()
        cached["error"] = f"{type(e).__name__}: {e}"
        print(json.dumps(cached), flush=True)
        return 0


def cmd_complete(args: list[str]) -> int:
    if not args:
        print(json.dumps({"ok": False, "error": "missing task id"}))
        return 2
    token = _token()
    if not token:
        print(json.dumps({"ok": False, "error": "no token"}))
        return 1
    try:
        TodoistAPI(token).complete_task(task_id=args[0])
        print(json.dumps({"ok": True}))
        return 0
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"}))
        return 1


def _resolve_when(when: str) -> date | None:
    """Map a relative/ISO `when` to a concrete date, or None if not a plain date."""
    today = datetime.now().astimezone().date()
    w = when.strip().lower()
    if w == "today":
        return today
    if w == "tomorrow":
        return today + timedelta(days=1)
    try:
        return date.fromisoformat(when.strip())
    except ValueError:
        return None


def cmd_reschedule(args: list[str]) -> int:
    if len(args) < 2:
        print(json.dumps({"ok": False, "error": "usage: reschedule <id> <when>"}))
        return 2
    token = _token()
    if not token:
        print(json.dumps({"ok": False, "error": "no token"}))
        return 1
    task_id, when = args[0], args[1]
    try:
        api = TodoistAPI(token)
        # Recurring tasks: passing a bare due_string (e.g. "tomorrow") REPLACES the
        # whole due and drops the recurrence. To move just the next occurrence while
        # keeping the schedule, re-send the original recurrence string together with
        # an explicit due_date.
        target = _resolve_when(when)
        due = getattr(api.get_task(task_id), "due", None)
        recurring = bool(getattr(due, "is_recurring", False)) if due else False
        rec_string = getattr(due, "string", None) if due else None
        # SDK's Due.date is a datetime when the task is timed, a date otherwise.
        due_date_val = getattr(due, "date", None) if due else None
        if recurring and rec_string and target is not None:
            # Keep the recurrence; move only the next occurrence. Preserve the
            # time-of-day if the task is timed (due_date is date-only and drops it).
            if isinstance(due_date_val, datetime):
                api.update_task(
                    task_id=task_id,
                    due_string=rec_string,
                    due_datetime=datetime.combine(target, due_date_val.timetz()),
                )
            else:
                api.update_task(task_id=task_id, due_string=rec_string, due_date=target)
        elif target is not None:
            # Non-recurring: move the date, keeping any time-of-day.
            if isinstance(due_date_val, datetime):
                api.update_task(
                    task_id=task_id,
                    due_datetime=datetime.combine(target, due_date_val.timetz()),
                )
            else:
                api.update_task(task_id=task_id, due_date=target)
        else:
            api.update_task(task_id=task_id, due_string=when)
        print(json.dumps({"ok": True}))
        return 0
    except Exception as e:
        print(json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"}))
        return 1


def main() -> int:
    if len(sys.argv) < 2:
        return cmd_fetch([])
    cmd, *rest = sys.argv[1:]
    if cmd == "fetch":
        return cmd_fetch(rest)
    if cmd == "complete":
        return cmd_complete(rest)
    if cmd == "reschedule":
        return cmd_reschedule(rest)
    print(json.dumps({"ok": False, "error": f"unknown command: {cmd}"}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
