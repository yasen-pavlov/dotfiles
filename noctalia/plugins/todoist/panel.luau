--!nonstrict
-- [[panel]] entry: the three sections (Overdue / Today / Upcoming) rendered from the
-- state the sync service publishes. Each row: priority pip, content + project and the
-- due chip (that whole stretch is one click target that opens the task in Todoist),
-- then two always-visible ghost buttons — push to tomorrow (overdue + today only) and
-- complete. The header carries the summary or the last error, a refresh and an
-- open-in-Todoist button; a last-sync line sits under it.
--
-- Actions never touch the data here: they are handed to the service through
-- "action_request" and the service republishes at once (optimistic removal +
-- suppression live there, see service.luau). This panel only re-renders on state
-- changes, on open, and once a minute for the sync-ago text. Panels are rebuilt on
-- a settings change, so there is no onConfigChanged here (services only).

local DEFAULT_COLORS = { color_overdue = "#de4c4a", color_today = "#f49c18", color_upcoming = "#4073d6" }
local DEFAULT_OPEN_URL = "https://todoist.com/app/today"

-- Width budget so long task text ellipsizes instead of overrunning the row's
-- buttons (a label wraps freely unless it has a maxWidth). Mirrors noctalia's
-- Style constants: panelPadding 14, scrollbarWidth 6 + scrollbarGap 8.
local PANEL_WIDTH = 440 -- keep in sync with [[panel]] width in plugin.toml
local PANEL_PADDING = 14
local SCROLLBAR_GUTTER = 14
local CONTENT_W = PANEL_WIDTH - 2 * PANEL_PADDING - SCROLLBAR_GUTTER
local ROW_PAD_H = 4
local ROW_GAP = 8
local PIP_W = 6
local DUE_W = 64
local ACTION_BTN_W = 30
local HEADER_GLYPH = 22
local HEADER_TEXT_W = CONTENT_W + SCROLLBAR_GUTTER - HEADER_GLYPH - 3 * ROW_GAP - 2 * ACTION_BTN_W

local BUCKETS = {
  { key = "overdue", show = "show_overdue", color = "color_overdue", title = "panel.section_overdue", empty = "panel.empty_overdue" },
  { key = "today", show = "show_today", color = "color_today", title = "panel.section_today", empty = "panel.empty_today" },
  { key = "upcoming", show = "show_upcoming", color = "color_upcoming", title = "panel.section_upcoming", empty = "panel.empty_upcoming" },
}

local tr = noctalia.tr

-- Constant per-row tooltips, resolved once instead of twice per row per render.
local PUSH_TIP = tr("panel.row_push_tomorrow")
local DONE_TIP = tr("panel.row_complete")

local isOpen = false
local tasks = { overdue = {}, today = {}, upcoming = {} }
local counts = { overdue = 0, today = 0, upcoming = 0, total = 0 }
local lastSync = 0
local errorMessage = ""
local status = "loading"
local renderedSyncText = ""

local render

-- ── Config helpers ───────────────────────────────────────────────────────────

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

local function taskTextWidth(withPush)
  local w = CONTENT_W - 2 * ROW_PAD_H - PIP_W - ROW_GAP - DUE_W - ROW_GAP - ACTION_BTN_W
  if withPush then
    w = w - ROW_GAP - ACTION_BTN_W
  end
  return w
end

-- P1 (priority 4 in the API) -> overdue color, down to P4 (priority 1) -> muted.
local function priorityColor(priority)
  if priority == 4 then
    return colorFor("color_overdue")
  elseif priority == 3 then
    return colorFor("color_today")
  elseif priority == 2 then
    return colorFor("color_upcoming")
  end
  return "on_surface_variant"
end

-- ── State + actions ──────────────────────────────────────────────────────────

local function syncFromState()
  local t = noctalia.state.get("tasks")
  tasks = type(t) == "table" and t or { overdue = {}, today = {}, upcoming = {} }
  local c = noctalia.state.get("counts")
  counts = type(c) == "table" and c or { overdue = 0, today = 0, upcoming = 0, total = 0 }
  lastSync = tonumber(noctalia.state.get("last_sync")) or 0
  errorMessage = noctalia.state.get("error") or ""
  status = noctalia.state.get("status") or "loading"
end

local function openUrl(url)
  if type(url) ~= "string" or noctalia.string.trim(url) == "" then
    url = noctalia.getConfig("open_url")
    if type(url) ~= "string" or noctalia.string.trim(url) == "" then
      url = DEFAULT_OPEN_URL
    end
  end
  noctalia.runAsync({ "xdg-open", noctalia.string.trim(url) })
end

local function requestRefresh()
  noctalia.state.set("refresh_requested", (tonumber(noctalia.state.get("refresh_requested")) or 0) + 1)
end

local function sendAction(kind, id)
  noctalia.state.set("action_request", { kind = kind, id = id, at = noctalia.nowMs() })
end

-- ── Text formatting ──────────────────────────────────────────────────────────

-- Luau's os.time(table) is timegm, so this is 12:00 UTC of the calendar date: a
-- DST-proof stamp for whole-day arithmetic. Format it with "!"-prefixed os.date
-- (UTC) so the weekday/month never roll over in far-east zones.
local function noonOf(year, month, day)
  return os.time({ year = year, month = month, day = day, hour = 12 })
end

-- "10:30am"; falls back to 24h when the locale has no am/pm designator.
local function clockText(epoch)
  local ampm = string.lower(os.date("%p", epoch))
  if ampm == "" then
    return os.date("%H:%M", epoch)
  end
  return tostring(tonumber(os.date("%I", epoch))) .. ":" .. os.date("%M", epoch) .. ampm
end

local function dueText(task, bucket)
  local y, m, d = (task.due_date or ""):match("^(%d+)%-(%d+)%-(%d+)")
  if y == nil then
    return ""
  end
  local due = noonOf(tonumber(y), tonumber(m), tonumber(d))
  local now = os.date("*t", os.time())
  local today = noonOf(now.year, now.month, now.day)
  local diffDays = math.floor((due - today) / 86400 + 0.5)
  if bucket == "overdue" then
    local n = math.abs(diffDays)
    if n == 1 then
      return tr("panel.due_yesterday")
    end
    return tr("panel.due_days_ago", { n = n })
  elseif bucket == "today" then
    if task.due_epoch ~= nil then
      return clockText(task.due_epoch)
    end
    return tr("panel.due_today")
  end
  if diffDays == 1 then
    return tr("panel.due_tomorrow")
  elseif diffDays < 7 then
    return os.date("!%a", due)
  end
  return os.date("!%b", due) .. " " .. tostring(tonumber(d))
end

local function syncText()
  if lastSync <= 0 then
    return tr("panel.last_sync_never")
  end
  local ago = math.max(0, os.time() - lastSync)
  local when
  if ago < 60 then
    when = tr("panel.ago_just_now")
  elseif ago < 3600 then
    when = tr("panel.ago_minutes", { n = math.floor(ago / 60 + 0.5) })
  else
    when = tr("panel.ago_hours", { n = math.floor(ago / 3600 + 0.5) })
  end
  return tr("panel.last_sync", { time = when })
end

local function summaryText()
  if errorMessage ~= "" then
    return tr("panel.error_prefix") .. errorMessage
  end
  if status == "loading" then
    return tr("panel.loading")
  end
  if (tonumber(counts.total) or 0) == 0 then
    return tr("panel.summary_clear")
  end
  return tr("panel.summary", { overdue = counts.overdue or 0, today = counts.today or 0, upcoming = counts.upcoming or 0 })
end

local function urgencyColor()
  if (tonumber(counts.overdue) or 0) > 0 then
    return colorFor("color_overdue")
  elseif (tonumber(counts.today) or 0) > 0 then
    return colorFor("color_today")
  end
  return "on_surface"
end

-- ── Tree ─────────────────────────────────────────────────────────────────────

local function taskRow(task, bucket, accent)
  local id = task.id
  local withPush = bucket ~= "upcoming"
  local url = task.url

  local body = {
    ui.label({ text = task.content, fontSize = 13, color = "on_surface", maxLines = 1, maxWidth = taskTextWidth(withPush) }),
  }
  if task.project ~= nil and task.project ~= "" then
    table.insert(body, ui.label({
      text = "# " .. task.project,
      fontSize = 11,
      color = "on_surface_variant",
      opacity = 0.65,
      maxLines = 1,
      maxWidth = taskTextWidth(withPush),
    }))
  end

  -- Pip + text + due chip form one click target (open in Todoist), like v4's
  -- row-wide MouseArea. The action buttons stay outside it as siblings: whether a
  -- button nested inside a clickable container wins the click is not documented.
  local openTarget = ui.row({
    key = "open-" .. id,
    flexGrow = 1,
    gap = ROW_GAP,
    align = "center",
    onClick = function()
      openUrl(url)
    end,
  }, {
    ui.box({ width = PIP_W, height = PIP_W, radius = PIP_W / 2, fill = priorityColor(task.priority) }),
    ui.column({ key = "body-" .. id, flexGrow = 1, gap = 0 }, body),
    ui.label({
      text = dueText(task, bucket),
      fontSize = 11,
      color = bucket == "overdue" and accent or "on_surface_variant",
      width = DUE_W,
      textAlign = "end",
    }),
  })

  local children = { openTarget }
  if withPush then
    table.insert(children, ui.button({
      key = "push-" .. id,
      glyph = "calendar-plus",
      glyphSize = 14,
      variant = "ghost",
      width = ACTION_BTN_W,
      height = ACTION_BTN_W,
      tooltip = PUSH_TIP,
      onClick = function()
        sendAction("push", id)
      end,
    }))
  end
  table.insert(children, ui.button({
    key = "done-" .. id,
    glyph = "check",
    glyphSize = 14,
    variant = "ghost",
    width = ACTION_BTN_W,
    height = ACTION_BTN_W,
    tooltip = DONE_TIP,
    onClick = function()
      sendAction("complete", id)
    end,
  }))

  return ui.row({ key = "row-" .. id, gap = ROW_GAP, align = "center", paddingH = ROW_PAD_H, paddingV = 2, radius = 6 }, children)
end

local function section(spec)
  local list = tasks[spec.key]
  if type(list) ~= "table" then
    list = {}
  end
  local total = tonumber(counts[spec.key]) or 0
  local accent = colorFor(spec.color)

  local children = {
    ui.row({ gap = ROW_GAP, align = "center" }, {
      ui.box({ width = 4, height = 14, radius = 2, fill = accent }),
      ui.label({ text = tr(spec.title), fontSize = 14, fontWeight = "bold", color = "on_surface" }),
      ui.label({ text = total > 0 and ("· " .. tostring(total)) or "", fontSize = 12, color = "on_surface_variant" }),
    }),
  }
  if #list == 0 then
    -- While nothing has synced yet the header already says "Loading…"; an empty
    -- line here would wrongly claim the section is clear.
    if status ~= "loading" then
      table.insert(children, ui.label({
        text = tr(spec.empty),
        fontSize = 12,
        color = "on_surface_variant",
        opacity = 0.7,
        maxWidth = CONTENT_W - 12,
      }))
    end
  else
    for _, task in ipairs(list) do
      table.insert(children, taskRow(task, spec.key, accent))
    end
    if total > #list then
      table.insert(children, ui.label({
        text = tr("panel.more", { n = total - #list }),
        fontSize = 11,
        color = "on_surface_variant",
        opacity = 0.7,
      }))
    end
  end
  return ui.column({ key = "section-" .. spec.key, gap = 4, align = "stretch" }, children)
end

render = function()
  if not isOpen then
    return
  end
  renderedSyncText = syncText()

  local header = ui.row({ gap = ROW_GAP, align = "center" }, {
    ui.glyph({ name = "checklist", size = HEADER_GLYPH, color = urgencyColor() }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = tr("panel.title"), fontSize = 16, fontWeight = "bold", color = "on_surface" }),
      ui.label({
        text = summaryText(),
        fontSize = 12,
        color = errorMessage ~= "" and colorFor("color_overdue") or "on_surface_variant",
        maxLines = 2,
        maxWidth = HEADER_TEXT_W,
      }),
    }),
    ui.button({
      key = "header-refresh",
      glyph = "refresh",
      variant = "ghost",
      width = ACTION_BTN_W,
      height = ACTION_BTN_W,
      tooltip = tr("panel.footer_refresh"),
      onClick = requestRefresh,
    }),
    ui.button({
      key = "header-open",
      glyph = "external-link",
      variant = "ghost",
      width = ACTION_BTN_W,
      height = ACTION_BTN_W,
      tooltip = tr("panel.footer_open"),
      onClick = function()
        openUrl("")
      end,
    }),
  })

  local syncLine = ui.label({ text = renderedSyncText, fontSize = 10, color = "on_surface_variant", opacity = 0.7, textAlign = "end" })

  local sections = {}
  for _, spec in ipairs(BUCKETS) do
    if flagOn(spec.show) then
      table.insert(sections, section(spec))
    end
  end

  panel.render(ui.column({ flexGrow = 1, gap = 8, align = "stretch" }, {
    header,
    syncLine,
    ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, sections),
  }))
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

-- The service sets status last, so one watcher sees a consistent snapshot.
noctalia.state.watch("status", function()
  syncFromState()
  render()
end)

function onOpen(_context)
  syncFromState()
  isOpen = true
  panel.setWantsSecondTicks(true)
  render()
end

function onClose()
  isOpen = false
end

-- Second ticks only re-render when the sync-ago text actually changes (once a minute).
function update()
  if isOpen and syncText() ~= renderedSyncText then
    render()
  end
end
