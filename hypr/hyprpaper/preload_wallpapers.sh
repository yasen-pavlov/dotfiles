#!/bin/bash
set -euo pipefail

wallpaper_dir="$HOME/Pictures/Wallpapers"
out="$HOME/.config/hypr/hyprpaper/hyprpaper-preload.conf"

mkdir -p "$(dirname "$out")"

mapfile -d '' imgs < <(
	find "$wallpaper_dir" -type f \
		\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
		-print0
)

tmp="$(mktemp)"
{
	echo "# GENERATED — do not edit"
	for wp in "${imgs[@]}"; do
		printf 'preload = %s\n' "$wp"
	done
} >"$tmp"

mv "$tmp" "$out"

systemctl --user restart hyprpaper
