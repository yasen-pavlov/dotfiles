# muty/borg-backup

Bar pill and panel for the nightly `borg-backup.service`: progress while a backup runs, a
warning when the last run failed or the last archive is old, nothing otherwise.

Served by the `dotfiles` path source. Plugin id `muty/borg-backup`.

| Entry | Type string | What |
|---|---|---|
| service | `muty/borg-backup:service` | reads the two status files, asks systemctl for the next run, publishes one snapshot |
| bar | `muty/borg-backup:bar` | pill: hidden when idle, progress while running, warning otherwise |
| panel | `muty/borg-backup:panel` | details: live progress, warnings, last run, last archive, next run |

## Bar pill

| Mode | Shown when | Pill |
|---|---|---|
| idle | nothing to report, or no state file yet | hidden (no capsule, no gap) |
| running | the live status file says `running` and its pid is alive | glyph + `Backup 42%` during `create` when the previous archive's file count is known, else `Backup` |
| warn | not running and the last run failed / was interrupted before an archive was written, or the last archive is older than `stale_hours` (or there is none) | red warning glyph + `Backup failed` / `Backup interrupted` / `Backup 3d old` / `No backup yet` |

The percentage is an estimate: files processed so far relative to the previous archive's
file count, capped at 99 %. A failed or interrupted run wins over the age warning. Left
click toggles the panel (a `[widget.actions]` default, remappable per instance). The
tooltip shows stage, elapsed time and files while running, last run and last archive
age on a warning.

## Panel

While running: stage (Snapshot / Backing up / Pruning / Cleaning up), a progress bar
(determinate only during `create` with a baseline), files processed vs expected, bytes
processed, new (deduplicated) data, elapsed time ticking every second and the previous
`create` duration. Always: both warning causes in words when present, the last run when it
did not succeed (result, when, stage it ended in, exit code, whether its archive was
written), the last archive (age and time, original size, new data, duration) and the next
timer run (`systemctl show borg-backup.timer`, refreshed on open and at most once a
minute; "unknown" if that fails).

## Status files

Written by the root-side backup script; the plugin only reads them. Integers are Unix
seconds and bytes; both files are replaced atomically; readers ignore unknown keys.

- `/run/borg-backup/status.json` — exists only while a run is in progress: `schema` (1),
  `state` (`running`), `pid`, `stage` (`snapshot` | `create` | `prune` | `cleanup`),
  `started_at`, `stage_started_at`, `updated_at`, `nfiles`, `original_size`,
  `compressed_size`, `deduplicated_size`, `expected_nfiles`, `expected_duration_s`.
- `/var/lib/borg-backup/last-run.json` — `schema` (1), `last_run` (`result`: `running` |
  `success` | `failed` | `interrupted`, `started_at`, `finished_at`, `stage`,
  `exit_code`, `archive`) and `last_archive` (`name`, `finished_at`, `duration_s`,
  `nfiles`, `original_size`, `compressed_size`, `deduplicated_size`).

Both are polled with async reads, every 2 s while a run is live and every 5 s otherwise; no
processes are spawned for polling. A missing, unreadable or unparsable file counts as no
data; an existing file that fails one read keeps its previous data for that poll only.
`result: "running"` without a live run (no status file, or its pid is gone) is an
interrupted run (hard kill, power loss); it counts only after a second poll a second later
confirms it, because every run start shows that picture for a moment. With no state file at
all (root side not installed) the plugin stays idle and never warns.

## Settings (Settings → Plugins)

| Key | Default | Notes |
|---|---|---|
| `status_file` | `/run/borg-backup/status.json` | live status path (for testing against fixtures) |
| `state_file` | `/var/lib/borg-backup/last-run.json` | persistent state path (for testing against fixtures) |
| `stale_hours` | `48` | warn when the last archive is older; min 1. Below 24 h the pill shows hours (`Backup 6h old`) |

The two paths can be pointed at fixtures from `config.toml`:

```toml
[plugin_settings."muty/borg-backup"]
status_file = "/tmp/fixtures/status.json"
state_file  = "/tmp/fixtures/last-run.json"
```

then `noctalia msg config-reload`. A fixture run needs a live `pid` (any process you own,
e.g. a `sleep`).

## IPC

```
noctalia msg plugin muty/borg-backup:service all refresh   # poll both files now
noctalia msg plugin muty/borg-backup:service all status    # log paths + the current snapshot
noctalia msg panel-toggle muty/borg-backup:panel           # built-in, no plugin code
```

`status` answers in `~/.cache/noctalia/noctalia.log` (v5 `onIpc` has no return channel).

## Notes

- Noctalia closes an open panel when the pill appears or disappears (bar relayout), so the
  panel closes by itself when a run starts or ends while it is open.
- Requirements: `systemctl` (next run only; everything else works without it).
