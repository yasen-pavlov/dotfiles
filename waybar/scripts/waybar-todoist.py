#!/usr/bin/env python3
from todoist_api_python.api import TodoistAPI
from datetime import datetime
import json
import subprocess
import pathlib

CACHE = pathlib.Path.home() / ".cache/waybar-todoist.json"


def load_cache():
    try:
        if CACHE.exists():
            return json.loads(CACHE.read_text())
    except Exception:
        pass
    # minimal safe default payload
    return {
        "text": "",
        "tooltip": "Todoist: waiting for keyring/network",
        "class": "todoist",
    }


def save_cache(payload: dict):
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(payload))
    except Exception:
        pass


def api_token() -> str:
    """Fetch token quickly from secret-tool without blocking at boot."""
    try:
        result = subprocess.run(
            ["secret-tool", "lookup", "uuid", "todoist_api_token"],
            capture_output=True,
            text=True,
            timeout=0.6,
        )
        token = result.stdout.strip()
        return token or ""
    except subprocess.TimeoutExpired:
        return ""
    except Exception:
        return ""


def seg(color: str, val: int) -> str:
    return f'<span foreground="{color}" size="smaller">●</span> {val}'


def classify(items):
    """Return dict lists: overdue/today/upcoming."""
    today = datetime.now().astimezone().date()
    cats = {"overdue": [], "today": [], "upcoming": []}
    for t in items:
        due = getattr(t, "due", None)
        d = getattr(due, "date", None) if due else None
        if d is None:
            continue
        if d < today:
            cats["overdue"].append(t)
        elif d == today:
            cats["today"].append(t)
        else:
            cats["upcoming"].append(t)
    for k in cats:
        cats[k].sort(
            key=lambda x: (
                getattr(getattr(x, "due", None), "date", None),
                getattr(x, "updated_at", None),
            )
        )
    return cats


def build_payload(cats):
    counts = {k: len(v) for k, v in cats.items()}
    text = " ".join(
        [  # thin spaces for tight layout
            seg("#de4c4a", counts["overdue"]),
            seg("#f49c18", counts["today"]),
            seg("#4073d6", counts["upcoming"]),
        ]
    )
    # simple tooltip with a few items
    lines = []
    for title, key in (
        ("Overdue", "overdue"),
        ("Today", "today"),
        ("Upcoming", "upcoming"),
    ):
        lst = cats[key][:5]
        if lst:
            lines.append(title + ":")
            lines += [f" • {t.content}" for t in lst]
    tooltip = "\n".join(lines) if lines else "No due tasks"
    return {"text": text, "tooltip": tooltip, "class": "todoist"}


def main():
    # If token isn’t ready yet, show cached payload immediately
    token = api_token()
    if not token:
        print(json.dumps(load_cache()), flush=True)
        return

    api = TodoistAPI(token)
    try:
        # fetch active tasks (SDK v3 iterator)
        it = api.get_tasks(limit=200)
        tasks = [t for page in it for t in page]
        cats = classify(tasks)
        payload = build_payload(cats)
        print(json.dumps(payload), flush=True)
        save_cache(payload)
    except Exception as e:
        # On error, fall back to cache so the module still renders
        cached = load_cache()
        cached["tooltip"] = (
            f"{cached.get('tooltip', '')}\nLast error: {type(e).__name__}: {e}"
        )
        print(json.dumps(cached), flush=True)


if __name__ == "__main__":
    main()
