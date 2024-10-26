#!/bin/bash

preload_wallpapers() {
	wallpaper_dir="$HOME/Pictures/Wallpapers"

	wallpapers=$(find "$wallpaper_dir" -type f)

	for wallpaper in $wallpapers; do

		# shellcheck disable=SC2027
		preload_string+="preload = "$wallpaper"\n"
		wallpaper_string+="wallpaper = , $wallpaper\n"
	done

	echo -en "$preload_string$wallpaper_string" >~/.config/hypr/hyprpaper.conf
}

preload_wallpapers

killall hyprpaper
hyprctl dispatch exec hyprpaper
