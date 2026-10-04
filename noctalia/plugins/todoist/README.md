# noctalia-todoist

Todoist tasks on the noctalia bar — overdue / today / upcoming counts in the
pill, and a panel to complete or push tasks to tomorrow without opening the web
app.

## Bar pill

Capsule with a checklist icon (tinted by urgency: red if anything overdue,
amber if anything due today, neutral otherwise) and per-bucket colored dots
showing the counts. Buckets with zero items are hidden so the widget stays
calm on quiet days.

| Click  | Action |
|--------|--------|
| Left   | Open the panel |
| Right  | Open Todoist in the browser |
| Middle | Force refresh |

## Panel

Header with title, totals, last-sync, refresh + open-in-browser buttons.
Three sections (Overdue / Today / Upcoming) with one row per task:

- Priority pip (P1 red → P4 muted)
- Content + project subtext
- Due chip (e.g. `3d ago`, `10:30am`, `Wed`)
- On hover: `[push to tomorrow]` (overdue + today only) and `[mark complete]`
- Click row → open that task in Todoist

## Requirements

- Python 3 with the `todoist-api-python` package available on the system
  interpreter. (`pacman -S python-todoist-api-python` on Arch, or
  `pip install todoist-api-python` in a venv that `python3` resolves to.)
- A Todoist API token stored in libsecret under the attribute
  `uuid=todoist_api_token`:

  ```
  secret-tool store --label="Todoist API" uuid todoist_api_token
  ```

- `xdg-open` for the "open in Todoist" actions.

## Settings

| Setting | Default | Notes |
|---|---|---|
| `pollSeconds` | `90` | Refresh interval; the script caches the last response so a poll failure doesn't blank the pill |
| `filter` | `""` | Optional Todoist filter expression (e.g. `@work`, `today | overdue`). Empty fetches all active tasks |
| `maxPerSection` | `10` | Per-section row cap; overflow shows `+ N more` |
| `showOverdue` / `showToday` / `showUpcoming` | `true` | Hide individual sections |
| `pillShowIcon` | `true` | Toggle the checklist icon |
| `pillShowDots` | `true` | Toggle the count dots |
| `colorOverdue` / `colorToday` / `colorUpcoming` | `#de4c4a` / `#f49c18` / `#4073d6` | Hex colors for dots, accents, and the urgency tint |
| `openUrl` | `https://todoist.com/app/today` | Where right-click on the pill (and the panel's open button) go |

## Install

This plugin is installed by `link_files`. If you're enabling it for the first
time, add it to noctalia's plugin manager (or edit `~/.config/noctalia/plugins.json`
to include a `"todoist": { "enabled": true }` state entry).
