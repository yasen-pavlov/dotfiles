--!nonstrict
-- Todoist sync [[service]] — the only entry that runs scripts/todoist-fetch.py.
--
-- Polls `fetch` every poll_seconds, applies each result through the suppression
-- set, and publishes plain data to the plugin's shared state. The bar widget and
-- the panel render from that state and send actions back through it.
--
-- State published (status is always set LAST so one watcher sees a consistent snapshot):
--   tasks      { overdue = {task}, today = {task}, upcoming = {task} } — suppression-
--              filtered and cut to max_per_section rows each. A task is { id, content,
--              priority, project, url, due_date, due_epoch } where due_epoch is the unix
--              time of a timed due (absent for date-only tasks).
--   counts     { overdue, today, upcoming, total } — full (uncut) sizes
--   last_sync  unix seconds of the last successful backend sync, 0 = never
--   error      "" when healthy, else the backend/process error text
--   status     "loading" (nothing applied yet) | "ok" | "error" (error set; the lists
--              still hold the last good / backend-cached data)
--   suppress   mirror of the suppression set, so a service reload cannot resurrect a
--              just-closed task
-- State consumed:
--   refresh_requested  nonce bumped by the bar (middle click) and the panel (refresh)
--   action_request     { kind = "complete" | "push", id, at } from the panel row buttons
--
-- Optimistic-action suppression (the v4 race fix, preserved exactly): completing or
-- pushing a task removes it locally at once and records id -> untilMs (complete 30 s,
-- push 8 s). Every applied fetch filters suppressed ids out and prunes the set ONLY
-- by now > untilMs — never because a fetch no longer lists the task. Todoist is
-- eventually consistent and can briefly re-list a just-closed task on a later
-- request; a flat time-based grace outlasts that flutter, an existence check would
-- resurrect the task. A short burst of quicker polls after an action lets the lists
-- settle (completes vanish for good, pushes resurface under "upcoming" once the
-- grace passes) without waiting for the regular poll.

local COMPLETE_GRACE_MS = 30000
local PUSH_GRACE_MS = 8000
local RECONCILE_POLLS = 3
local RECONCILE_INTERVAL_MS = 3000
local FETCH_TIMEOUT_MS = 30000
local ACTION_TIMEOUT_MS = 20000
local DEFAULT_POLL_SECONDS = 90
local MIN_POLL_SECONDS = 15
local DEFAULT_MAX_PER_SECTION = 10
local BUCKETS = { "overdue", "today", "upcoming" }

local scriptPath = (noctalia.pluginDir() or ".") .. "/scripts/todoist-fetch.py"
local tr = noctalia.tr

local lists = { overdue = {}, today = {}, upcoming = {} } -- suppression-filtered, uncut
local lastSync = 0
local lastError = ""
local status = "loading"
local suppress = {} -- id -> { untilMs }
local fetching = false
local fetchGeneration = 0
local currentFilter = ""
local reconcileLeft = 0
local lastRefreshNonce = tonumber(noctalia.state.get("refresh_requested")) or 0

-- ── Config ───────────────────────────────────────────────────────────────────

local function readPollMs()
  local seconds = tonumber(noctalia.getConfig("poll_seconds")) or DEFAULT_POLL_SECONDS
  return math.max(MIN_POLL_SECONDS, seconds) * 1000
end

local function readFilter()
  local raw = noctalia.getConfig("filter")
  if type(raw) ~= "string" then
    return ""
  end
  return noctalia.string.trim(raw)
end

local function readMaxPerSection()
  local n = tonumber(noctalia.getConfig("max_per_section")) or DEFAULT_MAX_PER_SECTION
  return math.max(1, math.floor(n))
end

-- ── Time ─────────────────────────────────────────────────────────────────────

-- Luau's os.time(table) is timegm — the fields are read as UTC (the vendored VM
-- deliberately swaps PUC Lua's mktime for os_timegm, and ignores isdst) — while
-- os.date("*t", t) is local. Round-tripping t through both therefore yields the
-- local UTC offset (seconds east) in effect at unix time t.
local function localOffsetAt(t)
  return os.time(os.date("*t", t)) - t
end

-- ISO-8601 "YYYY-MM-DDTHH:MM[:SS][.fff](Z|±HH:MM)?" -> unix seconds. A string with
-- no zone designator is a floating wall-clock time (what the backend emits for the
-- usual Todoist timed due) and is read as local time.
local function parseIso(text)
  if type(text) ~= "string" then
    return nil
  end
  local y, mo, d, h, mi, s = text:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):?(%d*)")
  if y == nil then
    return nil
  end
  local asUtc = os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s) or 0,
  })
  if asUtc == nil then
    return nil
  end
  local sign, oh, om = text:match("([+-])(%d%d):?(%d%d)$")
  if sign ~= nil then
    return asUtc - (tonumber(oh) * 3600 + tonumber(om) * 60) * (sign == "-" and -1 or 1)
  elseif text:sub(-1) == "Z" then
    return asUtc
  end
  -- Floating: the fields are local wall-clock. A second pass re-reads the offset at
  -- the resolved instant so a stamp next to a DST switch lands on the right side.
  local guess = asUtc - localOffsetAt(asUtc)
  return asUtc - localOffsetAt(guess)
end

-- ── Data ─────────────────────────────────────────────────────────────────────

local function normalizeTask(raw)
  if type(raw) ~= "table" or raw.id == nil then
    return nil
  end
  local task = {
    id = tostring(raw.id),
    content = type(raw.content) == "string" and raw.content or "",
    priority = tonumber(raw.priority) or 1,
    project = type(raw.project) == "string" and raw.project or "",
    url = type(raw.url) == "string" and raw.url or "",
    due_date = type(raw.due_date) == "string" and raw.due_date or "",
  }
  if type(raw.due_datetime) == "string" and raw.due_datetime ~= "" then
    task.due_epoch = parseIso(raw.due_datetime)
  end
  return task
end

-- Normalizes a backend list, dropping every currently suppressed id.
local function keepUnsuppressed(rawList)
  local out = {}
  if type(rawList) ~= "table" then
    return out
  end
  for _, raw in ipairs(rawList) do
    local task = normalizeTask(raw)
    if task ~= nil and suppress[task.id] == nil then
      table.insert(out, task)
    end
  end
  return out
end

local function slice(list, n)
  local out = {}
  for i = 1, math.min(n, #list) do
    out[i] = list[i]
  end
  return out
end

local function removeFromAll(id)
  for _, bucket in ipairs(BUCKETS) do
    local kept = {}
    for _, task in ipairs(lists[bucket]) do
      if task.id ~= id then
        table.insert(kept, task)
      end
    end
    lists[bucket] = kept
  end
end

-- status last: watchers triggering on it see tasks/counts already updated.
local function publish()
  local maxRows = readMaxPerSection()
  noctalia.state.set("tasks", {
    overdue = slice(lists.overdue, maxRows),
    today = slice(lists.today, maxRows),
    upcoming = slice(lists.upcoming, maxRows),
  })
  local counts = { overdue = #lists.overdue, today = #lists.today, upcoming = #lists.upcoming }
  counts.total = counts.overdue + counts.today + counts.upcoming
  noctalia.state.set("counts", counts)
  noctalia.state.set("last_sync", lastSync)
  noctalia.state.set("error", lastError)
  noctalia.state.set("status", status)
end

-- ── Suppression ──────────────────────────────────────────────────────────────

local function persistSuppress()
  noctalia.state.set("suppress", suppress)
end

local function suppressId(id, graceMs)
  suppress[id] = { untilMs = noctalia.nowMs() + graceMs }
  persistSuppress()
end

-- Purely time-based: an id leaves the set only once its grace has passed.
local function pruneSuppressed(now)
  local stale = {}
  for id, entry in pairs(suppress) do
    if now > entry.untilMs then
      table.insert(stale, id)
    end
  end
  for _, id in ipairs(stale) do
    suppress[id] = nil
  end
  if #stale > 0 then
    persistSuppress()
  end
end

-- ── Poll loop ────────────────────────────────────────────────────────────────

local function applyInterval()
  if reconcileLeft > 0 then
    noctalia.setUpdateInterval(RECONCILE_INTERVAL_MS)
  else
    noctalia.setUpdateInterval(readPollMs())
  end
end

local function scheduleReconcile()
  reconcileLeft = RECONCILE_POLLS
  applyInterval()
end

-- nil when the backend script is present, else the error text to surface. Checked
-- before every launch so a script that appears (or vanishes) later is picked up
-- without a reload.
local function backendMissing()
  if noctalia.fileExists(scriptPath) then
    return nil
  end
  return tr("error.missing_script", { path = scriptPath })
end

-- Process-level failure text, or nil when the process ran to completion.
local function describeFailure(result)
  if result.timedOut then
    return tr("error.timeout")
  end
  if result.exitCode ~= 0 then
    -- A Python traceback ends with the useful line (e.g. ModuleNotFoundError).
    local lastLine = nil
    for line in (result.stderr or ""):gmatch("[^\r\n]+") do
      local trimmed = noctalia.string.trim(line)
      if trimmed ~= "" then
        lastLine = trimmed
      end
    end
    if lastLine ~= nil then
      return lastLine
    end
    -- The host's piped runner execvp()s and _exit(127)s without writing anything to
    -- stderr, so a non-executable script (or a lost interpreter) is only visible as a
    -- bare exit code; 126/127 with silent stderr is that case.
    if result.exitCode == 127 or result.exitCode == 126 then
      return tr("error.exec", { path = scriptPath })
    end
    return tr("error.exit_code", { code = result.exitCode })
  end
  if result.stdoutTruncated then
    return tr("error.truncated")
  end
  return nil
end

local function applyFetch(result)
  local failure = describeFailure(result)
  if failure == nil then
    local payload = noctalia.json.decode(noctalia.string.trim(result.stdout or ""))
    if type(payload) ~= "table" then
      failure = tr("error.parse")
    else
      pruneSuppressed(noctalia.nowMs())
      lists.overdue = keepUnsuppressed(payload.overdue)
      lists.today = keepUnsuppressed(payload.today)
      lists.upcoming = keepUnsuppressed(payload.upcoming)
      local synced = parseIso(payload.last_sync)
      if synced ~= nil then
        lastSync = synced
      end
      -- The backend serves its cache with `error` set when the API call failed.
      lastError = type(payload.error) == "string" and payload.error or ""
    end
  end
  if failure ~= nil then
    -- Keep the last good lists; only the error text changes.
    lastError = failure
    noctalia.log("todoist: fetch failed: " .. failure)
  end
  status = lastError == "" and "ok" or "error"
  publish()
end

-- Launches a fetch. Returns true only when a process was actually started; false
-- while one is still in flight or when the launch itself failed.
local function startFetch()
  if fetching then
    return false
  end
  local missing = backendMissing()
  if missing ~= nil then
    lastError = missing
    status = "error"
    publish()
    return false
  end
  local argv = { scriptPath, "fetch" }
  if currentFilter ~= "" then
    table.insert(argv, "--filter")
    table.insert(argv, currentFilter)
  end
  fetching = true
  fetchGeneration = fetchGeneration + 1
  local generation = fetchGeneration
  local started = noctalia.runAsync(argv, function(result)
    if generation ~= fetchGeneration then
      return -- superseded by a config change; a newer fetch owns the state
    end
    fetching = false
    applyFetch(result)
  end, FETCH_TIMEOUT_MS)
  if not started then
    fetching = false
    lastError = tr("error.start")
    status = "error"
    publish()
    return false
  end
  return true
end

-- A running process cannot be cancelled: invalidate its callback instead.
local function restartFetch()
  if fetching then
    fetching = false
    fetchGeneration = fetchGeneration + 1
  end
  startFetch()
end

-- ── Actions ──────────────────────────────────────────────────────────────────

-- The server never saw the change: stop hiding the task and re-fetch so it comes back.
local function failAction(kind, id, message)
  noctalia.log("todoist: " .. kind .. " " .. id .. " failed: " .. message)
  noctalia.notifyError(tr("toast.error_title"), message)
  suppress[id] = nil
  persistSuppress()
  restartFetch()
end

-- The backend reports action failures as {"ok": false, "error": "..."} on STDOUT
-- with exit code 1 and nothing on stderr, so its own message has to be read before
-- the process-level description (which would only say "exited with code 1").
local function onActionResult(kind, id, result)
  local payload = noctalia.json.decode(noctalia.string.trim(result.stdout or ""))
  if type(payload) == "table" and payload.ok == true then
    return
  end
  local failure
  if type(payload) == "table" and type(payload.error) == "string" and payload.error ~= "" then
    failure = payload.error
  elseif type(payload) == "table" then
    failure = describeFailure(result) or tr("error.action")
  else
    failure = describeFailure(result) or tr("error.parse") -- timeout / exec failure / garbage
  end
  failAction(kind, id, failure)
end

local function runAction(kind, id, graceMs, argv, toastKey)
  -- A suppressed id is already hidden with its backend call in flight; a second
  -- request for it can only be a stale duplicate (double click before the panel
  -- re-rendered, a second panel instance). Running it again would spawn another
  -- process whose failure un-suppresses the task — the flutter this set prevents.
  if suppress[id] ~= nil then
    return
  end
  local missing = backendMissing()
  if missing ~= nil then
    noctalia.log("todoist: " .. kind .. " " .. id .. " skipped: " .. missing)
    noctalia.notifyError(tr("toast.error_title"), missing)
    return
  end
  suppressId(id, graceMs)
  removeFromAll(id)
  publish()
  local started = noctalia.runAsync(argv, function(result)
    onActionResult(kind, id, result)
  end, ACTION_TIMEOUT_MS)
  if not started then
    failAction(kind, id, tr("error.start"))
    return
  end
  noctalia.notify(tr(toastKey))
  scheduleReconcile()
end

local function completeTask(id)
  -- Gone for good: hide through the consistency window.
  runAction("complete", id, COMPLETE_GRACE_MS, { scriptPath, "complete", id }, "toast.completed_title")
end

local function pushTomorrow(id)
  -- Hide briefly, then let it surface under "upcoming".
  runAction("push", id, PUSH_GRACE_MS, { scriptPath, "reschedule", id, "tomorrow" }, "toast.rescheduled_title")
end

-- ── Wiring ───────────────────────────────────────────────────────────────────

noctalia.state.watch("refresh_requested", function(value)
  local nonce = tonumber(value) or 0
  if nonce ~= lastRefreshNonce then
    lastRefreshNonce = nonce
    startFetch()
  end
end)

noctalia.state.watch("action_request", function(request)
  if type(request) ~= "table" or request.id == nil then
    return
  end
  local id = tostring(request.id)
  if id == "" then
    return
  end
  if request.kind == "complete" then
    completeTask(id)
  elseif request.kind == "push" then
    pushTomorrow(id)
  end
end)

currentFilter = readFilter()

-- Restore the suppression set across a hot reload (state is process-lifetime).
local restored = noctalia.state.get("suppress")
if type(restored) == "table" then
  for id, entry in pairs(restored) do
    if type(entry) == "table" and tonumber(entry.untilMs) ~= nil then
      suppress[tostring(id)] = { untilMs = tonumber(entry.untilMs) }
    end
  end
end

-- First start: publish the loading snapshot. On a reload the previous snapshot
-- stays on screen until the fetch below lands.
if noctalia.state.get("status") == nil then
  publish()
end

applyInterval()
startFetch()

function update()
  if reconcileLeft > 0 then
    if fetching then
      return -- a fetch is still in flight: this burst tick is not spent
    end
    reconcileLeft = reconcileLeft - 1
    startFetch()
    if reconcileLeft == 0 then
      applyInterval() -- burst done: back to the regular cadence
    end
  else
    startFetch()
  end
end

-- Defined so a settings edit updates this runtime in place instead of restarting it.
function onConfigChanged()
  local filter = readFilter()
  applyInterval()
  if filter ~= currentFilter then
    currentFilter = filter
    restartFetch()
  else
    publish() -- max_per_section may have changed: re-cut the lists
  end
end

function onIpc(event, _payload)
  if event == "refresh" then
    startFetch()
  elseif event == "dump" then
    local suppressed = 0
    for _ in pairs(suppress) do
      suppressed = suppressed + 1
    end
    local summary = {
      status = status,
      error = lastError,
      overdue = #lists.overdue,
      today = #lists.today,
      upcoming = #lists.upcoming,
      last_sync = lastSync,
      suppressed = suppressed,
      fetching = fetching,
      reconcile_left = reconcileLeft,
    }
    noctalia.log("todoist: " .. (noctalia.json.encode(summary) or "?"))
  end
end
