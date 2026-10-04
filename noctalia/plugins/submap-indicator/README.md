# Submap Indicator

Bar pill that is hidden normally and appears only while one configured Hyprland
submap is active (default `grp`, shown as **GROUP MODE**). Other submaps (e.g.
`hyprexpo`) never show it. Luau port of the v4 QML plugin of the same name.

| Field   | Value                                |
|---------|--------------------------------------|
| ID      | `muty/submap-indicator`              |
| Entries | Bar widget: `submap`                 |
| Needs   | `hyprctl`, `socat`, `stdbuf` on PATH |

## Usage

Enable the plugin, then add the widget to a bar. The plugin draws its own pill
(primary with accent, `surface_variant` without), so disable the bar capsule for
this instance or the bar wraps the pill in a second capsule:

```toml
[widget.submap-indicator]
type    = "muty/submap-indicator:submap"
capsule = false
```

## Settings (per widget instance)

| Setting            | Type    | Default       | Description                                   |
|--------------------|---------|---------------|-----------------------------------------------|
| `matched_submap`   | string  | `grp`         | Submap name that shows the pill (exact match) |
| `label`            | string  | `GROUP MODE`  | Pill text; empty = glyph only                 |
| `glyph`            | glyph   | `layout-grid` | Tabler icon; empty = text only                |
| `use_accent_color` | bool    | `true`        | Primary fill + on-primary glyph/text          |

## Testing over IPC

```sh
noctalia msg plugin muty/submap-indicator:submap focused set grp   # force "grp" (shows)
noctalia msg plugin muty/submap-indicator:submap focused set       # default map (hides)
noctalia msg plugin muty/submap-indicator:submap focused refresh   # re-query hyprctl submap
noctalia msg plugin muty/submap-indicator:submap focused status    # notification + log line
```

`status` cannot answer on the command line (v5 `onIpc` has no return channel);
it sends a notification and writes the same line to `~/.cache/noctalia/noctalia.log`.

## Notes

- State comes from `hyprctl submap` on the first `update()` tick and once a
  minute after that (self-heal: the host never restarts a dead stream); live
  updates come from Hyprland's socket2 event stream (`socat` + `stdbuf`), which
  the host terminates on reload/disable.
- The v4 default icon `group` did not exist in the Noctalia icon set and rendered
  the `skull` fallback; v5 defaults to `layout-grid` (Tabler).
