-- See https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
	-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
	general = {
		gaps_in = 5,
		gaps_out = 10,
		border_size = 1,

		col = {
			active_border = { colors = { "rgba(4ab1faee)", "rgba(7194e9ee)" }, angle = 30 },
			inactive_border = "rgba(595959aa)",
		},

		resize_on_border = false,
		-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before turning this on
		allow_tearing = true,
		layout = "dwindle",
	},

	-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
	decoration = {
		rounding = 10,
		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},

		-- https://wiki.hypr.land/Configuring/Basics/Variables/#blur
		blur = {
			enabled = true,
			size = 3,
			passes = 1,
			vibrancy = 0.1696,
		},
	},

	group = {
		-- group window-border colors (distinct from the groupbar background below)
		col = {
			border_active          = { colors = { "rgba(4ab1faee)", "rgba(7194e9ee)" }, angle = 30 },
			border_inactive        = "rgba(595959aa)",
			border_locked_active   = { colors = { "rgba(fab95bee)", "rgba(f59e42ee)" }, angle = 30 }, -- amber = locked
			border_locked_inactive = "rgba(7a5a2aaa)",
		},

		-- behaviour: kill the two accidental-grouping footguns
		drag_into_group          = 2,     -- merge only when dropped ON the groupbar (default 1 = drag-onto-window footgun)
		group_on_movetoworkspace = false, -- moving a window to a workspace must NOT silently merge it

		groupbar = {
			enabled       = true,
			render_titles = true,   -- tab labels (was false)
			gradients     = true,   -- fill the active tab as a solid chip
			scrolling     = true,   -- mouse-wheel over the bar cycles tabs

			height               = 18,
			font_size            = 11,
			font_weight_active   = "bold",
			font_weight_inactive = "normal",

			indicator_height = 1,    -- want 0 (the rounded gradient pill IS the whole tab), but since
			                         -- Hyprland #15651 the lua config enforces the documented min of 1;
			                         -- 1px is the closest legal value to "no indicator sliver".
			                         -- TODO drop to 0 again if upstream relaxes the minimum

			-- per-tab rounded corners (like the old look) + space between tabs
			rounding                  = 10,    -- match the 10px window corner rounding
			round_only_edges          = false, -- round each tab, not just the strip edges
			gradient_rounding         = 10,    -- the gradient chip is the visible tab; match window rounding
			gradient_round_only_edges = false,
			gaps_in                   = 8,     -- distance BETWEEN adjacent tabs
			gaps_out                  = 6,     -- clearance between the tab and the window below (was 4)

			text_color          = "rgba(ffffffff)",
			text_color_inactive = "rgba(ffffff90)",

			col = {
				active          = { colors = { "rgba(4ab1faee)", "rgba(7194e9ee)" }, angle = 30 },
				inactive        = "rgba(595959aa)",
				locked_active   = { colors = { "rgba(fab95bee)", "rgba(f59e42ee)" }, angle = 30 }, -- amber when locked
				locked_inactive = "rgba(7a5a2aaa)",
			},
		},
	},

	-- Makes the existing SUPER+H/J/K/L focus cycle a group's tabs first, then
	-- leave the group at the ends — i3-style unified navigation, no extra bind.
	binds = {
		movefocus_cycles_groupfirst = true,
	},

	-- https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/
	dwindle = {
		preserve_split = true,
	},

	-- https://wiki.hypr.land/Configuring/Layouts/Master-Layout/
	master = {
		new_status = "master",
	},

	-- https://wiki.hypr.land/Configuring/Basics/Variables/#misc
	misc = {
		force_default_wallpaper = -1, -- 0 or 1 disables anime mascot wallpapers
		disable_hyprland_logo = true, -- disables the random hyprland logo background
		focus_on_activate = true,
	},

	cursor = {
		no_warps = true,
		-- false: hardware cursor plane moves independently of compositor frames.
		-- With software cursors (true), fullscreen + vrr=2 + no_break_fs_vrr made
		-- the cursor update only at the app's framerate (30fps video = 30fps
		-- cursor, still image = frozen). Verified fine on RDNA4 incl. over HDR
		-- (cm_auto_hdr) content, 2026-07-11.
		no_hardware_cursors = false,
		-- false: cursor movement may schedule frames during fullscreen VRR.
		-- Even a hardware cursor only becomes visible at scanout, and vrr=2
		-- holds scanout at the content's rate — a fullscreen still/low-fps
		-- video pinned the cursor to 24-60Hz (AyuGram media viewer, mpv).
		-- Cost: refresh ramps on cursor move over fullscreen VRR content;
		-- the OLED shimmer that comes with VRR was there regardless.
		no_break_fs_vrr = false,
	},

	-- unscale XWayland
	xwayland = {
		force_zero_scaling = true,
	},

	render = {
		-- false: keep the compositor in the render loop while fullscreen. With direct
		-- scanout on, a fullscreen game's buffer goes straight to the display plane;
		-- when a notification/overlay/workspace switch forces compositing back on, the
		-- plane source switch blanks the OLED for ~1s (black flash) on slow-to-switch
		-- games. Disabling trades a touch of latency (irrelevant on a 9070 XT) for no flash.
		direct_scanout = false,
		cm_auto_hdr = 1, -- SDR desktop; auto-switch output to HDR for fullscreen HDR content
	},

	-- With cm="srgb" the monitor's preferred image description is SDR, so CM-aware
	-- apps (mpv target-colorspace-hint=auto, DXVK) are told HDR isn't preferred and
	-- never emit an HDR surface -> cm_auto_hdr has nothing to promote. prefer_hdr
	-- advertises the HDR image description to clients while keeping the sRGB desktop.
	-- (maintainer-recommended for "auto fullscreen HDR not engaging on cm=srgb")
	-- 1 = all clients, 2 = gamescope windows only.
	quirks = {
		prefer_hdr = 1,
	},

	-- debug = {
	-- 	full_cm_proto = true,
	-- 	vfr = false,
	-- },

	animations = {
		enabled = true,
	},
})

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

-- GTK theme
hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark'")
hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
