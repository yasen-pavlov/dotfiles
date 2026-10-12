--!nonstrict
-- [[panel]] menu: the bar capsule's right-click menu (board 07).
--
-- Noctalia v5.2.1 gives bar widgets no context-menu API (panel.openContextMenu exists
-- only inside panels, and only from a ui.button right click), so this is a small
-- floating panel opened near the click and drawn like Noctalia's menu: header, rows,
-- separators, "›" rows that drill into the project list (the native menu has no
-- submenus for plugins either). Mouse, ↑ ↓ Home End ↵, → to open a submenu, ← / Backspace
-- to go back, Esc closes. Quit only asks the app, which shows its own quit sheet.

local model = require("./lib/model.luau")
local theme = require("./lib/theme.luau")
local ctl = require("./lib/ctl.luau")

local tr = noctalia.tr

local ROW_H = 30
local HEADER_H = 26
local SEP_H = 9
local WIDTH = 230 - 28
local TRANSPARENT = "#00000000"

local link = model.link()
local isOpen = false
local level = "root" -- "root" | "agent" | "shell"
local highlight = nil -- entry id

local render

local function close()
  panel.close()
end

local function entries()
  local out = {}
  if not model.running(link) then
    if ctl.canStart(link) then
      table.insert(out, { kind = "header", label = tr("menu.header_off") })
      table.insert(out, { id = "start", label = tr("panel.start"), glyph = "player-play" })
    else
      local status = link.status
      local header = (status == "protocol" or status == "incompatible") and "menu.header_protocol" or "menu.header_starting"
      table.insert(out, { kind = "header", label = tr(header) })
    end
    table.insert(out, { kind = "note", label = tr("tooltip.kept") })
    return out
  end
  local s = link.snapshot
  if level ~= "root" then
    table.insert(out, { kind = "header", label = level == "agent" and tr("menu.new_agent_in_header") or tr("menu.new_terminal_in_header") })
    table.insert(out, { id = "back", label = tr("menu.back"), glyph = "chevron-left" })
    table.insert(out, { kind = "separator" })
    for _, p in ipairs(s.projects or {}) do
      table.insert(out, { id = "p:" .. p.id, label = p.name, glyph = "folder", project = p.id })
    end
    return out
  end
  local counts = model.counts(s)
  table.insert(out, { kind = "header", label = tr("menu.header", { n = counts.live }) })
  local waiting = s.waiting and s.waiting.nextItemId
  local item = waiting and model.itemsById(s)[waiting] or nil
  if item ~= nil then
    table.insert(out, { id = "jump", label = tr("menu.jump_to", { title = item.title }), glyph = "arrow-big-right-lines" })
  else
    table.insert(out, { id = "jump", label = tr("menu.jump"), glyph = "arrow-big-right-lines", disabled = true })
  end
  local visible = s.app and s.app.windowVisible
  table.insert(out, { id = "window", label = visible and tr("menu.hide_app") or tr("menu.show_app"), glyph = "app-window" })
  table.insert(out, { id = "palette", label = tr("menu.palette"), glyph = "search" })
  local hasProjects = #(s.projects or {}) > 0
  table.insert(out, { id = "agent", label = tr("menu.new_agent_in_header"), glyph = "plus", submenu = true, disabled = not hasProjects })
  table.insert(out, { id = "shell", label = tr("menu.new_terminal_in_header"), glyph = "terminal-2", submenu = true, disabled = not hasProjects })
  table.insert(out, { kind = "separator" })
  table.insert(out, { id = "quit", label = tr("menu.quit"), glyph = "power", danger = true })
  return out
end

local function actionable()
  local out = {}
  for _, e in ipairs(entries()) do
    if e.id ~= nil and not e.disabled then
      table.insert(out, e)
    end
  end
  return out
end

local function activate(e)
  if e == nil or e.disabled then
    return
  end
  local id = e.id
  if id == "start" then
    ctl.start()
    close()
  elseif id == "jump" then
    ctl.send("jump_to_waiting", nil)
    close()
  elseif id == "window" then
    ctl.send("set_window_visible", { visible = "toggle" })
    close()
  elseif id == "palette" then
    ctl.send("open_palette", nil)
    close()
  elseif id == "agent" or id == "shell" then
    level = id
    highlight = nil
    render()
  elseif id == "back" then
    level = "root"
    highlight = nil
    render()
  elseif id == "quit" then
    ctl.send("request_quit", nil)
    close()
  elseif e.project ~= nil then
    ctl.send("new_item", { projectId = e.project, kind = level })
    close()
  end
end

local function row(c, e)
  local enabled = not e.disabled
  local hot = enabled and highlight == e.id
  local color = (not enabled) and c.disabled or (e.danger and c.errorColor or c.title)
  local children = {
    ui.glyph({ name = e.glyph or "point", size = 14, color = (not enabled) and c.disabled or (e.danger and c.errorColor or c.onSurfaceVariant) }),
    ui.label({ text = e.label, fontSize = 13, color = color, maxLines = 1, maxWidth = WIDTH - 52, flexGrow = 1 }),
  }
  if e.submenu then
    table.insert(children, ui.glyph({ name = "chevron-right", size = 13, color = enabled and c.onSurfaceVariant or c.disabled }))
  end
  return ui.row({
    key = "e-" .. e.id, height = ROW_H, paddingH = 8, gap = 8, radius = 6, align = "center",
    fill = hot and "surface_variant" or TRANSPARENT,
    onClick = enabled and function() activate(e) end or "",
    onHover = function(state)
      if state == "true" then
        highlight = e.id
        render()
      end
    end,
  }, children)
end

render = function()
  if not isOpen then
    return
  end
  local c = theme.colors()
  local children = {}
  local list = {}
  for i, e in ipairs(entries()) do
    if e.kind == "header" then
      table.insert(children, ui.row({ key = "h" .. i, height = HEADER_H, paddingH = 8, align = "center" }, {
        ui.label({ text = e.label, fontSize = 11, fontWeight = "semibold", color = c.onSurfaceVariant, maxLines = 1, maxWidth = WIDTH - 16 }),
      }))
    elseif e.kind == "separator" then
      table.insert(children, ui.column({ key = "s" .. i, height = SEP_H, justify = "center", paddingH = 6 }, {
        ui.separator({ color = c.footerLine, thickness = 1, spacing = 0 }),
      }))
    elseif e.kind == "note" then
      table.insert(children, ui.row({ key = "n" .. i, paddingH = 8, paddingV = 6 }, {
        ui.label({ text = e.label, fontSize = 11, color = c.onSurfaceVariant, maxLines = 3, maxWidth = WIDTH - 16 }),
      }))
    elseif level ~= "root" and e.project ~= nil then
      table.insert(list, row(c, e))
    else
      table.insert(children, row(c, e))
    end
  end
  if #list > 0 then
    table.insert(children, ui.scroll({ key = "projects", flexGrow = 1, gap = 0 }, list))
  end
  panel.render(ui.column({ gap = 0 }, children))
end

function onKey(chord, pressed)
  if not pressed then
    return
  end
  local items = actionable()
  if #items == 0 then
    return
  end
  local idx = nil
  for i, e in ipairs(items) do
    if e.id == highlight then
      idx = i
    end
  end
  if chord == "Up" then
    idx = idx and math.max(1, idx - 1) or #items
  elseif chord == "Down" then
    idx = idx and math.min(#items, idx + 1) or 1
  elseif chord == "Home" then
    idx = 1
  elseif chord == "End" then
    idx = #items
  elseif chord == "Return" or chord == "KP_Enter" or chord == "Right" then
    local e = idx and items[idx] or nil
    if e ~= nil and (chord ~= "Right" or e.submenu) then
      activate(e)
    end
    return
  elseif chord == "Left" or chord == "BackSpace" then
    if level ~= "root" then
      level = "root"
      highlight = nil
      render()
    end
    return
  end
  highlight = items[idx].id
  render()
end

function onOpen()
  isOpen = true
  level = "root"
  highlight = nil
  link = model.link()
  render()
end

function onClose()
  isOpen = false
end

noctalia.state.watch("link", function(value)
  link = type(value) == "table" and value or { status = "not_running" }
  render()
end)

noctalia.setUpdateInterval(3600000)

function update() end
