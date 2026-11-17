--!nonstrict
-- Borg Backup bar [[widget]]: a pill that exists only while a backup runs or something
-- needs attention. Pure renderer of the "borg" snapshot the service publishes; it reads no
-- files and runs nothing.
--
--   idle     hidden (setVisible(false): no capsule, no gap)
--   running  primary glyph + "Backup NN%" (estimate during create) or "Backup"
--   warn     error-coloured warning glyph + "Backup failed" / "Backup interrupted" /
--            "Backup Nd old" / "No backup yet"
--
-- Left click toggles the panel (manifest [widget.actions] default, remappable per
-- instance). The minute tick only refreshes the tooltip's elapsed / age text while the pill
-- is visible.

local format = require("./lib/format.luau")
local tr = noctalia.tr

local snapshot = noctalia.state.get("borg")

local function stageName(stage)
  if stage == "snapshot" or stage == "create" or stage == "prune" or stage == "cleanup" then
    return tr("stage." .. stage)
  end
  return tr("stage.unknown")
end

local function mode()
  if type(snapshot) ~= "table" then
    return "idle"
  end
  return snapshot.mode
end

-- Short pill text for the warn mode; W1 (failed / interrupted run) wins over W2 (age).
local function warnText(now)
  if snapshot.w1 then
    return tr(snapshot.failure == "failed" and "bar.failed" or "bar.interrupted")
  end
  local archive = snapshot.lastArchive
  if type(archive) ~= "table" then
    return tr("bar.no_backup")
  end
  local age = math.max(0, now - archive.finishedAt)
  if age < 86400 then
    return tr("bar.hours_old", { n = math.floor(age / 3600) }) -- only with stale_hours < 24
  end
  return tr("bar.days_old", { n = math.floor(age / 86400) })
end

local function runningRows(now)
  local live = snapshot.live
  local rows = {
    { key = tr("tooltip.stage"), value = stageName(live.stage) },
  }
  if type(live.startedAt) == "number" then
    table.insert(rows, { key = tr("tooltip.elapsed"), value = format.duration(now - live.startedAt, tr) })
  end
  local sep = tr("number.thousands_sep")
  local files = format.thousands(live.nfiles, sep)
  if type(live.expectedNfiles) == "number" and live.expectedNfiles > 0 then
    files = tr("tooltip.files_of", { n = files, total = format.thousands(live.expectedNfiles, sep) })
  end
  table.insert(rows, { key = tr("tooltip.files"), value = files })
  return rows
end

local function warnRows(now)
  local rows = {}
  local run = snapshot.lastRun
  if type(run) == "table" and run.result ~= "success" then
    local when = run.finishedAt or run.startedAt
    local value = tr("result." .. (run.result == "failed" and "failed" or "interrupted"))
    if type(when) == "number" then
      value = tr("tooltip.value_when", { value = value, when = format.ago(now - when, tr) })
    end
    table.insert(rows, { key = tr("tooltip.last_run"), value = value })
  end
  local archive = snapshot.lastArchive
  table.insert(rows, {
    key = tr("tooltip.last_archive"),
    value = type(archive) == "table" and format.ago(now - archive.finishedAt, tr) or tr("tooltip.none"),
  })
  return rows
end

local function render()
  local m = mode()
  if m ~= "running" and m ~= "warn" then
    barWidget.clearTooltip()
    barWidget.setVisible(false)
    return
  end
  local now = os.time()
  barWidget.setVisible(true)
  if m == "running" then
    local percent = snapshot.live.percent
    barWidget.setGlyph("database-export")
    barWidget.setGlyphColor("primary")
    barWidget.setText(type(percent) == "number" and tr("bar.running_percent", { percent = percent }) or tr("bar.running"))
    barWidget.setTooltip(runningRows(now))
  else
    barWidget.setGlyph("alert-triangle")
    barWidget.setGlyphColor("error")
    barWidget.setText(warnText(now))
    barWidget.setTooltip(warnRows(now))
  end
end

noctalia.state.watch("borg", function(value)
  snapshot = type(value) == "table" and value or nil
  render()
end)

render()
-- Set once at load so the host's 250 ms default tick never runs.
noctalia.setUpdateInterval(60000)

function update()
  local m = mode()
  if m == "running" or m == "warn" then
    render()
  end
end
