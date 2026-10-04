-- See https://wiki.hypr.land/Configuring/Basics/Binds/
-- Section headers below use the `-- N. NAME` format so the noctalia
-- keybind-cheatsheet plugin can group binds into categories.

return function(p)
	local mod = "SUPER"

	-- 1. Session
	hl.bind(
		mod .. " + CTRL + ALT + M",
		hl.dsp.exec_cmd("uwsm stop"),
		{ locked = true, description = "Log out (stop uwsm session)" }
	)

	-- 2. Applications
	hl.bind(mod .. " + Q", hl.dsp.exec_cmd(p.terminal), { description = "Terminal" })
	hl.bind(mod .. " + E", hl.dsp.exec_cmd(p.fileManager), { description = "File manager" })
	hl.bind(mod .. " + B", hl.dsp.exec_cmd(p.browser), { description = "Browser" })
	hl.bind(
		mod .. " + SHIFT + B",
		hl.dsp.exec_cmd(p.browser .. " -private-window"),
		{ description = "Browser (private window)" }
	)
	hl.bind(mod .. " + M", hl.dsp.exec_cmd(p.email), { description = "Email" })
	hl.bind(mod .. " + T", hl.dsp.exec_cmd("steam"), { description = "Steam" })
	hl.bind(mod .. " + comma", hl.dsp.exec_cmd("DESKTOPINTEGRATION=1 AyuGram"), { description = "AyuGram (Telegram)" })
	hl.bind(
		mod .. " + W",
		hl.dsp.exec_cmd("1password --quick-access --disable-features=WaylandWpColorManagerV1"),
		{ description = "1Password quick access" }
	)
	hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("bemoji -tn"), { description = "Emoji picker (bemoji)" })

	-- 3. Window Management
	hl.bind(mod .. " + C", hl.dsp.window.close(), { description = "Close focused window" })
	hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
	hl.bind(mod .. " + F", hl.dsp.window.fullscreen(), { description = "Toggle fullscreen" })
	hl.bind(mod .. " + Z", hl.dsp.window.pseudo(), { description = "Toggle pseudo-tile" })
	hl.bind(mod .. " + X", hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })

	-- 4. Groups
	-- Enter group mode (sticky submap); Escape (or any unbound key) exits.
	-- Mirrors the hyprexpo submap idiom below: bare keys, hjkl, 1..0, escape.
	-- Mental model: lowercase = focus / pull-in, SHIFT = move / reorder
	-- (same focus-vs-move split as the global hjkl / SHIFT+hjkl binds).
	hl.bind(mod .. " + G", hl.dsp.submap("grp"), { description = "Group mode" })

	hl.define_submap("grp", "reset", function()
		-- create / dissolve a group on the focused window
		hl.bind("g", hl.dsp.group.toggle(), { description = "Group: toggle (create / dissolve)" })

		-- pull the focused window INTO an adjacent group (no-op if none that way; press g first to create)
		hl.bind("h", hl.dsp.window.move({ into_group = "l" }), { description = "Group: pull in (left)" })
		hl.bind("j", hl.dsp.window.move({ into_group = "d" }), { description = "Group: pull in (down)" })
		hl.bind("k", hl.dsp.window.move({ into_group = "u" }), { description = "Group: pull in (up)" })
		hl.bind("l", hl.dsp.window.move({ into_group = "r" }), { description = "Group: pull in (right)" })

		-- pop the focused window OUT of the group (directional + quick directionless q)
		hl.bind("SHIFT + h", hl.dsp.window.move({ out_of_group = "l" }), { description = "Group: pop out (left)" })
		hl.bind("SHIFT + j", hl.dsp.window.move({ out_of_group = "d" }), { description = "Group: pop out (down)" })
		hl.bind("SHIFT + k", hl.dsp.window.move({ out_of_group = "u" }), { description = "Group: pop out (up)" })
		hl.bind("SHIFT + l", hl.dsp.window.move({ out_of_group = "r" }), { description = "Group: pop out (right)" })
		hl.bind("q", hl.dsp.window.move({ out_of_group = true }), { description = "Group: pop out" })

		-- cycle focus through tabs (lowercase = focus)
		hl.bind("n", hl.dsp.group.next(), { description = "Group: next tab" })
		hl.bind("Tab", hl.dsp.group.next(), { description = "Group: next tab" })
		hl.bind("p", hl.dsp.group.prev(), { description = "Group: previous tab" })
		hl.bind("SHIFT + Tab", hl.dsp.group.prev(), { description = "Group: previous tab" })

		-- REORDER the active tab within the group (SHIFT = move the thing, not the cursor)
		hl.bind("SHIFT + n", hl.dsp.group.move_window({ forward = true }), { description = "Group: move tab forward" })
		hl.bind(
			"SHIFT + p",
			hl.dsp.group.move_window({ forward = false }),
			{ description = "Group: move tab backward" }
		)

		-- jump to tab by index (1..9, 0 => 10) — same pattern as the hyprexpo submap
		for i = 1, 10 do
			local key = tostring(i % 10)
			hl.bind(key, hl.dsp.group.active({ index = i }), { description = "Group: focus tab " .. i })
		end

		-- lock the active stack (stop it swallowing new windows)
		hl.bind(
			"Space",
			hl.dsp.group.lock_active({ action = "toggle" }),
			{ description = "Group: lock / unlock stack" }
		)

		-- close the active tab (NOT the whole group)
		hl.bind("c", hl.dsp.window.close(), { description = "Group: close active tab" })

		-- forbid the focused window from ever grouping
		hl.bind(
			"x",
			hl.dsp.window.deny_from_group({ action = "toggle" }),
			{ description = "Group: deny from grouping" }
		)

		-- exit
		hl.bind("escape", hl.dsp.submap("reset"), { description = "Group: exit mode" })
	end)

	-- 5. System
	hl.bind(
		mod .. " + SHIFT + T",
		hl.dsp.exec_cmd("[float; size 1400 1000; center] alacritty -e btop"),
		{ description = "Task manager (btop, floating)" }
	)

	-- 6. Navigation (Focus)
	hl.bind(mod .. " + H", hl.dsp.focus({ direction = "left" }), { description = "Focus left" })
	hl.bind(mod .. " + L", hl.dsp.focus({ direction = "right" }), { description = "Focus right" })
	hl.bind(mod .. " + K", hl.dsp.focus({ direction = "up" }), { description = "Focus up" })
	hl.bind(mod .. " + J", hl.dsp.focus({ direction = "down" }), { description = "Focus down" })

	-- 7. Moving Windows
	hl.bind(
		mod .. " + SHIFT + H",
		hl.dsp.window.move({ direction = "left", group_aware = true }),
		{ description = "Move window left (or into group)" }
	)
	hl.bind(
		mod .. " + SHIFT + L",
		hl.dsp.window.move({ direction = "right", group_aware = true }),
		{ description = "Move window right (or into group)" }
	)
	hl.bind(
		mod .. " + SHIFT + K",
		hl.dsp.window.move({ direction = "up", group_aware = true }),
		{ description = "Move window up (or into group)" }
	)
	hl.bind(
		mod .. " + SHIFT + J",
		hl.dsp.window.move({ direction = "down", group_aware = true }),
		{ description = "Move window down (or into group)" }
	)

	-- 8. Workspaces
	for i = 1, 10 do
		local key = i % 10
		hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }), { description = "Go to workspace " .. i })
		hl.bind(
			mod .. " + SHIFT + " .. key,
			hl.dsp.window.move({ workspace = i }),
			{ description = "Move window to workspace " .. i }
		)
	end
	hl.bind(
		mod .. " + mouse_down",
		hl.dsp.focus({ workspace = "e+1" }),
		{ description = "Next workspace (mouse wheel)" }
	)
	hl.bind(
		mod .. " + mouse_up",
		hl.dsp.focus({ workspace = "e-1" }),
		{ description = "Previous workspace (mouse wheel)" }
	)

	-- 9. Scratchpad
	hl.bind(
		mod .. " + S",
		hl.dsp.workspace.toggle_special("magic"),
		{ description = "Toggle scratchpad (special:magic)" }
	)
	hl.bind(
		mod .. " + SHIFT + S",
		hl.dsp.window.move({ workspace = "special:magic" }),
		{ description = "Send window to scratchpad" }
	)

	-- 10. Mouse
	hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag window (LMB)" })
	hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window (RMB)" })

	-- 11. Noctalia Integration
	-- (v5 IPC: `noctalia msg …`, see `noctalia msg --help`; the cheatsheet plugin reads the line above as the category name)
	hl.bind("ALT + Space", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"), { description = "App launcher" })
	hl.bind(
		mod .. " + SHIFT + N",
		hl.dsp.exec_cmd("noctalia msg panel-toggle control-center notifications"),
		{ description = "Notification history" }
	)
	hl.bind(
		mod .. " + A",
		hl.dsp.exec_cmd("noctalia msg panel-toggle control-center"),
		{ description = "Control center" }
	)
	hl.bind(
		mod .. " + D",
		hl.dsp.exec_cmd("noctalia msg panel-toggle control-center calendar"),
		{ description = "Calendar" }
	)
	hl.bind(mod .. " + I", hl.dsp.exec_cmd("noctalia msg settings-toggle"), { description = "Noctalia settings" })
	hl.bind(
		mod .. " + ESCAPE",
		hl.dsp.exec_cmd("noctalia msg panel-toggle session"),
		{ description = "Session menu (lock / logout / shutdown)" }
	)
	hl.bind(mod .. " + CTRL + L", hl.dsp.exec_cmd("noctalia msg session lock"), { description = "Lock screen" })
	hl.bind(
		mod .. " + slash",
		hl.dsp.exec_cmd("noctalia msg panel-toggle kenn/keybind-cheatsheet:cheatsheet"),
		{ description = "Keybind cheatsheet" }
	)
	hl.bind(
		mod .. " + SHIFT + W",
		hl.dsp.exec_cmd("noctalia msg wallpaper-random"),
		{ description = "Random wallpaper" }
	)

	-- 12. Display
	hl.bind(
		"CTRL + ALT + SHIFT + D",
		hl.dsp.exec_cmd("ddcutil setvcp 60 0x10"),
		{ locked = true, description = "Switch monitor input → notebook (DDC/CI)" }
	)
	hl.bind(
		"XF86MonBrightnessUp",
		hl.dsp.exec_cmd("ddcutil setvcp 10 + 10"),
		{ locked = true, description = "Monitor brightness up (DDC/CI)" }
	)
	hl.bind(
		"XF86MonBrightnessDown",
		hl.dsp.exec_cmd("ddcutil setvcp 10 - 10"),
		{ locked = true, description = "Monitor brightness down (DDC/CI)" }
	)

	-- 13. Screenshots & Recording
	-- window / region / recording use hyprcapture's own overlay menu (the plugin).
	-- Fullscreen stays on grim because hyprcapture's offscreen re-render can't reproduce a
	-- fullscreen HDR game surface (goes flat/gray) — grim copies the real composited frame.
	hl.bind(mod .. " + PRINT", function()
		hl.plugin.hyprcapture.open("window")
	end, { description = "Screenshot focused window" })
	hl.bind(
		"PRINT",
		hl.dsp.exec_cmd(os.getenv("HOME") .. "/Workbench/Scripts/screenshot-fullscreen"),
		{ description = "Screenshot fullscreen (grim, HDR-correct) + preview" }
	)
	hl.bind(mod .. " + SHIFT + PRINT", function()
		hl.plugin.hyprcapture.open("region")
	end, { description = "Screenshot region" })
	hl.bind("CTRL + SHIFT + PRINT", function()
		hl.plugin.hyprcapture.record_toggle()
	end, { description = "Toggle screen recording" })

	-- 14. Multimedia
	hl.bind(
		"XF86AudioRaiseVolume",
		hl.dsp.exec_cmd("pamixer -i 1"),
		{ locked = true, repeating = true, description = "Volume up" }
	)
	hl.bind(
		"XF86AudioLowerVolume",
		hl.dsp.exec_cmd("pamixer -d 1"),
		{ locked = true, repeating = true, description = "Volume down" }
	)
	hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pamixer -t"), { locked = true, description = "Mute / unmute audio" })
	hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play / pause" })
	hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, description = "Next track" })
	hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, description = "Previous track" })
	hl.bind("ALT + SHIFT + O", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Play / pause (keyboard)" })

	-- 15. Pdx-Unlimiter
	hl.bind(
		"CTRL + SHIFT + I",
		hl.dsp.pass({ window = "class:^(Pdx-Unlimiter)$" }),
		{ description = "Forward Ctrl+Shift+I → Pdx-Unlimiter" }
	)
	hl.bind(
		"CTRL + SHIFT + K",
		hl.dsp.pass({ window = "class:^(Pdx-Unlimiter)$" }),
		{ description = "Forward Ctrl+Shift+K → Pdx-Unlimiter" }
	)

	-- 16. Overview (HyprExpo)
	-- dont_inhibit bypasses zwp_keyboard_shortcuts_inhibit so the overview opens
	-- even from inside fullscreen games / VMs that grab keyboard shortcuts.
	hl.bind(mod .. " + TAB", function()
		hl.plugin.hyprexpo.expo("toggle")
	end, { dont_inhibit = true, description = "Workspace overview (HyprExpo)" })

	-- Active submap while the overview is open. Plugin auto-enters this map
	-- on open because keynav_enable = 1 (see plugins.lua).
	hl.define_submap("hyprexpo", function()
		-- vim + arrow focus
		hl.bind("h", function()
			hl.plugin.hyprexpo.kb_focus("left")
		end, { description = "Overview: focus left" })
		hl.bind("j", function()
			hl.plugin.hyprexpo.kb_focus("down")
		end, { description = "Overview: focus down" })
		hl.bind("k", function()
			hl.plugin.hyprexpo.kb_focus("up")
		end, { description = "Overview: focus up" })
		hl.bind("l", function()
			hl.plugin.hyprexpo.kb_focus("right")
		end, { description = "Overview: focus right" })
		hl.bind("left", function()
			hl.plugin.hyprexpo.kb_focus("left")
		end, { description = "Overview: focus left" })
		hl.bind("down", function()
			hl.plugin.hyprexpo.kb_focus("down")
		end, { description = "Overview: focus down" })
		hl.bind("up", function()
			hl.plugin.hyprexpo.kb_focus("up")
		end, { description = "Overview: focus up" })
		hl.bind("right", function()
			hl.plugin.hyprexpo.kb_focus("right")
		end, { description = "Overview: focus right" })

		-- direct selection by workspace ID (1-9, 0 maps to 10).
		-- `kb_selectn` uses workspace IDs (handles sparse layouts); `kb_selecti`
		-- would use visible-tile position instead, which misroutes when not all
		-- workspaces 1-N exist.
		for i = 1, 10 do
			local key = tostring(i % 10)
			hl.bind(key, function()
				hl.plugin.hyprexpo.kb_selectn(i)
			end, { description = "Overview: go to workspace " .. i })
		end

		-- confirm / cancel
		hl.bind("return", function()
			hl.plugin.hyprexpo.kb_confirm()
		end, { description = "Overview: select focused tile" })
		hl.bind("escape", function()
			hl.plugin.hyprexpo.expo("off")
		end, { description = "Overview: close" })
	end)
end
