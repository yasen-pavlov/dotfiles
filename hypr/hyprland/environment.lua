hl.env("XCURSOR_SIZE", "20")

hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("GDK_BACKEND", "wayland")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_MENU_PREFIX", "arch-")

hl.env("QT_QPA_PLATFORMTHEME", "hyprqt6engine")
hl.env("GTK_THEME", "Materia-dark")

hl.env("GDK_SCALE", "1")
hl.env("GDK_DPI_SCALE", "1.2")
hl.env("QT_SCALE_FACTOR", "1.2")

hl.env("STEAM_FORCE_DESKTOPUI_SCALING", "1.2")

hl.env("HYPRSHOT_DIR", os.getenv("HOME") .. "/Pictures/Screenshots")
