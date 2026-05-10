-- See https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
  -- https://wiki.hypr.land/Configuring/Basics/Variables/#general
  general = {
    gaps_in     = 5,
    gaps_out    = 10,
    border_size = 1,

    col = {
      active_border   = { colors = { "rgba(4ab1faee)", "rgba(7194e9ee)" }, angle = 30 },
      inactive_border = "rgba(595959aa)",
    },

    resize_on_border = false,
    -- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before turning this on
    allow_tearing    = true,
    layout           = "dwindle",
  },

  -- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
  decoration = {
    rounding         = 10,
    active_opacity   = 1.0,
    inactive_opacity = 1.0,

    shadow = {
      enabled      = true,
      range        = 4,
      render_power = 3,
      color        = "rgba(1a1a1aee)",
    },

      -- https://wiki.hypr.land/Configuring/Basics/Variables/#blur
    blur = {
      enabled  = true,
      size     = 3,
      passes   = 1,
      vibrancy = 0.1696,
    },
  },

  group = {
    groupbar = {
      indicator_height = 12,
      rounding         = 4,
      round_only_edges = false,
      render_titles    = false,
      col = {
        active   = { colors = { "rgba(4ab1faee)", "rgba(7194e9ee)" }, angle = 30 },
        inactive = "rgba(595959aa)",
      },
    },
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
    force_default_wallpaper = -1,    -- 0 or 1 disables anime mascot wallpapers
    disable_hyprland_logo   = true,  -- disables the random hyprland logo background
    focus_on_activate       = true,
  },

  cursor = {
    no_warps            = true,
    no_hardware_cursors = true,
    no_break_fs_vrr     = true,
  },

  -- unscale XWayland
  xwayland = {
    force_zero_scaling = true,
  },

  render = {
    direct_scanout = true,
  },

  debug = {
    full_cm_proto = true,
    vfr           = false,
  },

  animations = {
    enabled = true,
  },
})

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { { 0.23, 1 },    { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear",         { type = "bezier", points = { { 0, 0 },       { 1, 1 } } })
hl.curve("almostLinear",   { type = "bezier", points = { { 0.5, 0.5 },   { 0.75, 1 } } })
hl.curve("quick",          { type = "bezier", points = { { 0.15, 0 },    { 0.1, 1 } } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

-- GTK theme
hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'Materia-dark'")
hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
