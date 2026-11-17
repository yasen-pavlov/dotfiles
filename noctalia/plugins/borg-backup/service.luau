--!nonstrict
-- Borg Backup [[service]] — the only entry that reads files or runs commands. The bar
-- widget and the panel are pure renderers of what this publishes on the plugin state
-- channel:
--
--   published  "borg"      snapshot table, re-published only when its content changes:
--                { mode, hasState, stateFile, staleHours, w1, w2, failure,
--                  live = { stage, startedAt, stageStartedAt, updatedAt, nfiles,
--                           originalSize, compressedSize, dedupSize, expectedNfiles,
--                           expectedDurationS, percent } | nil,
--                  lastRun = { result, implicit, startedAt, finishedAt, stage, exitCode,
--                              archiveWritten } | nil,
--                  lastArchive = { finishedAt, durationS, nfiles, originalSize,
--                                  compressedSize, dedupSize } | nil,
--                  nextRun = { state = "pending" | "ok" | "unknown", at } }
--              with mode = "idle" | "running" | "warn"
--   consumed   "borg_cmd"  { id, action = "panel_open" | "panel_close" } from the panel
--                (id must differ per command so a repeated action still fires the watch)
--
-- Inputs (both written by the root-side backup script, see README "Status files"):
--   status_file  live status, exists only while a run is in progress
--   state_file   last run + last good archive, persistent
-- Both are polled with noctalia.readFileAsync — 2 s while a run is live, 5 s otherwise,
-- no subprocesses. The pid liveness check is a stat of /proc/<pid>. The next timer
-- elapse comes from `systemctl show` (argv form), at most once a minute.

local format = require("./lib/format.luau")

local DEFAULT_STATUS_FILE = "/run/borg-backup/status.json"
local DEFAULT_STATE_FILE = "/var/lib/borg-backup/last-run.json"
local DEFAULT_STALE_HOURS = 48
local POLL_LIVE_MS = 2000
local POLL_IDLE_MS = 5000
-- A "running" last_run without a live status file is an interrupted run (hard kill, power
-- loss) — but the same picture shows for a moment at every run start (the script writes
-- the state file, then the status file, and the two reads here are not atomic either).
-- Only in that window (status file absent, no live run published before) does an
-- implicit interruption wait for a second poll this much later; a corrupt status file or
-- a dead pid counts at once.
local POLL_CONFIRM_MS = 1000
local NEXT_RUN_MIN_INTERVAL_S = 60
local NEXT_RUN_TIMEOUT_MS = 5000
local TIMER_UNIT = "borg-backup.timer"
local STAGES = { snapshot = true, create = true, prune = true, cleanup = true }

-- ── Config ───────────────────────────────────────────────────────────────────

local cfg = {}

local function pathSetting(key, default)
  local value = noctalia.getConfig(key)
  if type(value) == "string" then
    value = noctalia.string.trim(value)
  end
  if type(value) ~= "string" or value == "" then
    return default
  end
  return value
end

local function readConfig()
  cfg.statusFile = pathSetting("status_file", DEFAULT_STATUS_FILE)
  cfg.stateFile = pathSetting("state_file", DEFAULT_STATE_FILE)
  local hours = tonumber(noctalia.getConfig("stale_hours"))
  cfg.staleHours = (hours ~= nil and hours >= 1) and math.floor(hours) or DEFAULT_STALE_HOURS
end

-- ── Parsing ──────────────────────────────────────────────────────────────────
-- Unknown keys are ignored; a file whose top level is not a schema-1 object is "no data".

local count = format.count

local function text(value)
  return type(value) == "string" and value or nil
end

local function parseStatus(value)
  if type(value) ~= "table" or value.schema ~= 1 then
    return nil
  end
  local pid = count(value.pid)
  local stage = text(value.stage)
  return {
    state = text(value.state) or "",
    pid = (pid ~= nil and pid > 0) and pid or nil,
    stage = (stage ~= nil and STAGES[stage]) and stage or "",
    startedAt = count(value.started_at),
    stageStartedAt = count(value.stage_started_at),
    updatedAt = count(value.updated_at),
    nfiles = count(value.nfiles) or 0,
    originalSize = count(value.original_size) or 0,
    compressedSize = count(value.compressed_size) or 0,
    dedupSize = count(value.deduplicated_size) or 0,
    expectedNfiles = count(value.expected_nfiles),
    expectedDurationS = count(value.expected_duration_s),
  }
end

local function parseState(value)
  if type(value) ~= "table" or value.schema ~= 1 then
    return nil
  end
  local lastRun = nil
  local run = value.last_run
  if type(run) == "table" and text(run.result) ~= nil then
    lastRun = {
      result = run.result,
      startedAt = count(run.started_at),
      finishedAt = count(run.finished_at),
      stage = text(run.stage) or "",
      exitCode = count(run.exit_code),
      archiveWritten = text(run.archive) ~= nil and run.archive ~= "",
    }
  end
  local lastArchive = nil
  local archive = value.last_archive
  -- Without a finish time an archive cannot be aged, so it does not count as known.
  if type(archive) == "table" and count(archive.finished_at) ~= nil then
    lastArchive = {
      finishedAt = count(archive.finished_at),
      durationS = count(archive.duration_s),
      nfiles = count(archive.nfiles),
      originalSize = count(archive.original_size),
      compressedSize = count(archive.compressed_size),
      dedupSize = count(archive.deduplicated_size),
    }
  end
  return { lastRun = lastRun, lastArchive = lastArchive }
end

-- ── File polling ─────────────────────────────────────────────────────────────

-- data: last good parse (nil = no data); failures: consecutive failed reads while data is
-- kept. A missing file is "no data" at once; an existing file that fails to read or parse
-- keeps the previous snapshot for exactly one poll.
local files = {
  status = { data = nil, failures = 0 },
  state = { data = nil, failures = 0 },
}
local generation = 0 -- bumped on a config change: callbacks from older reads are dropped
local polling = false
local implicitPolls = 0 -- consecutive polls showing "running" without a live run
local confirming = false -- the last poll was held back as a possible run start
local nextRun = { state = "pending", at = 0 }
local nextRunQueriedAt = 0
local nextRunInflight = false
local panelOpen = false
local lastEncoded = nil
local snapshot = nil
local publish -- forward

local function decode(contents)
  local ok, value = pcall(noctalia.json.decode, contents)
  return ok and value or nil
end

-- slot.missing: the last read found no file at all (as opposed to an unreadable or
-- unparsable one); only that case may stand for "the run is just starting".
local function settle(slot, path, parsed)
  if parsed ~= nil then
    slot.data = parsed
    slot.failures = 0
    slot.missing = false
    return
  end
  local exists = noctalia.fileExists(path)
  slot.missing = not exists
  if slot.data ~= nil and slot.failures == 0 and exists then
    slot.failures = 1
  else
    slot.data = nil
    slot.failures = 0
  end
end

-- A read that returns no contents while the path exists by callback time raced a file
-- that was created (or replaced) in between — typically status.json at a run start, which
-- would otherwise pass for a corrupt file and skip the run-start debounce. Such a read is
-- repeated once, immediately; a second miss is settled as usual. Unparsable contents are
-- never re-read.
local function readInto(slot, path, parser, gen, done, isRetry)
  local accepted = noctalia.readFileAsync(path, function(contents, _err)
    if gen ~= generation then
      return
    end
    if contents == nil and not isRetry and noctalia.fileExists(path) then
      readInto(slot, path, parser, gen, done, true)
      return
    end
    settle(slot, path, contents ~= nil and parser(decode(contents)) or nil)
    done()
  end)
  if not accepted then
    settle(slot, path, nil)
    done()
  end
end

local function pidAlive(pid)
  return pid ~= nil and noctalia.fileExists(`/proc/{pid}`)
end

-- Derives the mode from the two parsed files. Returns false for the run-start window
-- (nothing is published for that poll, see POLL_CONFIRM_MS).
local function derive()
  local now = os.time()
  confirming = false
  local live = files.status.data
  local state = files.state.data
  local running = live ~= nil and live.state == "running" and pidAlive(live.pid)

  local snap = {
    mode = "idle",
    hasState = state ~= nil,
    stateFile = cfg.stateFile,
    staleHours = cfg.staleHours,
    w1 = false,
    w2 = false,
    failure = "",
    nextRun = nextRun,
  }

  if state ~= nil then
    local archive = state.lastArchive
    snap.lastArchive = archive
    snap.w2 = archive == nil or now - archive.finishedAt > cfg.staleHours * 3600
  end

  if running then
    implicitPolls = 0
    snap.mode = "running"
    local entry = table.clone(live)
    entry.state = nil
    entry.pid = nil
    entry.percent = entry.stage == "create" and format.percent(entry.nfiles, entry.expectedNfiles) or nil
    snap.live = entry
    return snap -- last_run describes this very run while it is live
  end

  if state == nil then
    implicitPolls = 0
    return snap -- root side not installed (or unreadable): idle, never a warning
  end

  local run = state.lastRun
  if run ~= nil then
    local implicit = run.result == "running"
    if implicit then
      implicitPolls += 1
      -- Run-start window only: the status file is absent (not corrupt, not a dead pid) and
      -- no live run was published. Anything else is an interruption right away.
      local starting = files.status.missing and (snapshot == nil or snapshot.mode ~= "running")
      if starting and implicitPolls < 2 then
        confirming = true
        return false
      end
    else
      implicitPolls = 0
    end
    local result = implicit and "interrupted" or run.result
    local entry = table.clone(run)
    entry.result = result
    entry.implicit = implicit
    snap.lastRun = entry
    if (result == "failed" or result == "interrupted") and not run.archiveWritten then
      snap.w1 = true
      snap.failure = result
    end
  else
    implicitPolls = 0
  end

  if snap.w1 or snap.w2 then
    snap.mode = "warn"
  end
  return snap
end

local function applyInterval()
  local ms = POLL_IDLE_MS
  if confirming then
    ms = POLL_CONFIRM_MS
  elseif snapshot ~= nil and snapshot.mode == "running" then
    ms = POLL_LIVE_MS
  end
  noctalia.setUpdateInterval(ms)
end

local function poll()
  if polling then
    return
  end
  polling = true
  local gen = generation
  -- Status first, state second: the script writes the final state before it removes the
  -- status file, so a state read that follows a "no live run" read sees the outcome.
  readInto(files.status, cfg.statusFile, parseStatus, gen, function()
    readInto(files.state, cfg.stateFile, parseState, gen, function()
      polling = false
      local snap = derive()
      if snap then
        snapshot = snap
        publish()
      end
      applyInterval()
    end)
  end)
end

publish = function()
  if snapshot == nil then
    return
  end
  snapshot.nextRun = nextRun
  local encoded = noctalia.json.encode(snapshot)
  if encoded ~= nil and encoded == lastEncoded then
    return
  end
  lastEncoded = encoded
  noctalia.state.set("borg", snapshot)
end

-- ── Next timer elapse ────────────────────────────────────────────────────────

local function setNextRun(state, at)
  nextRun = { state = state, at = at or 0 }
  publish()
end

-- Called at load, on every panel open and on service ticks while the panel is open; the
-- query itself runs at most once a minute whoever asks.
local function queryNextRun()
  local now = os.time()
  if nextRunInflight or (nextRunQueriedAt ~= 0 and now - nextRunQueriedAt < NEXT_RUN_MIN_INTERVAL_S) then
    return
  end
  nextRunQueriedAt = now
  if not noctalia.commandExists("systemctl") then
    setNextRun("unknown")
    return
  end
  nextRunInflight = true
  local accepted = noctalia.runAsync(
    { "systemctl", "show", TIMER_UNIT, "-p", "NextElapseUSecRealtime", "--timestamp=unix" },
    function(result)
      nextRunInflight = false
      local at = nil
      if result.exitCode == 0 and type(result.stdout) == "string" then
        at = tonumber(result.stdout:match("NextElapseUSecRealtime=@(%d+)"))
      end
      if at ~= nil and at > 0 then
        setNextRun("ok", math.floor(at))
      else
        setNextRun("unknown")
      end
    end,
    NEXT_RUN_TIMEOUT_MS
  )
  if not accepted then
    nextRunInflight = false
    setNextRun("unknown")
  end
end

-- ── Commands ─────────────────────────────────────────────────────────────────

noctalia.state.watch("borg_cmd", function(cmd)
  if type(cmd) ~= "table" then
    return
  end
  if cmd.action == "panel_open" then
    panelOpen = true
    queryNextRun()
    poll()
  elseif cmd.action == "panel_close" then
    panelOpen = false
  end
end)

-- ── Load ─────────────────────────────────────────────────────────────────────

readConfig()
poll()
queryNextRun()

-- ── Callbacks ────────────────────────────────────────────────────────────────

function update()
  poll()
  if panelOpen then
    queryNextRun()
  end
end

-- Paths or the stale limit changed: forget both files and start over at once.
function onConfigChanged()
  readConfig()
  generation += 1
  polling = false
  implicitPolls = 0
  confirming = false
  files.status = { data = nil, failures = 0 }
  files.state = { data = nil, failures = 0 }
  poll()
end

-- noctalia msg plugin muty/borg-backup:service all <refresh|status>
function onIpc(event, _payload)
  if event == "refresh" then
    poll()
  elseif event == "status" then
    local encoded = snapshot ~= nil and noctalia.json.encode(snapshot) or "null"
    noctalia.log(`borg-backup: status={cfg.statusFile} state={cfg.stateFile} snapshot={encoded}`)
  else
    noctalia.log(`borg-backup: unknown IPC event "{tostring(event)}"`)
  end
end
