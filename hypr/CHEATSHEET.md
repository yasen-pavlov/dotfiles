# Keybindings Cheatsheet

> Live view: press `SUPER + /` to open the noctalia keybind-cheatsheet plugin (auto-detects bindings via `hyprctl binds -j`). This static file is kept as a portable / git-versioned backup but may drift; the live panel is authoritative.

Generated from `hyprland/keybindings.lua`. `SUPER` is the Mod key.

## Session
| Keys | Action |
| --- | --- |
| `SUPER + CTRL + ALT + M` | Stop the uwsm session (log out) |
| `SUPER + ESCAPE` | Noctalia session menu (lock / logout / shutdown) |
| `SUPER + CTRL + L` | Lock screen now |

## Launching apps
| Keys | Action |
| --- | --- |
| `ALT + Space` | Noctalia launcher |
| `SUPER + Q` | Terminal |
| `SUPER + E` | File manager |
| `SUPER + B` | Browser |
| `SUPER + SHIFT + B` | Browser (private window) |
| `SUPER + M` | Email |
| `SUPER + G` | Steam |
| `SUPER + comma` | AyuGram |
| `SUPER + W` | 1Password quick access |
| `SUPER + SHIFT + E` | Emoji picker (bemoji) |

## Window management
| Keys | Action |
| --- | --- |
| `SUPER + C` | Close window |
| `SUPER + V` | Toggle floating |
| `SUPER + F` | Toggle fullscreen |
| `SUPER + Z` | Toggle pseudo-tile |
| `SUPER + X` | Toggle split direction |
| `SUPER + H` / `J` / `K` / `L` | Focus left / down / up / right |
| `SUPER + SHIFT + H/J/K/L` | Move window (or into group) |
| `SUPER + Drag (LMB)` | Move window with mouse |
| `SUPER + Drag (RMB)` | Resize window with mouse |

## Workspaces
| Keys | Action |
| --- | --- |
| `SUPER + 1..9, 0` | Go to workspace 1..10 |
| `SUPER + SHIFT + 1..9, 0` | Move window to workspace 1..10 |
| `SUPER + Mouse wheel` | Cycle workspaces |
| `SUPER + S` | Toggle scratchpad (special workspace `magic`) |
| `SUPER + SHIFT + S` | Send window to scratchpad |

## Groups (tabbed windows)
| Keys | Action |
| --- | --- |
| `SUPER + T` | Toggle group |
| `SUPER + N` | Next window in group |
| `SUPER + P` | Previous window in group |

## System
| Keys | Action |
| --- | --- |
| `SUPER + SHIFT + T` | btop task manager (floating, centered) |

## Noctalia panels
| Keys | Action |
| --- | --- |
| `SUPER + A` | Control center |
| `SUPER + D` | Calendar |
| `SUPER + I` | Settings |
| `SUPER + SHIFT + N` | Notification history |
| `SUPER + SHIFT + W` | Random wallpaper |

## Screenshots & recording (HyprCapture)
| Keys | Action |
| --- | --- |
| `PRINT` | Screenshot full-screen |
| `SUPER + PRINT` | Screenshot focused window |
| `SUPER + SHIFT + PRINT` | Screenshot region |
| `CTRL + SHIFT + PRINT` | Toggle screen recording |

## Media & audio
| Keys | Action |
| --- | --- |
| `XF86AudioRaiseVolume` / `LowerVolume` | Volume ±1% (repeats) |
| `XF86AudioMute` | Mute |
| `XF86AudioPlay` | Play / pause |
| `ALT + SHIFT + O` | Play / pause (keyboard fallback) |
| `XF86AudioNext` / `Prev` | Next / previous track |

## Display brightness (DDC/CI)
| Keys | Action |
| --- | --- |
| `XF86MonBrightnessUp` / `Down` | Monitor brightness ±10 |
| `CTRL + ALT + SHIFT + D` | Switch monitor input → notebook (VCP 0x60 = 0x10) |

## Games / app passthrough
| Keys | Action |
| --- | --- |
| `CTRL + SHIFT + I` | Forward to Pdx-Unlimiter window |
| `CTRL + SHIFT + K` | Forward to Pdx-Unlimiter window |
