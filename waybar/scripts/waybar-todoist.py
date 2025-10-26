#!/usr/bin/env python3
from todoist_api_python.api import TodoistAPI
from datetime import datetime
import json
import subprocess
import pathlib

CACHE = pathlib.Path.home() / ".cache/waybar-todoist.json"


def api_token() -> str:
    return subprocess.run(
        ["secret-tool", "lookup", "uuid", "todoist_api_token"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()


def seg(color: str, val: int) -> str:
    return f'<span foreground="{color}" size="smaller">●</span> {val}'


def classify(items):
    """Return dict of lists: overdue/today/upcoming."""
    today = datetime.now().astimezone().date()
    cats = {"overdue": [], "today": [], "upcoming": []}

    for t in items:
        d = getattr(getattr(t, "due", None), "date", None)
        if d is None:
            continue
        if d < today:
            cats["overdue"].append(t)
        elif d == today:
            cats["today"].append(t)
        else:
            cats["upcoming"].append(t)

    # sort by date then updated_at for stable order
    for k in cats:
        cats[k].sort(
            key=lambda x: (
                getattr(getattr(x, "due", None), "date", None),
                getattr(x, "updated_at", None),
            )
        )
    return cats


def read_cache():
    try:
        if CACHE.exists():
            return json.loads(CACHE.read_text())
    except Exception:
        pass
    return {"overdue": 0}


def write_cache(data):
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(data))
    except Exception:
        pass


def notify_overdue_increase(prev: int, curr: int, examples: list[str]):
    if curr > prev:
        subtitle = f"{curr} overdue task" + ("s" if curr != 1 else "")
        body = "\n".join(examples[:5]) if examples else ""
        subprocess.run(["notify-send", "Todoist",
                       f"{subtitle}\n{body}"], check=False)


def tooltip_text(cats) -> str:
    def lines(title, tasks, limit=5):
        out = [title] if tasks else []
        for t in tasks[:limit]:
            d = getattr(getattr(t, "due", None), "date", None)
            ds = d.isoformat() if d else ""
            out.append(f" • {t.content}  [{ds}]")
        return out

    parts = []
    parts += lines("Overdue:", cats["overdue"])
    parts += lines("Today:", cats["today"])
    parts += lines("Upcoming:", cats["upcoming"])
    return "\n".join(parts) if parts else "No due tasks"


def main():
    api = TodoistAPI(api_token())

    try:
        it = api.get_tasks(limit=200)
        tasks = [t for page in it for t in page]

        cats = classify(tasks)
        counts = {k: len(v) for k, v in cats.items()}

        text = "  ".join(
            [
                seg("#de4c4a", counts["overdue"]),
                seg("#f49c18", counts["today"]),
                seg("#4073d6", counts["upcoming"]),
            ]
        )

        # Tooltip content
        tip = tooltip_text(cats)

        # Notify if overdue increased
        cache = read_cache()
        notify_overdue_increase(
            cache.get("overdue", 0),
            counts["overdue"],
            [t.content for t in cats["overdue"]],
        )
        write_cache({"overdue": counts["overdue"]})

        payload = {"text": text, "tooltip": tip, "class": "todoist"}
        print(json.dumps(payload), flush=True)

    except Exception as e:
        print(json.dumps({"text": f"⚠️ {type(e).__name__}: {e}"}), flush=True)


if __name__ == "__main__":
    main()
