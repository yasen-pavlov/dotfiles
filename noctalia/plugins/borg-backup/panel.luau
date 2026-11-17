--!nonstrict
-- Borg Backup [[panel]] (340 px, floating): header with the current state, then
--   running   stage, progress (determinate only during `create` with a previous archive to
--             compare with — an estimate), files / bytes / new data, ticking elapsed time
--             and the previous `create` duration
--   warnings  both causes spelled out when present
--   last run  only when it did not succeed (and is not the run in progress)
--   last archive, next timer run
-- Pure renderer of the service's "borg" snapshot. It tells the service when it opens and
-- closes ("borg_cmd") so the next-run query refreshes on open; it ticks once a second while
-- open, re-rendering every tick during a run (elapsed time, indeterminate bar) and once a
-- minute otherwise (relative times).

local format = require("./lib/format.luau")
local tr = noctalia.tr
local ENTRY = "panel"

-- Width budget (keep PANEL_WIDTH in sync with [[panel]] width in plugin.toml). The panel
-- surface insets its content by Style::panelPadding (14), so the tree adds no padding.
local PANEL_WIDTH = 340
local PANEL_PADDING = 14
local CONTENT_W = PANEL_WIDTH - 2 * PANEL_PADDING
local GAP = 8
local SECTION_GAP = 14
local HEADER_GLYPH = 22
local HEADER_TEXT_W = CONTENT_W - HEADER_GLYPH - GAP
local KEY_W = 96
local VALUE_W = CONTENT_W - KEY_W - GAP
local BAR_H = 6
local WARN_PAD = 8
local WARN_GLYPH = 14
local WARN_TEXT_W = CONTENT_W - 2 * WARN_PAD - WARN_GLYPH - 6
local MARQUEE_SEG = math.floor(CONTENT_W * 0.3)
local MARQUEE_STEPS = 8
-- fmt-style pattern for the date part of absolute times; the time part is the shell's
-- [shell].time_format (noctalia.timeFormat()).
local DATE_PATTERN = "{:%a %b %d}"

local snapshot = noctalia.state.get("borg")
local isOpen = false
local phase = 0
local renderedMinute = 0
local cmdCounter = 0

local function send(action)
  cmdCounter += 1
  noctalia.state.set("borg_cmd", { id = `{ENTRY}-{cmdCounter}`, action = action })
end

-- ── Text helpers ─────────────────────────────────────────────────────────────

local function stageName(stage)
  if stage == "snapshot" or stage == "create" or stage == "prune" or stage == "cleanup" then
    return tr("stage." .. stage)
  end
  return tr("stage.unknown")
end

local function sameDay(a, b)
  return os.date("%Y-%m-%d", a) == os.date("%Y-%m-%d", b)
end

local function absoluteTime(epoch, now)
  local clock = noctalia.formatTime(noctalia.timeFormat(), epoch)
  if sameDay(epoch, now) then
    return clock
  end
  return tr("time.date_time", { date = noctalia.formatTime(DATE_PATTERN, epoch), time = clock })
end

-- "2 h ago · 18:22" / "1 d ago · Mon Nov 16, 18:22"
local function pastText(epoch, now)
  return tr("time.relative_absolute", { relative = format.ago(now - epoch, tr), absolute = absoluteTime(epoch, now) })
end

local function files(n)
  return format.thousands(n, tr("number.thousands_sep"))
end

-- ── Tree pieces ──────────────────────────────────────────────────────────────

-- The key sits in a fixed-width row: a label's own `width` does not reserve space.
local function kv(key, value, valueColor)
  return ui.row({ key = "kv-" .. key, gap = GAP, align = "start" }, {
    ui.row({ width = KEY_W, align = "start" }, {
      ui.label({ text = key, fontSize = 12, color = "on_surface_variant", maxWidth = KEY_W, maxLines = 1 }),
    }),
    ui.label({ text = value, fontSize = 12, color = valueColor or "on_surface", maxWidth = VALUE_W, maxLines = 2 }),
  })
end

local function sectionTitle(text)
  return ui.label({ text = text, fontSize = 13, fontWeight = "bold", color = "on_surface" })
end

local function note(text, color)
  return ui.label({ text = text, fontSize = 11, color = color or "on_surface_variant", maxWidth = CONTENT_W, maxLines = 3 })
end

local function statusText(now)
  local m = snapshot.mode
  if m == "running" then
    return tr("panel.status_running", { stage = stageName(snapshot.live.stage) })
  elseif m == "warn" then
    if snapshot.w1 then
      return tr(snapshot.failure == "failed" and "panel.status_failed" or "panel.status_interrupted")
    elseif type(snapshot.lastArchive) == "table" then
      return tr("panel.status_stale", { ago = format.ago(now - snapshot.lastArchive.finishedAt, tr) })
    end
    return tr("panel.status_no_archive")
  elseif type(snapshot.lastArchive) == "table" then
    return tr("panel.status_ok", { ago = format.ago(now - snapshot.lastArchive.finishedAt, tr) })
  end
  return tr("panel.status_no_state")
end

local function header(now)
  local m = snapshot.mode
  local glyph, color = "archive", "on_surface_variant"
  if m == "running" then
    glyph, color = "database-export", "primary"
  elseif m == "warn" then
    glyph, color = "alert-triangle", "error"
  end
  return ui.row({ gap = GAP, align = "center" }, {
    ui.glyph({ name = glyph, size = HEADER_GLYPH, color = color }),
    ui.column({ flexGrow = 1, gap = 0 }, {
      ui.label({ text = tr("panel.title"), fontSize = 16, fontWeight = "bold", color = "on_surface" }),
      ui.label({
        text = statusText(now),
        fontSize = 12,
        color = m == "warn" and "error" or "on_surface_variant",
        maxLines = 1,
        maxWidth = HEADER_TEXT_W,
      }),
    }),
  })
end

-- Indeterminate bar: a segment that sweeps the track, one step per second tick.
local function marquee()
  local cycle = 2 * MARQUEE_STEPS
  local step = phase % cycle
  if step > MARQUEE_STEPS then
    step = cycle - step
  end
  local offset = math.floor((CONTENT_W - MARQUEE_SEG) * step / MARQUEE_STEPS)
  -- Same node shape on every tick (keyed), so the host only moves the segment.
  return ui.row({ key = "marquee", width = CONTENT_W, height = BAR_H, radius = BAR_H / 2, fill = "surface_container", gap = 0 }, {
    ui.box({ key = "marquee-lead", width = offset, height = BAR_H, fill = "#00000000" }),
    ui.box({ key = "marquee-segment", width = MARQUEE_SEG, height = BAR_H, radius = BAR_H / 2, fill = "primary" }),
  })
end

local function runningSection(now)
  local live = snapshot.live
  local determinate = type(live.percent) == "number"
  local titleRow = {
    ui.label({ text = stageName(live.stage), fontSize = 14, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
  }
  local bar, caption
  if determinate then
    table.insert(titleRow, ui.label({ text = tr("panel.percent_estimate", { percent = live.percent }), fontSize = 12, color = "primary" }))
    local ratio = math.min(live.nfiles / live.expectedNfiles, 0.99)
    bar = ui.progress({ key = "progress", width = CONTENT_W, height = BAR_H, radius = BAR_H / 2, progress = ratio, fill = "primary", track = "surface_container" })
    caption = tr("panel.estimate_note")
  else
    bar = marquee()
    if live.stage == "create" then
      caption = tr("panel.caption_create_no_baseline")
    else
      caption = tr("panel.caption_" .. (live.stage ~= "" and live.stage or "unknown"))
    end
  end

  local rows = {
    ui.row({ key = "stage", gap = GAP, align = "center" }, titleRow),
    bar,
    note(caption),
  }
  if live.stage ~= "snapshot" then
    local filesText = files(live.nfiles)
    if type(live.expectedNfiles) == "number" and live.expectedNfiles > 0 then
      filesText = tr("panel.files_of", { n = filesText, total = files(live.expectedNfiles) })
    end
    table.insert(rows, kv(tr("panel.files"), filesText))
    table.insert(rows, kv(tr("panel.processed"), format.bytes(live.originalSize)))
    table.insert(rows, kv(tr("panel.new_data"), format.bytes(live.dedupSize)))
  end
  if type(live.startedAt) == "number" then
    table.insert(rows, kv(tr("panel.elapsed"), format.duration(now - live.startedAt, tr)))
  end
  local previous = live.expectedDurationS
  table.insert(rows, kv(tr("panel.previous_duration"), type(previous) == "number" and format.duration(previous, tr) or tr("panel.unknown")))
  return ui.column({ key = "running", gap = 6, align = "stretch" }, rows)
end

local function warningRow(text)
  return ui.row({ gap = 6, align = "start" }, {
    ui.glyph({ name = "alert-triangle", size = WARN_GLYPH, color = "error" }),
    ui.label({ text = text, fontSize = 12, color = "on_surface", maxWidth = WARN_TEXT_W, maxLines = 3 }),
  })
end

local function warningsBox(now)
  local rows = {}
  if snapshot.w1 then
    local run = snapshot.lastRun
    local key = "warn.interrupted"
    if run ~= nil and run.implicit then
      key = "warn.implicit"
    elseif snapshot.failure == "failed" then
      key = "warn.failed"
    end
    table.insert(rows, warningRow(tr(key)))
  end
  if snapshot.w2 then
    local archive = snapshot.lastArchive
    if type(archive) == "table" then
      table.insert(rows, warningRow(tr("warn.stale", { hours = snapshot.staleHours, ago = format.ago(now - archive.finishedAt, tr) })))
    else
      table.insert(rows, warningRow(tr("warn.no_archive")))
    end
  end
  if #rows == 0 then
    return nil
  end
  return ui.column({ key = "warnings", gap = 6, padding = WARN_PAD, radius = 8, fill = "error/0.12", align = "stretch" }, rows)
end

local function resultText(run)
  if run.result == "failed" or run.result == "interrupted" or run.result == "success" then
    if run.implicit then
      return tr("result.interrupted_implicit")
    end
    return tr("result." .. run.result)
  end
  return tr("result.other", { result = tostring(run.result) })
end

local function lastRunSection(now)
  local run = snapshot.lastRun
  local rows = {
    sectionTitle(tr("panel.last_run")),
    kv(tr("panel.result"), resultText(run), "error"),
  }
  if type(run.finishedAt) == "number" then
    table.insert(rows, kv(tr("panel.ended"), pastText(run.finishedAt, now)))
  elseif type(run.startedAt) == "number" then
    table.insert(rows, kv(tr("panel.started"), pastText(run.startedAt, now)))
  end
  if run.stage ~= "" then
    table.insert(rows, kv(tr("panel.ended_in"), stageName(run.stage)))
  end
  if type(run.exitCode) == "number" then
    table.insert(rows, kv(tr("panel.exit_code"), tostring(run.exitCode)))
  end
  if run.archiveWritten then
    table.insert(rows, note(tr("panel.archive_written")))
  end
  return ui.column({ key = "last-run", gap = 4, align = "stretch" }, rows)
end

local function lastArchiveSection(now)
  local rows = { sectionTitle(tr("panel.last_archive")) }
  local archive = snapshot.lastArchive
  if type(archive) == "table" then
    -- Sizes are null after an interactive (TTY) run: the archive is still known, its
    -- unknown rows are simply left out.
    table.insert(rows, kv(tr("panel.created"), pastText(archive.finishedAt, now)))
    if type(archive.originalSize) == "number" then
      table.insert(rows, kv(tr("panel.size"), format.bytes(archive.originalSize)))
    end
    if type(archive.dedupSize) == "number" then
      table.insert(rows, kv(tr("panel.new_data"), format.bytes(archive.dedupSize)))
    end
    if type(archive.durationS) == "number" then
      table.insert(rows, kv(tr("panel.duration"), format.duration(archive.durationS, tr)))
    end
  elseif snapshot.hasState then
    table.insert(rows, note(tr("panel.no_archive")))
  else
    table.insert(rows, note(tr("panel.no_state", { path = tostring(snapshot.stateFile) })))
  end
  return ui.column({ key = "last-archive", gap = 4, align = "stretch" }, rows)
end

local function nextRunRow(now)
  local info = snapshot.nextRun
  local value
  if type(info) ~= "table" or info.state == "pending" then
    value = tr("panel.next_pending")
  elseif info.state == "ok" then
    value = tr("time.relative_absolute", { relative = format.fromNow(info.at - now, tr), absolute = absoluteTime(info.at, now) })
  else
    value = tr("panel.unknown")
  end
  return kv(tr("panel.next_run"), value)
end

local function render()
  if not isOpen then
    return
  end
  local now = os.time()
  renderedMinute = math.floor(now / 60)
  if type(snapshot) ~= "table" then
    panel.render(ui.column({ flexGrow = 1, gap = SECTION_GAP, align = "stretch" }, {
      ui.label({ text = tr("panel.title"), fontSize = 16, fontWeight = "bold", color = "on_surface" }),
      note(tr("panel.loading")),
    }))
    return
  end

  local children = { header(now) }
  if snapshot.mode == "running" then
    table.insert(children, runningSection(now))
  end
  local warnings = warningsBox(now)
  if warnings ~= nil then
    table.insert(children, warnings)
  end
  local run = snapshot.lastRun
  if snapshot.mode ~= "running" and type(run) == "table" and run.result ~= "success" then
    table.insert(children, lastRunSection(now))
  end
  table.insert(children, lastArchiveSection(now))
  table.insert(children, nextRunRow(now))
  panel.render(ui.column({ flexGrow = 1, gap = SECTION_GAP, align = "stretch" }, children))
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

noctalia.state.watch("borg", function(value)
  snapshot = type(value) == "table" and value or nil
  render()
end)

function onOpen(_context)
  snapshot = noctalia.state.get("borg")
  isOpen = true
  panel.setWantsSecondTicks(true)
  send("panel_open")
  render()
end

function onClose()
  isOpen = false
  send("panel_close")
end

function update()
  if not isOpen then
    return
  end
  if type(snapshot) == "table" and snapshot.mode == "running" then
    phase += 1
    render()
  elseif math.floor(os.time() / 60) ~= renderedMinute then
    render()
  end
end
