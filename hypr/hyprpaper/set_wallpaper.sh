#!/bin/bash
set -euo pipefail
shopt -s nullglob

set_wallpaper() {
	local wallpaper_dir="$HOME/Pictures/Wallpapers"
	local files=("$wallpaper_dir"/*)
	((${#files[@]} > 0)) || return 0

	local random_file="${files[RANDOM % ${#files[@]}]}"

	# Retry for up to ~5s (50 * 0.1s) until hyprpaper IPC accepts it
	for _ in {1..50}; do
		if hyprctl hyprpaper wallpaper ",$random_file" >/dev/null 2>&1; then
			ln -sf "$random_file" "$HOME/Pictures/current_wallpaper"
			return 0
		fi
		sleep 0.1
	done

	# If we get here, it never worked
	return 1
}

set_wallpaper
