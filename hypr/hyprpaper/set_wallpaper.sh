#!/bin/bash

set_wallpaper() {
	wallpaper_dir="$HOME/Pictures/Wallpapers"

	files=("$wallpaper_dir"/*)

	random_file="${files[RANDOM % ${#files[@]}]}"

	hyprctl hyprpaper wallpaper ",$random_file"
	ln -sf "$random_file" "$HOME"/Pictures/current_wallpaper
}

set_wallpaper
