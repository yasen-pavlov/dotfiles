-- See https://wiki.hypr.land/Configuring/Basics/Binds/
-- Section headers below use the `-- N. NAME` format so the noctalia
-- keybind-cheatsheet plugin can group binds into categories.

return function(p)
	local mod = "SUPER"

	-- 1. Session
	hl.bind(mod .. " + CTRL + ALT + M", hl.dsp.exec_cmd("uwsm stop"), { locked = true, description = "Log out (stop uwsm session)" })

	-- 2. Applications
	hl.bind(mod .. " + Q",         hl.dsp.exec_cmd(p.terminal),                       { description = "Terminal" })
	hl.bind(mod .. " + E",         hl.dsp.exec_cmd(p.fileManager),                    { description = "File manager" })
	hl.bind(mod .. " + B",         hl.dsp.exec_cmd(p.browser),                        { description = "Browser" })
	hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd(p.browser .. " -private-window"),  { description = "Browser (private window)" })
	hl.bind(mod .. " + M",         hl.dsp.exec_cmd(p.email),                          { description = "Email" })
	hl.bind(mod .. " + G",         hl.dsp.exec_cmd("steam"),                          { description = "Steam" })
	hl.bind(mod .. " + comma",     hl.dsp.exec_cmd("DESKTOPINTEGRATION=1 AyuGram"),   { description = "AyuGram (Telegram)" })
	hl.bind(mod .. " + W",         hl.dsp.exec_cmd("1password --quick-access"),       { description = "1Password quick access" })
	hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("bemoji -tn"),                     { description = "Emoji picker (bemoji)" })

	-- 3. Window Management
	hl.bind(mod .. " + C", hl.dsp.window.close(),                      { description = "Close focused window" })
	hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
	hl.bind(mod .. " + F", hl.dsp.window.fullscreen(),                 { description = "Toggle fullscreen" })
	hl.bind(mod .. " + Z", hl.dsp.window.pseudo(),                     { description = "Toggle pseudo-tile" })
	hl.bind(mod .. " + X", hl.dsp.layout("togglesplit"),               { description = "Toggle split direction" })

	-- 4. Groups
	hl.bind(mod .. " + T", hl.dsp.group.toggle(), { description = "Toggle window group" })
	hl.bind(mod .. " + N", hl.dsp.group.next(),   { description = "Next window in group" })
	hl.bind(mod .. " + P", hl.dsp.group.prev(),   { description = "Previous window in group" })

	-- 5. System
	hl.bind(mod .. " + SHIFT + T", hl.dsp.exec_cmd("[float; size 1400 1000; center] foot -e btop"), { description = "Task manager (btop, floating)" })

	-- 6. Navigation (Focus)
	hl.bind(mod .. " + H", hl.dsp.focus({ direction = "left" }),  { description = "Focus left" })
	hl.bind(mod .. " + L", hl.dsp.focus({ direction = "right" }), { description = "Focus right" })
	hl.bind(mod .. " + K", hl.dsp.focus({ direction = "up" }),    { description = "Focus up" })
	hl.bind(mod .. " + J", hl.dsp.focus({ direction = "down" }),  { description = "Focus down" })

	-- 7. Moving Windows
	hl.bind(mod .. " + SHIFT + H", hl.dsp.window.move({ direction = "left",  group_aware = true }), { description = "Move window left (or into group)" })
	hl.bind(mod .. " + SHIFT + L", hl.dsp.window.move({ direction = "right", group_aware = true }), { description = "Move window right (or into group)" })
	hl.bind(mod .. " + SHIFT + K", hl.dsp.window.move({ direction = "up",    group_aware = true }), { description = "Move window up (or into group)" })
	hl.bind(mod .. " + SHIFT + J", hl.dsp.window.move({ direction = "down",  group_aware = true }), { description = "Move window down (or into group)" })

	-- 8. Workspaces
	for i = 1, 10 do
		local key = i % 10
		hl.bind(mod .. " + " .. key,         hl.dsp.focus({ workspace = i }),       { description = "Go to workspace " .. i })
		hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
	end
	hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace (mouse wheel)" })
	hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace (mouse wheel)" })

	-- 9. Scratchpad
	hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"),            { description = "Toggle scratchpad (special:magic)" })
	hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Send window to scratchpad" })

	-- 10. Mouse
	hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag window (LMB)" })
	hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window (RMB)" })

	-- 11. Noctalia Integration
	hl.bind("ALT + Space",         hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher toggle"),                  { description = "App launcher" })
	hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd("qs -c noctalia-shell ipc call notifications toggleHistory"),      { description = "Notification history" })
	hl.bind(mod .. " + A",         hl.dsp.exec_cmd("qs -c noctalia-shell ipc call controlCenter toggle"),             { description = "Control center" })
	hl.bind(mod .. " + D",         hl.dsp.exec_cmd("qs -c noctalia-shell ipc call calendar toggle"),                  { description = "Calendar" })
	hl.bind(mod .. " + I",         hl.dsp.exec_cmd("qs -c noctalia-shell ipc call settings toggle"),                  { description = "Noctalia settings" })
	hl.bind(mod .. " + ESCAPE",    hl.dsp.exec_cmd("qs -c noctalia-shell ipc call sessionMenu toggle"),               { description = "Session menu (lock / logout / shutdown)" })
	hl.bind(mod .. " + CTRL + L",  hl.dsp.exec_cmd("qs -c noctalia-shell ipc call lockScreen lock"),                  { description = "Lock screen" })
	hl.bind(mod .. " + slash",     hl.dsp.exec_cmd("qs -c noctalia-shell ipc call plugin:keybind-cheatsheet toggle"), { description = "Keybind cheatsheet" })
	hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd("qs -c noctalia-shell ipc call wallpaper random"),                 { description = "Random wallpaper" })

	-- 12. Display
	hl.bind("CTRL + ALT + SHIFT + D", hl.dsp.exec_cmd("ddcutil setvcp 60 0x10"),     { locked = true, description = "Switch monitor input → notebook (DDC/CI)" })
	hl.bind("XF86MonBrightnessUp",    hl.dsp.exec_cmd("ddcutil setvcp 10 + 10"),     { locked = true, description = "Monitor brightness up (DDC/CI)" })
	hl.bind("XF86MonBrightnessDown",  hl.dsp.exec_cmd("ddcutil setvcp 10 - 10"),     { locked = true, description = "Monitor brightness down (DDC/CI)" })

	-- 13. Screenshots & Recording
	hl.bind(mod .. " + PRINT", function()
		hl.plugin.hyprcapture.open("window")
	end, { description = "Screenshot focused window" })
	hl.bind("PRINT", function()
		hl.plugin.hyprcapture.open("fullscreen")
	end, { description = "Screenshot full screen" })
	hl.bind(mod .. " + SHIFT + PRINT", function()
		hl.plugin.hyprcapture.open("region")
	end, { description = "Screenshot region" })
	hl.bind("CTRL + SHIFT + PRINT", function()
		hl.plugin.hyprcapture.record_toggle()
	end, { description = "Toggle screen recording" })

	-- 14. Multimedia
	hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pamixer -i 1"),         { locked = true, repeating = true, description = "Volume up" })
	hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pamixer -d 1"),         { locked = true, repeating = true, description = "Volume down" })
	hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("pamixer -t"),           { locked = true, description = "Mute / unmute audio" })
	hl.bind("XF86AudioPlay",        hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play / pause" })
	hl.bind("XF86AudioNext",        hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Next track" })
	hl.bind("XF86AudioPrev",        hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Previous track" })
	hl.bind("ALT + SHIFT + O",      hl.dsp.exec_cmd("playerctl play-pause"), { description = "Play / pause (keyboard)" })

	-- 15. Pdx-Unlimiter
	hl.bind("CTRL + SHIFT + I", hl.dsp.pass({ window = "class:^(Pdx-Unlimiter)$" }), { description = "Forward Ctrl+Shift+I → Pdx-Unlimiter" })
	hl.bind("CTRL + SHIFT + K", hl.dsp.pass({ window = "class:^(Pdx-Unlimiter)$" }), { description = "Forward Ctrl+Shift+K → Pdx-Unlimiter" })
end
