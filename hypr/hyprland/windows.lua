-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- 1password
hl.window_rule({
	match = { title = "Quick Access — 1Password" },
	stay_focused = true,
})
hl.window_rule({
	match = { title = "Quick Access — 1Password" },
	pin = true,
})

-- dolphin
hl.window_rule({
	match = { title = "Create New Folder — Dolphin" },
	stay_focused = true,
})

-- Counter-Strike 2
hl.window_rule({
	match = { title = "Counter-Strike 2" },
	center = true,
})
hl.window_rule({
	match = { title = "Counter-Strike 2" },
	immediate = true,
})

-- Deadlock
hl.window_rule({
	match = { title = "Deadlock" },
	immediate = true,
})

-- Old World
hl.window_rule({
	match = { title = "OldWorld" },
	immediate = true,
})

-- Steam apps
hl.window_rule({
	match = { class = "^(steam_app)" },
	immediate = true,
})

-- Steam client → always workspace 3 (main window only; title match keeps
-- the empty-title popups/menus off this rule). Add " silent" to the value
-- to assign without pulling focus to ws3 on launch.
hl.window_rule({
	match = { class = "^steam$", title = "^Steam$" },
	workspace = "3",
})

-- UT99 / OldUnreal: float at exactly the output size. The engine's exclusive
-- fullscreen hard-crashes on Wayland's async fullscreen ("Inconsistent SDL
-- window flags"; no SDL/engine-side fix exists — SDL_VIDEO_SYNC_WINDOW_OPERATIONS
-- tested, doesn't cover it). Floating the borderless window at 3840x2160@0,0
-- gives pixel-perfect gapless "fullscreen" with no SDL fullscreen involved.
-- Do NOT use the in-game fullscreen toggle (re-arms StartupFullscreen=True in
-- ~/.utpg/System/UnrealTournament.ini → next launch crashes; flip it back if so).
hl.window_rule({
	match = { class = "^(ut-bin-amd64)$" },
	float = true,
})
hl.window_rule({
	match = { class = "^(ut-bin-amd64)$" },
	size = "3840 2160",
})
hl.window_rule({
	match = { class = "^(ut-bin-amd64)$" },
	move = "0 0",
})
-- ...and 1s after the window opens, promote it to real compositor fullscreen
-- (engages vrr=2). A map-time `fullscreen` RULE crashes the engine
-- (ResizeViewport(0,0) — retested 2026-07-19); fullscreening the ESTABLISHED
-- window (same as a manual Mod+F) is safe. Guards: only if UT still holds
-- focus and isn't already fullscreen (the dispatcher is a toggle).
hl.on("window.open", function(w)
	if not w or w.class ~= "ut-bin-amd64" then return end
	hl.timer(function()
		local active = hl.get_active_window()
		if active and active.class == "ut-bin-amd64" and active.fullscreen == 0 then
			hl.dispatch(hl.dsp.window.fullscreen())
		end
	end, { timeout = 1000, type = "oneshot" })
end)

-- telegram
hl.window_rule({
	match = { class = "org.telegram.desktop" },
	suppress_event = "activate activatefocus",
})
hl.window_rule({
	match = { class = "com.ayugram.desktop" },
	suppress_event = "activate activatefocus",
})

-- IntelliJ floating subwindows
hl.window_rule({
	match = { class = "jetbrains-idea", title = "win\\d.*" },
	stay_focused = true,
})

-- ueberzugpp
hl.window_rule({
	match = { title = "^(.*ueberzugpp.*)$" },
	no_anim = true,
})

-- suppress maximize requests for everything
hl.window_rule({
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- Pdx-Unlimiter (xwayland phantoms)
hl.window_rule({
	match = { class = "^Pdx-Unlimiter$", title = "^$", xwayland = true },
	no_focus = true,
})
hl.window_rule({
	match = { class = "^Pdx-Unlimiter$", title = "^$", xwayland = true },
	no_shadow = true,
})
hl.window_rule({
	match = { class = "^Pdx-Unlimiter$", title = "^$", xwayland = true },
	no_blur = true,
})

-- discord
hl.window_rule({
	match = { class = "discord" },
	suppress_event = "activate activatefocus",
})

-- noctalia (v5): Settings is a regular xdg-toplevel, not a layer surface -> float + center it
hl.window_rule({
	match = { class = "dev.noctalia.Noctalia" },
	float = true,
	size = "1080 920",
	center = true,
})

-- noctalia (v5) bar: the shell asks Hyprland for a blur region over the whole bar body
-- (ext-background-effect), which the compositor honours even with background_opacity = 0
-- and which no layer rule can veto (CLayerSurface::shouldBlur). ignore_alpha keeps the
-- transparent bar body unblurred so only the 0.5-opacity capsules pick up blur, as in v4.
hl.layer_rule({
	match = { namespace = "^noctalia-bar-.*$" },
	ignore_alpha = 0.3,
})
