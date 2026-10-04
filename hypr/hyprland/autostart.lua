hl.on("hyprland.start", function()
	-- Both plugins are LOCAL builds (hand-ported to Hyprland-git), loaded directly.
	-- hyprexpo is a local port until sandwichfarm/hyprexpo updates upstream for the
	-- new Hyprland API (then revert to hyprpm). After a Hyprland update, rebuild:
	--   hyprcapture: cmake --build ~/.local/share/hyprland-plugins/hyprcapture/build-v055
	--   hyprexpo:    ~/.local/share/hyprland-plugins/hyprexpo/rebuild.sh
	hl.exec_cmd("hyprctl plugin load $HOME/.local/share/hyprland-plugins/hyprcapture/build-v055/libhyprcapture.so")
	hl.exec_cmd("hyprctl plugin load $HOME/.local/share/hyprland-plugins/hyprexpo/hyprexpo.so")
	-- plugin.* config keys are eagerly validated at the initial parse, which
	-- happens before hyprpm reload runs above — so every cold start logs them
	-- as "unknown config key" and the error overlay sticks for the session.
	-- Touching the top-level config triggers Hyprland's inotify auto-reload,
	-- which re-validates with the plugins now loaded and clears the overlay.
	hl.exec_cmd("sleep 2 && touch $HOME/.config/hypr/hyprland.lua")
	-- network + bluetooth applets replaced by noctalia bar widgets
	-- hl.exec_cmd("nm-applet &")
	-- hl.exec_cmd("blueman-applet")
	-- bar / notifications / lock / wallpaper also handled by noctalia
	-- hl.exec_cmd("waybar")
	-- hl.exec_cmd("swaync")
	hl.exec_cmd("noctalia")
	hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 25")
	hl.exec_cmd("udiskie")
	-- 1Password: started here, NOT via 1P's own "start at login" (which keeps
	-- rewriting ~/.config/autostart/1password.desktop and dropping the
	-- --disable-features flag, washing out colours on cm=srgb 10-bit).
	hl.exec_cmd("1password --silent --disable-features=WaylandWpColorManagerV1")
	hl.exec_cmd("sleep 5 && onedrivegui")
	hl.exec_cmd("QT_QPA_PLATFORM=xcb synology-drive autostart")
end)
