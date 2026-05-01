# dotfiles

Personal config for Linux (CachyOS / Hyprland) and macOS.

## Machine-local overrides

Anything machine-specific (secrets, work-only paths, host-only aliases) goes in untracked `*.local` files under `$XDG_CONFIG_HOME/zsh/` (i.e. `~/.config/zsh/`). They live outside this repo so they're never committed.

Two hooks are wired up:

| Tracked file              | Sources (if it exists)            | Use for                                       |
|---------------------------|-----------------------------------|-----------------------------------------------|
| `zsh/zshenv`              | `~/.config/zsh/zshenv.local`      | env vars, PATH tweaks, anything needed early  |
| `zsh/aliases`             | `~/.config/zsh/aliases.local`     | host-specific aliases                         |

Both checks are `[ -r ... ] && source ...`, so missing files silently no-op. Keep modes at `0600` if the file holds anything sensitive.

Tokens and similar secrets should go in the system keyring (Linux: `secret-tool store ...`, macOS: `security add-generic-password ...`) and be retrieved on demand from the `*.local` file or directly from scripts — not exported into every subprocess's environment unless needed.
