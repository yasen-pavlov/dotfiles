-- Plugin configuration. Settings apply only once the corresponding plugin is loaded;
-- they are inert otherwise, so this file is safe to load even on fresh machines.

hl.config({
	plugin = {
		hyprcapture = {
			-- Wrapper unsets QT_SCALE_FACTOR (overlay sizing) and re-sets
			-- QT_QPA_PLATFORMTHEME (plugin's spawn allowlist strips it, breaking dark mode).
			helper = os.getenv("HOME") .. "/Workbench/Scripts/hyprcapture-helper",
		},
	},
})
