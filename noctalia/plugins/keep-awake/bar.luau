--!nonstrict
-- Keep Awake bar [[widget]]: a coffee pill that exists only while a session runs (v4
-- BarWidget.qml hid itself when off). Pure renderer — no update(), no clock: it watches
-- the two keys the service publishes and patches the built-in glyph/text row.
--
--   "keepawake"            snapshot (status / scope / endEpoch / gates …), on transitions
--   "keepawake_remaining"  "29m" | "1h05m" | "<1m" | "∞" | "", at most once a minute
--
-- Gestures (v4 BarWidget.qml:54-62): left = open the panel, or toggle the last choice when
-- activate_on_left_click is on; right = turn off; middle = toggle the last choice (the
-- manifest binds middle = "none" so onMiddleClick fires). Widgets are rebuilt on a settings
-- change, so the settings are simply read at load.

local tr = noctalia.tr
local PANEL_ID = "muty/keep-awake:panel"
local ENTRY = "bar"

local showRemaining = noctalia.getConfig("show_remaining_text") ~= false
local activateOnLeftClick = noctalia.getConfig("activate_on_left_click") == true

local snapshot = noctalia.state.get("keepawake")
local remaining = tostring(noctalia.state.get("keepawake_remaining") or "")
local cmdCounter = 0

local function send(action)
  cmdCounter += 1
  noctalia.state.set("keepawake_cmd", { id = `{ENTRY}-{cmdCounter}`, action = action })
end

-- Shown while starting too, so the pill appears on the click and not ~100 ms later when
-- the holder reports (v4 updated optimistically for the same reason).
local function isShown()
  return type(snapshot) == "table" and (snapshot.status == "on" or snapshot.status == "starting")
end

-- Tooltip rows are { key, value } pairs (barWidget.setTooltip accepts a list of them).
local function tooltipRows()
  local full = snapshot.scope == "full"
  local rows = {
    { key = tr("title"), value = tr(full and "tooltip.scope_full" or "tooltip.scope_partial") },
    { key = tr("tooltip.remaining"), value = remaining },
  }
  if not snapshot.unlimited and (tonumber(snapshot.endEpoch) or 0) > 0 then
    -- timeFormat() already falls back to "{:%H:%M}" when [shell].time_format is empty.
    table.insert(rows, { key = tr("tooltip.until"), value = noctalia.formatTime(noctalia.timeFormat(), snapshot.endEpoch) })
  end
  if full and type(snapshot.gates) == "table" and snapshot.gates.screensaver == false and snapshot.status == "on" then
    table.insert(rows, { key = tr("tooltip.gate"), value = tr("tooltip.gate_logind_only") })
  end
  return rows
end

local function render()
  if not isShown() then
    barWidget.clearTooltip()
    barWidget.setVisible(false) -- hides the whole node: no capsule, no gap
    return
  end
  barWidget.setVisible(true)
  barWidget.setGlyph("coffee")
  barWidget.setGlyphColor(snapshot.scope == "full" and "primary" or "secondary")
  barWidget.setText(showRemaining and remaining or "")
  barWidget.setTooltip(tooltipRows())
end

noctalia.state.watch("keepawake", function(value)
  snapshot = type(value) == "table" and value or nil
  remaining = tostring(noctalia.state.get("keepawake_remaining") or "")
  render()
end)

noctalia.state.watch("keepawake_remaining", function(value)
  remaining = tostring(value or "")
  render()
end)

render()

function onClick()
  if activateOnLeftClick then
    send("toggle")
  else
    noctalia.togglePanel(PANEL_ID)
  end
end

function onRightClick()
  send("stop")
end

function onMiddleClick()
  send("toggle")
end
