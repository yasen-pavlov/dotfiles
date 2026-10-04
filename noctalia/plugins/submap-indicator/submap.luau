--!nonstrict
-- Submap Indicator: a bar pill that exists only while one configured Hyprland
-- submap (default "grp") is active. Luau port of the v4 QML plugin.
--
-- Mechanism (same as k4n4t4/hypr-submap):
--   state        : `hyprctl submap` (prints "default" when no submap is active),
--                  queried on the first update() tick and once a minute after
--                  that as a self-heal: the host never restarts a dead stream
--                  and gives Luau no exit notification for it
--   live updates : Hyprland's socket2 event stream via socat, filtered to
--                  "submap>>NAME" lines; NAME is "" on return to the default map
-- The socat subprocess belongs to the host: it is terminated when this entry
-- reloads, is removed, or the plugin is disabled, so no onExit hook is needed
-- (runStream() returns no handle that Luau could stop anyway).
--
-- Entry id: muty/submap-indicator:submap. IPC for testing without a keybind:
--   noctalia msg plugin muty/submap-indicator:submap focused set grp   -- force "grp" (shows)
--   noctalia msg plugin muty/submap-indicator:submap focused set       -- default map (hides)
--   noctalia msg plugin muty/submap-indicator:submap focused refresh   -- re-query hyprctl
--   noctalia msg plugin muty/submap-indicator:submap focused status    -- notify + log the state

-- Widget settings, declared in plugin.toml (an undeclared key returns nil + a warning).
-- A settings change rebuilds the widget, so this chunk re-runs and re-reads them
-- (onConfigChanged() is only delivered to services).
local cfg = {}
local function loadSettings()
  local matched = noctalia.string.trim(tostring(noctalia.getConfig("matched_submap") or ""))
  cfg.matched = if matched ~= "" then matched else "grp"
  cfg.label = tostring(noctalia.getConfig("label") or "")
  cfg.glyph = noctalia.string.trim(tostring(noctalia.getConfig("glyph") or ""))
  cfg.accent = noctalia.getConfig("use_accent_color") ~= false -- nil counts as true
end
loadSettings()

-- Active submap, normalised so "" always means the default map
-- (socket2 reports "", `hyprctl submap` prints "default").
local current = ""
-- Bumped by every socket2 event so a slower `hyprctl submap` answer that
-- started before the event cannot overwrite the newer state.
local eventSeq = 0

local function normalize(name)
  name = noctalia.string.trim(name or "")
  return if name == "default" then "" else name
end

local function isActive()
  return current ~= "" and current == cfg.matched
end

local function render()
  -- setVisible(false) hides the widget's root node; the bar drops it from the
  -- section layout, so no capsule and no gap remain while inactive.
  barWidget.setVisible(isActive())

  -- v4 recoloured its own BarPill (primary + on_primary with accent, capsule
  -- colour + on_surface without). The bar capsule fill is not scriptable, so
  -- the pill is drawn here in BOTH modes as a filled ui.row, and the widget
  -- instance should set `capsule = false` (see plugin.toml / README) or the bar
  -- wraps this pill in a second capsule. surface_variant is v5's default
  -- capsule fill; an unset text colour inherits the widget foreground.
  local fg = if cfg.accent then "on_primary" else nil
  local children = {}
  if cfg.glyph ~= "" then
    table.insert(children, ui.glyph({ name = cfg.glyph, color = fg }))
  end
  if cfg.label ~= "" then
    table.insert(children, ui.label({ text = cfg.label, color = fg }))
  end
  -- Row on a horizontal bar, column on a side bar; only the main axis grows.
  local container = if barWidget.isVertical() then ui.column else ui.row
  barWidget.render(container({
    gap = 6,
    align = "center",
    paddingH = 8,
    paddingV = 4,
    radius = 12,
    fill = if cfg.accent then "primary" else "surface_variant",
  }, children))
  -- Tooltips still apply while a render() tree is active.
  barWidget.setTooltip(`Hyprland submap: {cfg.matched}`)
end

local function setCurrent(name)
  current = normalize(name)
  render()
end

local function query()
  local seq = eventSeq
  noctalia.runAsync("hyprctl submap", function(result)
    -- The callback receives a CommandResult table, not the raw stdout string.
    -- A socket2 event that landed while hyprctl ran is newer than this answer.
    if result.exitCode == 0 and eventSeq == seq then
      setCurrent(result.stdout)
    end
  end)
end

local function socketPath()
  local sig = noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE")
  local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
  if sig == nil or sig == "" or runtimeDir == nil or runtimeDir == "" then
    return nil
  end
  return `{runtimeDir}/hypr/{sig}/.socket2.sock`
end

render() -- start hidden; the load-time patch lands before anything is drawn

local sock = socketPath()
local streaming = false
if sock ~= nil then
  -- stdbuf forces line buffering so each event reaches onLine as Hyprland emits it.
  streaming = noctalia.runStream(`stdbuf -oL -eL socat -u UNIX-CONNECT:"{sock}" -`, function(line)
    local name = line:match("^submap>>(.*)$")
    if name ~= nil then
      eventSeq += 1
      setCurrent(name)
    end
  end)
end
if not streaming then
  noctalia.log("submap-indicator: no socket2 stream (Hyprland env unset or runStream refused); 60 s poll only")
end

function update()
  -- Set the interval here, not at load: the host then runs this first tick at
  -- its 250 ms default (a load-time 60 s interval would delay it by a minute),
  -- and isVertical() is only known after the first layout.
  noctalia.setUpdateInterval(60000)
  render() -- re-render with the real bar orientation
  query() -- initial state on the first tick; later ticks re-sync if the stream died
end

function onIpc(event, payload)
  if event == "set" then
    setCurrent(payload or "")
  elseif event == "refresh" then
    query()
  elseif event == "status" then
    -- onIpc has no return channel in v5 (the router only answers ok/error).
    local msg = `current="{current}" matched="{cfg.matched}" active={isActive()}`
    noctalia.log(`submap-indicator: {msg}`)
    noctalia.notify("Submap Indicator", msg)
  end
end
