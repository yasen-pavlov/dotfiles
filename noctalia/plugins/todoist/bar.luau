--!nonstrict
-- Bar [[widget]] entry: the Todoist pill, fed entirely by the sync service through
-- shared state. Optional checklist glyph (tinted by urgency: overdue color when
-- anything is overdue, today color when anything is due today, else the bar's
-- icon color) followed by one colored dot + count per bucket — only buckets that
-- are enabled and non-zero, so the pill stays calm on quiet days. The capsule
-- hides altogether when it would be empty (icon off and nothing to count).
--
-- The chips honour show_overdue/show_today/show_upcoming; the glyph tint and the
-- tooltip use the raw counts (as v4 did), so the bar agrees with the panel header
-- even when a section is hidden.
--
-- Gestures: left click is bound in plugin.toml to panel-toggle, middle click is
-- freed there ("none") so onMiddleClick below forces a refresh, right click opens
-- open_url in the browser. Widgets are rebuilt on a settings change, so there is
-- no onConfigChanged here (that callback only reaches services).

local DEFAULT_COLORS = { color_overdue = "#de4c4a", color_today = "#f49c18", color_upcoming = "#4073d6" }
local DEFAULT_OPEN_URL = "https://todoist.com/app/today"
local GLYPH_SIZE = 16
local DOT_SIZE = 6

local BUCKET_SPECS = {
  { key = "overdue", show = "show_overdue", color = "color_overdue", tooltip = "tooltip.line_overdue" },
  { key = "today", show = "show_today", color = "color_today", tooltip = "tooltip.line_today" },
  { key = "upcoming", show = "show_upcoming", color = "color_upcoming", tooltip = "tooltip.line_upcoming" },
}

local counts = noctalia.state.get("counts")
local errorMessage = noctalia.state.get("error") or ""
local status = noctalia.state.get("status") or "loading"
local tr = noctalia.tr

local function colorFor(key)
  local value = noctalia.getConfig(key)
  if type(value) == "string" and (value:match("^#%x%x%x%x%x%x$") or value:match("^#%x%x%x%x%x%x%x%x$")) then
    return value
  end
  return DEFAULT_COLORS[key]
end

local function flagOn(key)
  return noctalia.getConfig(key) ~= false
end

local function countOf(key)
  if counts == nil then
    return 0
  end
  return tonumber(counts[key]) or 0
end

local function openUrl()
  local url = noctalia.getConfig("open_url")
  if type(url) ~= "string" or noctalia.string.trim(url) == "" then
    url = DEFAULT_OPEN_URL
  end
  noctalia.runAsync({ "xdg-open", noctalia.string.trim(url) })
end

-- The chips the pill may show: enabled in settings and non-zero.
local function chipBuckets()
  local out = {}
  for _, spec in ipairs(BUCKET_SPECS) do
    local n = countOf(spec.key)
    if flagOn(spec.show) and n > 0 then
      table.insert(out, { key = spec.key, n = n, color = colorFor(spec.color) })
    end
  end
  return out
end

-- Raw-count urgency; nil lets the glyph inherit the bar's icon color.
local function urgencyColor()
  if countOf("overdue") > 0 then
    return colorFor("color_overdue")
  elseif countOf("today") > 0 then
    return colorFor("color_today")
  end
  return nil
end

local function tooltipText()
  if errorMessage ~= "" then
    return tr("tooltip.error") .. " — " .. errorMessage
  end
  if status == "loading" then
    return tr("tooltip.header") -- nothing synced yet: just the name, like v4
  end
  local parts = { tr("tooltip.header") }
  for _, spec in ipairs(BUCKET_SPECS) do
    local n = countOf(spec.key)
    if n > 0 then
      table.insert(parts, tr(spec.tooltip, { n = n }))
    end
  end
  if #parts == 1 then
    return tr("tooltip.clear")
  end
  return table.concat(parts, " · ")
end

local function render()
  local showIcon = flagOn("pill_show_icon")
  local chips = flagOn("pill_show_dots") and chipBuckets() or {}

  if not showIcon and #chips == 0 then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)

  local children = {}
  if showIcon then
    table.insert(children, ui.glyph({ name = "checklist", size = GLYPH_SIZE, color = urgencyColor() }))
  end
  for _, chip in ipairs(chips) do
    table.insert(children, ui.row({ key = "chip-" .. chip.key, gap = 3, align = "center" }, {
      ui.box({ width = DOT_SIZE, height = DOT_SIZE, radius = DOT_SIZE / 2, fill = chip.color }),
      ui.label({ text = tostring(chip.n) }),
    }))
  end

  local isVertical = barWidget.isVertical()
  local container = isVertical and ui.column or ui.row
  local layout = { gap = 6, align = "center" }
  if isVertical then
    layout.paddingV = 4
  else
    layout.paddingH = 4
  end
  barWidget.render(container(layout, children))
  barWidget.setTooltip(tooltipText())
end

-- The service sets status last, so one watcher sees a consistent counts/error snapshot.
noctalia.state.watch("status", function(value)
  counts = noctalia.state.get("counts")
  errorMessage = noctalia.state.get("error") or ""
  status = value or "loading"
  render()
end)

render()
-- Safety net only; the state watch drives real updates. Set once here so the
-- host's 250 ms default tick never fires (it applies before the first update()).
noctalia.setUpdateInterval(60000)

function update()
  render()
end

function onMiddleClick()
  noctalia.state.set("refresh_requested", (tonumber(noctalia.state.get("refresh_requested")) or 0) + 1)
end

function onRightClick()
  openUrl()
end
