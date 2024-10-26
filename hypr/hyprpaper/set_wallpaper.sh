#!/bin/bash

set_wallpaper() {
	wallpaper_dir="$HOME/Pictures/Wallpapers"

	# shellcheck disable=SC2206
	files=($wallpaper_dir/*)

	random_file=("${files[RANDOM % ${#files[@]}]}")
	# shellcheck disable=SC2128
	random_file_name=$(basename "$random_file")

	# shellcheck disable=SC2128
	hyprctl hyprpaper wallpaper ",$random_file"
	sed -i "s|\(path = \).*|\1~/Pictures/Wallpapers/$random_file_name|" "$HOME"/.config/hypr/hyprlock.conf
}

set_wallpaper
