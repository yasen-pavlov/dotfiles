-- Hyprland Lua config entry point.
-- Module path resolution: Hyprland sets package.path so that
-- require("hyprland.<name>") loads ~/.config/hypr/hyprland/<name>.lua.

local programs = require("hyprland.programs")

require("hyprland.environment")
require("hyprland.monitors")
require("hyprland.input")
require("hyprland.look_and_feel")
require("hyprland.windows")
require("hyprland.autostart")
require("hyprland.keybindings")(programs)
