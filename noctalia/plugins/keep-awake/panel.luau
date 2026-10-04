--!nonstrict
-- Keep Awake [[panel]] (320 px, attached): header with status line, a 3-column grid of
-- duration tiles (+ ∞), the "Keep display awake" scope toggle and an action row with
-- quick-extend + Turn on/off — the v4 Panel.qml layout. Renders in onOpen and from the two
-- state watches; never ticks (the service publishes the remaining text ≤ once a minute).
--
-- Selection state follows v4 Panel.qml:21-48: while a session runs the tiles mirror it
-- (scope from the session, minutes from the chosen duration); when off they start at the
-- first duration and the default scope. Clicking a tile while on restarts with that
-- duration at once, toggling the scope while on restarts with the remaining time kept —
-- both are commands to the service, this panel owns no session state.

local format = require("./lib/format.luau")
local tr = noctalia.tr
local ENTRY = "panel"

-- Width budget (keep PANEL_WIDTH in sync with [[panel]] width in plugin.toml). The panel
-- surface already insets its content by Style::panelPadding (14), so the tree adds no
-- outer padding of its own.
local PANEL_WIDTH = 320
local PANEL_PADDING = 14
local CONTENT_W = PANEL_WIDTH - 2 * PANEL_PADDING
local GAP = 8
local GRID_GAP = 6
local COLUMNS = 3
local CELL_W = math.floor((CONTENT_W - (COLUMNS - 1) * GRID_GAP) / COLUMNS)
local HEADER_GLYPH = 22
local SCOPE_GLYPH = 20
local TOGGLE_W = 48
local HEADER_TEXT_W = CONTENT_W - HEADER_GLYPH - GAP
local SCOPE_TEXT_W = CONTENT_W - SCOPE_GLYPH - GAP - TOGGLE_W - GAP
local DEFAULT_DURATIONS = { 30, 60, 120, 240, 480 }

local snapshot = noctalia.state.get("keepawake")
local remaining = tostring(noctalia.state.get("keepawake_remaining") or "")
local isOpen = false
local selectedMinutes = nil -- -1 = unlimited
local selectedScope = "partial"
local lastSeenStatus = nil
local cmdCounter = 0

-- ── Config ───────────────────────────────────────────────────────────────────

local function cfgDurations()
  local out = {}
  local raw = noctalia.getConfig("durations")
  if type(raw) == "table" then
    for _, value in ipairs(raw) do
      local n = tonumber(value)
      if n ~= nil and n > 0 then
        table.insert(out, math.floor(n))
      end
    end
  end
  if #out == 0 then
    out = table.clone(DEFAULT_DURATIONS)
  end
  return out
end

local function cfgIncludeUnlimited()
  return noctalia.getConfig("include_unlimited") ~= false
end

local function cfgQuickExtend()
  return math.clamp(math.floor(tonumber(noctalia.getConfig("quick_extend_minutes")) or 30), 5, 240)
end

local function cfgDefaultScope()
  return noctalia.getConfig("default_scope") == "full" and "full" or "partial"
end

-- ── State ────────────────────────────────────────────────────────────────────

local function statusOf()
  return type(snapshot) == "table" and snapshot.status or "off"
end

local function isOn()
  return statusOf() == "on"
end

local function isBusy()
  local s = statusOf()
  return s == "starting" or s == "stopping" or (type(snapshot) == "table" and snapshot.restarting == true)
end

local function isAvailable()
  return type(snapshot) ~= "table" or snapshot.available ~= false
end

local function send(action, extra)
  cmdCounter += 1
  local cmd = { id = `{ENTRY}-{cmdCounter}`, action = action }
  if extra ~= nil then
    for key, value in pairs(extra) do
      cmd[key] = value
    end
  end
  noctalia.state.set("keepawake_cmd", cmd)
end

-- Tile minutes for the running session: -1 for unlimited, else the chosen duration.
local function minutesFromSnapshot()
  if snapshot.unlimited then
    return -1
  end
  local chosen = tonumber(snapshot.chosenSeconds) or 0
  if chosen > 0 then
    return math.floor(chosen / 60)
  end
  return cfgDurations()[1]
end

-- While a session runs the tiles mirror it (so an IPC `on 2h full` shows up here too),
-- except while a restart this panel asked for is in flight — the local click already moved
-- the selection and the snapshot still carries the old session until the replacement
-- holder is adopted (or, on failure, the old values come back and the mirror resets).
-- `force` = the panel just opened (v4 built a fresh panel on every open); when off, only
-- an on -> off edge resets the selection to the defaults.
local function syncSelection(force)
  local status = statusOf()
  if status == "on" or status == "starting" then
    if force or snapshot.restarting ~= true then
      selectedScope = snapshot.scope == "full" and "full" or "partial"
      selectedMinutes = minutesFromSnapshot()
    end
  elseif force or selectedMinutes == nil or lastSeenStatus == "on" or lastSeenStatus == "starting" then
    selectedScope = (type(snapshot) == "table" and snapshot.pendingScope) or cfgDefaultScope()
    selectedMinutes = cfgDurations()[1]
  end
  lastSeenStatus = status
end

-- ── Actions ──────────────────────────────────────────────────────────────────

local render

local function onDurationClicked(minutes)
  selectedMinutes = minutes
  if isOn() then
    send("set_duration", { seconds = minutes == -1 and -1 or minutes * 60, scope = selectedScope })
  end
  render()
end

local function onScopeToggled(full)
  selectedScope = full and "full" or "partial"
  if isOn() then
    send("set_scope", { scope = selectedScope })
  end
  render()
end

local function onMainClicked()
  local status = statusOf()
  if status == "on" or status == "starting" then
    send("stop")
  else
    local minutes = selectedMinutes or cfgDurations()[1]
    send("start", { seconds = minutes == -1 and -1 or minutes * 60, scope = selectedScope })
  end
end

local function onExtendClicked()
  send("extend", { minutes = cfgQuickExtend() })
end

-- ── Tree ─────────────────────────────────────────────────────────────────────

local function statusText()
  local status = statusOf()
  if status == "starting" then
    return tr("panel.starting")
  elseif status == "stopping" then
    return tr("panel.stopping")
  elseif status == "on" then
    local key = snapshot.scope == "full" and "panel.remaining_display_on" or "panel.remaining_display_may_sleep"
    return tr(key, { time = remaining })
  end
  if type(snapshot) == "table" and type(snapshot.error) == "string" and snapshot.error ~= "" then
    return tr("panel.error", { message = snapshot.error })
  end
  return tr("panel.off")
end

local function header()
  local on = isOn()
  local color = "on_surface_variant"
  if on then
    color = snapshot.scope == "full" and "primary" or "secondary"
  end
  local errorShown = not on and type(snapshot) == "table" and type(snapshot.error) == "string" and snapshot.error ~= ""
  return ui.row({ gap = GAP, align = "center" }, {
    ui.glyph({ name = on and "coffee" or "coffee-off", size = HEADER_GLYPH, color = color }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = tr("panel.title"), fontSize = 16, fontWeight = "bold", color = "on_surface" }),
      ui.label({
        text = statusText(),
        fontSize = 12,
        color = errorShown and "error" or "on_surface_variant",
        maxLines = 1,
        maxWidth = HEADER_TEXT_W,
      }),
    }),
  })
end

local function durationGrid()
  local items = {}
  for _, minutes in ipairs(cfgDurations()) do
    table.insert(items, { minutes = minutes, label = format.label(minutes * 60) })
  end
  if cfgIncludeUnlimited() then
    table.insert(items, { minutes = -1, label = tr("panel.unlimited") })
  end
  local full = selectedScope == "full"
  local enabled = isAvailable() and not isBusy()
  local rows = {}
  local cells = {}
  for index, item in ipairs(items) do
    local minutes = item.minutes
    local selected = minutes == selectedMinutes
    table.insert(cells, ui.button({
      key = `d{minutes}`,
      text = item.label,
      width = CELL_W,
      controlSize = "sm",
      variant = selected and (full and "primary" or "secondary") or "outline",
      selected = selected,
      enabled = enabled,
      onClick = function()
        onDurationClicked(minutes)
      end,
    }))
    if #cells == COLUMNS or index == #items then
      table.insert(rows, ui.row({ gap = GRID_GAP, align = "center" }, cells))
      cells = {}
    end
  end
  return ui.column({ gap = GRID_GAP }, rows)
end

local function scopeRow()
  local full = selectedScope == "full"
  return ui.row({ gap = GAP, align = "center" }, {
    ui.glyph({ name = full and "sun" or "moon", size = SCOPE_GLYPH, color = full and "primary" or "secondary" }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = tr("panel.keep_display_label"), fontSize = 13, color = "on_surface", maxWidth = SCOPE_TEXT_W }),
      ui.label({
        text = tr("panel.keep_display_desc"),
        fontSize = 11,
        color = "on_surface_variant",
        maxLines = 2,
        maxWidth = SCOPE_TEXT_W,
      }),
    }),
    ui.toggle({
      key = "scope",
      checked = full,
      enabled = isAvailable() and not isBusy(),
      onChange = function(value)
        onScopeToggled(value == "true")
      end,
    }),
  })
end

local function actionRow()
  local status = statusOf()
  local on = status == "on" or status == "starting"
  local full = selectedScope == "full"
  local buttons = {}
  if isOn() and not snapshot.unlimited then
    table.insert(buttons, ui.button({
      key = "extend",
      text = tr("panel.extend", { minutes = cfgQuickExtend() }),
      glyph = "clock-plus",
      variant = "outline",
      flexGrow = 1,
      enabled = not isBusy(),
      onClick = onExtendClicked,
    }))
  end
  table.insert(buttons, ui.button({
    key = "main",
    text = tr(on and "panel.turn_off" or "panel.turn_on"),
    glyph = "power",
    variant = on and "destructive" or (full and "primary" or "secondary"),
    flexGrow = 1,
    enabled = isAvailable() and status ~= "stopping" and status ~= "starting",
    onClick = onMainClicked,
  }))
  return ui.row({ gap = GAP, align = "center" }, buttons)
end

render = function()
  if not isOpen then
    return
  end
  panel.render(ui.column({ flexGrow = 1, gap = GAP + 4, align = "stretch" }, {
    header(),
    durationGrid(),
    scopeRow(),
    actionRow(),
  }))
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

noctalia.state.watch("keepawake", function(value)
  snapshot = type(value) == "table" and value or nil
  remaining = tostring(noctalia.state.get("keepawake_remaining") or "")
  syncSelection(false)
  render()
end)

noctalia.state.watch("keepawake_remaining", function(value)
  remaining = tostring(value or "")
  render()
end)

function onOpen(_context)
  snapshot = noctalia.state.get("keepawake")
  remaining = tostring(noctalia.state.get("keepawake_remaining") or "")
  syncSelection(true)
  isOpen = true
  render()
end

function onClose()
  isOpen = false
end
