--!nonstrict
-- Keep Awake control-center [[shortcut]] tile. A pure watcher of the service's state (no
-- update(): the host only ticks shortcut scripts while the control center is open, and the
-- two state watches already cover every change): active while a session runs, label =
-- remaining time. Left click opens the panel and right click turns the session off, exactly
-- like the v4 ControlCenterWidget.qml. Registered in the shortcut catalog as type
-- "muty/keep-awake:tile".

local tr = noctalia.tr
local PANEL_ID = "muty/keep-awake:panel"
local ENTRY = "tile"

local snapshot = noctalia.state.get("keepawake")
local remaining = tostring(noctalia.state.get("keepawake_remaining") or "")
local cmdCounter = 0

local function send(action)
  cmdCounter += 1
  noctalia.state.set("keepawake_cmd", { id = `{ENTRY}-{cmdCounter}`, action = action })
end

local function render()
  local status = type(snapshot) == "table" and snapshot.status or "off"
  local available = type(snapshot) ~= "table" or snapshot.available ~= false
  local on = status == "on"
  local busy = status == "starting" or status == "stopping"
  shortcut.setIcon("coffee", "coffee-off")
  shortcut.setActive(on or status == "starting")
  shortcut.setLabel(on and tr("tile.label_active", { remaining = remaining }) or tr("tile.label"))
  shortcut.setEnabled(available and not busy)
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
  noctalia.togglePanel(PANEL_ID)
end

function onRightClick()
  send("stop")
end
