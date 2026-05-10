-- See https://wiki.hypr.land/Configuring/Basics/Binds/

return function(p)
  local mod = "SUPER"

  -- session
  hl.bind(mod .. " + CTRL + ALT + M", hl.dsp.exec_cmd("uwsm stop"), { locked = true })

  -- programs
  hl.bind(mod .. " + Q", hl.dsp.exec_cmd(p.terminal))
  hl.bind(mod .. " + C", hl.dsp.window.close())
  hl.bind(mod .. " + E", hl.dsp.exec_cmd(p.fileManager))
  hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
  hl.bind(mod .. " + F", hl.dsp.window.fullscreen())
  hl.bind("ALT + Space", hl.dsp.exec_cmd("pkill wofi || " .. p.menu))
  hl.bind(mod .. " + Z", hl.dsp.window.pseudo())
  hl.bind(mod .. " + X", hl.dsp.layout("togglesplit"))

  -- groups
  hl.bind(mod .. " + T", hl.dsp.group.toggle())
  hl.bind(mod .. " + N", hl.dsp.group.next())
  hl.bind(mod .. " + P", hl.dsp.group.prev())

  -- focus (vim keys)
  hl.bind(mod .. " + H", hl.dsp.focus({ direction = "left" }))
  hl.bind(mod .. " + L", hl.dsp.focus({ direction = "right" }))
  hl.bind(mod .. " + K", hl.dsp.focus({ direction = "up" }))
  hl.bind(mod .. " + J", hl.dsp.focus({ direction = "down" }))

  -- move-window-or-into-group (group_aware = movewindoworgroup)
  hl.bind(mod .. " + SHIFT + H", hl.dsp.window.move({ direction = "left",  group_aware = true }))
  hl.bind(mod .. " + SHIFT + L", hl.dsp.window.move({ direction = "right", group_aware = true }))
  hl.bind(mod .. " + SHIFT + K", hl.dsp.window.move({ direction = "up",    group_aware = true }))
  hl.bind(mod .. " + SHIFT + J", hl.dsp.window.move({ direction = "down",  group_aware = true }))

  -- workspace switch / move (1..10, key 0 = ws 10)
  for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,             hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
  end

  -- special workspace (scratchpad)
  hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
  hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

  -- mouse-wheel workspace cycling
  hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
  hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

  -- mouse drag move/resize
  hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
  hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

  -- 1password quick access
  hl.bind(mod .. " + W", hl.dsp.exec_cmd("1password --quick-access"))

  -- notifications
  hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd("swaync-client -t -sw"))

  -- switch monitor display input to notebook (via DDC/CI VCP feature 60)
  hl.bind("CTRL + ALT + SHIFT + D", hl.dsp.exec_cmd("ddcutil setvcp 60 0x10"), { locked = true })

  -- screenshots
  hl.bind(mod .. " + PRINT",         hl.dsp.exec_cmd("hyprshot -m window"))
  hl.bind("PRINT",                   hl.dsp.exec_cmd("hyprshot -m output"))
  hl.bind(mod .. " + SHIFT + PRINT", hl.dsp.exec_cmd("hyprshot -m region"))

  -- screen recording
  hl.bind("CTRL + SHIFT + PRINT",
    hl.dsp.exec_cmd([[wf-recorder -f ~/Videos/recording_$(date +"%Y-%m-%d_%H:%M:%S.mp4")]]))
  hl.bind("CTRL + SHIFT + " .. mod .. " + PRINT",
    hl.dsp.exec_cmd([[wf-recorder -g "$(slurp)" -f ~/Videos/recording_$(date +"%Y-%m-%d_%H:%M:%S.mp4")]]))
  hl.bind("CTRL + SHIFT + BACKSPACE", hl.dsp.exec_cmd("killall -s SIGINT wf-recorder"))

  -- media keys
  hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("pamixer -i 1"),           { locked = true, repeating = true })
  hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("pamixer -d 1"),           { locked = true, repeating = true })
  hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("ddcutil setvcp 10 + 10"), { locked = true })
  hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("ddcutil setvcp 10 - 10"), { locked = true })
  hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("pamixer -t"),             { locked = true })
  hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"),   { locked = true })
  hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),         { locked = true })
  hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),     { locked = true })

  hl.bind("ALT + SHIFT + O", hl.dsp.exec_cmd("playerctl play-pause"))

  -- wallpaper rotation
  hl.bind(mod .. " + SHIFT + W", hl.dsp.exec_cmd("systemctl --user start set-wallpaper.service"))

  -- bemoji picker
  hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("bemoji -tn"))

  -- browser
  hl.bind(mod .. " + B",         hl.dsp.exec_cmd(p.browser))
  hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd(p.browser .. " -private-window"))

  -- email
  hl.bind(mod .. " + M", hl.dsp.exec_cmd(p.email))

  -- AyuGram
  hl.bind(mod .. " + comma", hl.dsp.exec_cmd("DESKTOPINTEGRATION=1 AyuGram"))

  -- steam
  hl.bind(mod .. " + G", hl.dsp.exec_cmd("steam"))

  -- Pdx-Unlimiter passthrough
  hl.bind("CTRL + SHIFT + I", hl.dsp.pass({ window = "class:^(Pdx-Unlimiter)$" }))
  hl.bind("CTRL + SHIFT + K", hl.dsp.pass({ window = "class:^(Pdx-Unlimiter)$" }))
end
