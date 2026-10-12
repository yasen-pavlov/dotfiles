--!nonstrict
-- [[widget]] bar: one capsule (board 02). The U_ mark, then segments only when their
-- count is above zero, always in the order needs you · error · working · on job; unread
-- is a dot on the mark. Busy shells, exited items and seen turns never reach the bar.
-- Nothing moves: the capsule re-renders only when the service publishes.
--
-- Gestures (board 07): left toggles the panel (manifest [widget.actions]); middle jumps
-- to what's waiting, else shows/hides the window, or starts the app when it isn't
-- running; right opens the menu panel (v5.2.1 has no context-menu API for bar widgets,
-- so the bar menu is a small panel of its own, opened near the click); scroll: nothing.

local model = require("./lib/model.luau")
local theme = require("./lib/theme.luau")
local assets = require("./lib/assets.luau")
local ctl = require("./lib/ctl.luau")

-- Base sizes (Noctalia multiplies by the bar scale, 1.2 here): board 08 "Size".
local MARK = 13.33
local MARK_DOT_W = 15.83 -- the 19 px box with the unread dot
local GLYPH = 10
local COUNT_FONT = 11
local SEG_GAP = 5
local INSIDE_GAP = 3.33
local NEED_H = 15
local NEED_PAD = 5

local link = model.link()

local function count(n, color, weight)
  return ui.label({ text = tostring(n), fontSize = COUNT_FONT, fontWeight = weight or "semibold", color = color })
end

-- Everything the capsule shows (board 09: re-render only when a count, the unread flag or
-- the connection changes). Snapshot changes outside this key only refresh the tooltip.
local renderedKey = nil

local function capsuleKey()
  local running = model.running(link)
  local parts = { tostring(running), tostring(noctalia.getConfig("hide_when_not_running") == true) }
  if running then
    local n = model.counts(link.snapshot)
    table.insert(parts, string.format("%d/%d/%d/%d/%s", n.need, n.err, n.work, n.onjob, tostring(n.unread > 0)))
  end
  for _, role in ipairs({ "surface", "on_surface", "on_surface_variant", "primary", "error" }) do
    table.insert(parts, tostring(noctalia.getColor(role)))
  end
  return table.concat(parts, "|")
end

local function render()
  local running = model.running(link)
  local key = capsuleKey()
  if key == renderedKey then
    if running or noctalia.getConfig("hide_when_not_running") ~= true then
      barWidget.setTooltip(model.tooltipRows(link, noctalia.nowMs()))
    end
    return
  end
  renderedKey = key
  if not running and noctalia.getConfig("hide_when_not_running") == true then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)

  local c = theme.colors()
  local children = {}
  if not running then
    table.insert(children, ui.image({ key = "mark", path = assets.mark(c.onSurfaceVariant, false), width = MARK, height = MARK }))
  else
    local n = model.counts(link.snapshot)
    if n.unread > 0 then
      table.insert(children, ui.image({
        key = "mark", path = assets.mark(c.onSurface, true, c.unread), width = MARK_DOT_W, height = MARK,
      }))
    else
      table.insert(children, ui.image({ key = "mark", path = assets.mark(c.onSurface, true), width = MARK, height = MARK }))
    end
    if n.need > 0 then
      table.insert(children, ui.row({
        key = "need", gap = 2.5, align = "center", fill = c.primary, radius = NEED_H / 2,
        paddingH = NEED_PAD, height = NEED_H,
      }, {
        ui.label({ text = "!", fontSize = COUNT_FONT, fontWeight = "heavy", color = c.needText }),
        count(n.need, c.needText, "bold"),
      }))
    end
    if n.err > 0 then
      table.insert(children, ui.row({ key = "err", gap = 2.5, align = "center" }, {
        ui.label({ text = "×", fontSize = 12.5, fontWeight = "bold", color = c.errorColor }),
        count(n.err, c.errorColor),
      }))
    end
    if n.work > 0 then
      table.insert(children, ui.row({ key = "work", gap = INSIDE_GAP, align = "center" }, {
        ui.image({ path = assets.arc(c.purple, c.purpleLine, 0), width = GLYPH, height = GLYPH }),
        count(n.work, c.purple),
      }))
    end
    if n.onjob > 0 then
      table.insert(children, ui.row({ key = "onjob", gap = INSIDE_GAP, align = "center" }, {
        ui.image({ path = assets.ring(c.purple), width = GLYPH, height = GLYPH }),
        count(n.onjob, c.purple),
      }))
    end
  end

  local vertical = barWidget.isVertical()
  local container = vertical and ui.column or ui.row
  barWidget.render(container({ gap = SEG_GAP, align = "center" }, children))
  barWidget.setTooltip(model.tooltipRows(link, noctalia.nowMs()))
end

noctalia.state.watch("link", function(value)
  link = type(value) == "table" and value or { status = "not_running" }
  render()
end)

render()
-- Snapshots drive the capsule. The only tick refreshes the tooltip's ages once a minute:
-- board 04 wanted them computed at hover start, but a hover callback on the capsule
-- tree makes its own (tooltip-less) hover target and hides the widget tooltip in v5.2.1.
noctalia.setUpdateInterval(60000)

function update()
  if model.running(link) then
    barWidget.setTooltip(model.tooltipRows(link, noctalia.nowMs()))
  end
end

function onMiddleClick()
  if not model.running(link) then
    ctl.start()
    return
  end
  local waiting = link.snapshot.waiting and link.snapshot.waiting.nextItemId
  if waiting ~= nil then
    ctl.send("jump_to_waiting", nil)
  else
    ctl.send("set_window_visible", { visible = "toggle" })
  end
end

function onRightClick()
  noctalia.togglePanel("muty/ultra9000:menu")
end
