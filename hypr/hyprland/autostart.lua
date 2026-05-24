hl.on("hyprland.start", function()
  -- Load hyprpm-managed plugins first (currently: hyprexpo). This also
  -- unloads any non-hyprpm plugins, so we manually reload HyprCapture after.
  hl.exec_cmd("hyprpm reload")
  hl.exec_cmd("hyprctl plugin load $HOME/.local/share/hyprland-plugins/hyprcapture/build-v055/libhyprcapture.so")
  -- network + bluetooth applets replaced by noctalia bar widgets
  -- hl.exec_cmd("nm-applet &")
  -- hl.exec_cmd("blueman-applet")
  -- bar / notifications / lock / wallpaper also handled by noctalia
  -- hl.exec_cmd("waybar")
  -- hl.exec_cmd("swaync")
  hl.exec_cmd("qs -c noctalia-shell")
  hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 25")
  hl.exec_cmd("udiskie")
  hl.exec_cmd("sleep 5 && onedrivegui")
  hl.exec_cmd("QT_QPA_PLATFORM=xcb synology-drive autostart")
end)
