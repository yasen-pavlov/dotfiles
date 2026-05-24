-- Plugin configuration. Settings apply only once the corresponding plugin is loaded;
-- they are inert otherwise, so this file is safe to load even on fresh machines.

hl.config({
	plugin = {
		hyprcapture = {
			-- Wrapper unsets QT_SCALE_FACTOR (overlay sizing) and re-sets
			-- QT_QPA_PLATFORMTHEME (plugin's spawn allowlist strips it, breaking dark mode).
			helper = os.getenv("HOME") .. "/Workbench/Scripts/hyprcapture-helper",
		},

		-- https://github.com/sandwichfarm/hyprexpo
		hyprexpo = {
			columns          = 2,
			gaps_in          = 6,
			gaps_out         = 12,
			bg_col           = "rgb(0d1117)",
			-- start the grid at workspace 1 instead of centering on the
			-- current one, so the same tile position always maps to the
			-- same workspace across openings. skip_empty = 0 keeps the
			-- grid aligned with workspace IDs (tile N = workspace N).
			workspace_method = "first 1",
			gesture_distance = 200,
			skip_empty       = 0,

			-- match the active-border gradient used in look_and_feel.lua
			border_width         = 2,
			border_color         = "rgba(2a2a2aff)",
			border_color_current = "rgba(4ab1faee) rgba(7194e9ee) 45deg",
			border_color_focus   = "rgba(ffcc66ff) rgba(ff9966ff) 45deg",
			border_color_hover   = "rgba(7194e966)",

			-- keyboard navigation + tile labels
			keynav_enable        = 1,
			keynav_wrap_h        = 1,
			keynav_wrap_v        = 1,
			keynav_reading_order = 0,

			label_enable        = 1,
			label_position      = "top-left",
			label_offset_x      = 10,
			label_offset_y      = 10,
			label_text_mode     = "token",
			label_show          = "always",
			label_font_size     = 20,
			label_font_bold     = 1,
			label_color_default = "rgb(e6edf3)",
			label_color_hover   = "rgb(ffffff)",
			label_color_focus   = "rgb(ffcc66)",
			label_color_current = "rgb(4ab1fa)",
			label_bg_enable     = 1,
			label_bg_color      = "rgba(0d1117cc)",
			label_bg_shape      = "rounded",
			label_bg_rounding   = 8,
			label_padding       = 10,
		},
	},
})
