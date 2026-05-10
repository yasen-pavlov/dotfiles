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
