hl.on("hyprland.start", function()
	-- uwsm waits ~30 s for WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE in the
	-- systemd user environment and tears the session down if they never appear.
	-- Since Hyprland 9927f2eb8 the compositor no longer exports them when it runs
	-- as a systemd unit (which is how uwsm runs it), so do it the uwsm way. Skipped
	-- when a session already exported them, i.e. in a nested Hyprland.
	hl.exec_cmd("systemctl --user show-environment | grep -q '^WAYLAND_DISPLAY=' || uwsm finalize")
	-- All plugins are LOCAL builds, loaded directly. Rebuild after a Hyprland update
	-- with ~/Workbench/Scripts/update-hypr-plugins:
	--   cua:         Cua Driver input plugin (agent seats for background input), pinned
	--                release tag + local port commit (branch port-hyprland-git), cmake build/.
	--                Its agent seats appear when it loads with plugin.cua.enabled set
	--                (plugins.lua); apps started before that can't take background input.
	--                exec_cmd is asynchronous, so the apps started below race this load.
	--                None of them is a background-input target (layer shell, Electron,
	--                XWayland, tray). One that is must be started only after
	--                `hyprctl -j cua:status` reports transport.ready, not from a bare exec_cmd.
	--   hyprcapture: upstream master (branch upstream-master), cmake build-upstream/
	--   hyprexpo:    upstream master + local 0.57 port commits (branch port-057), make all
	-- The Cua module can never be unloaded (-z nodelete): a stale build loaded here
	-- would refuse itself but stay mapped, and a rebuilt one could then not be loaded
	-- until the next login. So load it only when it was built for the installed
	-- Hyprland; update-hypr-plugins writes that stamp and loads it otherwise.
	hl.exec_cmd("cmp -s /usr/include/hyprland/src/version.h $HOME/.local/share/hyprland-plugins/cua/libs/cua-driver/hyprland-plugin/build/built-for-version.h && hyprctl plugin load $HOME/.local/share/hyprland-plugins/cua/libs/cua-driver/hyprland-plugin/build/cua-hyprland-plugin.so")
	hl.exec_cmd("hyprctl plugin load $HOME/.local/share/hyprland-plugins/hyprcapture/build-upstream/libhyprcapture.so")
	hl.exec_cmd("hyprctl plugin load $HOME/.local/share/hyprland-plugins/hyprexpo/hyprexpo.so")
	-- Cua Driver daemon: always on, so agent sessions never start or stop it (one
	-- socket is shared by all of them) and the session accessibility switch
	-- (org.a11y.Status IsEnabled, on only while it runs) is on before Firefox starts,
	-- which is what gives Firefox its accessibility tree. Log: $XDG_RUNTIME_DIR/cua-driver.log
	hl.exec_cmd("env CUA_DRIVER_RS_ENABLE_WAYLAND=1 CUA_TELEMETRY_ENABLED=0 DO_NOT_TRACK=1 $HOME/.local/bin/cua-driver serve --no-overlay > $XDG_RUNTIME_DIR/cua-driver.log 2>&1")
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
	-- onedrive: runs as user unit onedrive-yasen.service (MemoryMax=2G), not via
	-- onedrivegui auto_sync — the 2.5.12 monitor leaked to ~20 GiB RSS.
	hl.exec_cmd("QT_QPA_PLATFORM=xcb synology-drive autostart")
end)
