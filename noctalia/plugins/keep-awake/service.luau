--!nonstrict
-- Keep Awake [[service]] — the only entry with state, and the only one that spawns or
-- kills the inhibit holder (scripts/keepawake-hold.py). The bar widget, the control-center
-- tile and the panel are stateless renderers driven through the plugin state channel:
--
--   published  "keepawake"            snapshot table, set ONLY on transitions:
--                { rev, status, available, error, scope, unlimited, endEpoch, startedEpoch,
--                  chosenSeconds, label, gates = { screensaver, logind }, restarting,
--                  pendingScope }   with status = "off" | "starting" | "on" | "stopping"
--              "keepawake_remaining"  "29m" | "1h05m" | "<1m" | "∞" | "" — set only when the
--                text changes (about once a minute); this service is the only clock
--   consumed   "keepawake_cmd"        { id, action, seconds, scope, minutes } from the
--                renderers (id must differ per command); onIpc maps the CLI to the same
--                handlers, see README "IPC"
--
-- Holder contract (one stdout line per event, consumed through noctalia.runStream):
--   held scope=<s> screensaver=<0|1> cookie=<n|-> logind=<what|-> pid=<n> until=<epoch|0> session=<id>
--   alive until=<epoch|0>            heartbeat every 15 s (40 s of silence = dead holder)
--   reacquired cookie=<n> | lost-owner | error <what>: <message>
--   released reason=<expired|sigterm|sigint|sighup|stdout-closed|parent-gone|nothing-held>
--                                    (last line)
--
-- Scopes: full = org.freedesktop.ScreenSaver cookie (served by Noctalia) + logind
-- Inhibit("idle:sleep:handle-lid-switch", block) — both feed the one counter that gates
-- every idle behaviour; partial = logind Inhibit("sleep:handle-lid-switch", block) only,
-- i.e. v4 semantics: dim / screen-off / lock still run, auto-suspend is refused by logind.
--
-- Lifetime: the holder is a runStream child, so the host SIGTERMs it on reload / disable /
-- uninstall / shutdown; the ScreenSaver cookie dies with the holder's bus name, the logind
-- inhibit with its fd, and the holder self-releases when this Noctalia disappears
-- (PR_SET_PDEATHSIG plus a ppid check every heartbeat — a closed stdout alone is not a
-- reliable signal because processes Noctalia forks later inherit the pipe) — nothing can
-- leak. runStream returns no handle or pid, so early stops are `pkill -f` by a
-- per-holder session nonce (argv form, API 24). Extend / scope / duration changes spawn the
-- replacement holder FIRST and kill the old one only after the new `held` line, so the
-- inhibit counter never touches zero and no idle countdown is re-armed mid-session.
--
-- Persistence mirrors v4: the live session in $XDG_RUNTIME_DIR/noctalia-keep-awake/
-- session.json (silently resumed after a Noctalia restart or plugin reload, gone with the
-- login session) and the last choice in pluginDataDir()/last.json (v4 schema; the v4 file
-- under ~/.local/state/system-awake is imported once when no last.json exists).
--
-- Budget: every callback here runs under the host's 25 ms CPU budget; update() ticks once a
-- second while a session runs and does a handful of integer compares.

local format = require("./lib/format.luau")
local tr = noctalia.tr

local HEARTBEAT_S = 15
local WATCHDOG_MS = 40000 -- > 2 missed heartbeats
-- No `held` line by then = failed start. Must exceed the holder's own worst case: two 2 s
-- D-Bus call timeouts plus a cold polkitd start for the logind Inhibit authorisation.
local SPAWN_TIMEOUT_S = 10
local SPAWN_TIMEOUT_MS = SPAWN_TIMEOUT_S * 1000
local STOP_TIMEOUT_MS = 1000 -- no `released` after SIGTERM by then = SIGKILL + off
local DEADLINE_GRACE_S = 10 -- wall-clock backstop behind the holder's own monotonic timer
local RESUME_MIN_SECONDS = 5 -- a saved session with less left is not worth respawning
local FALLBACK_SESSION_MAX_AGE_S = 24 * 3600 -- only when XDG_RUNTIME_DIR is unset
local FALLBACK_SECONDS = 1800 -- toggle with no last choice (v4 hard-coded 30 min)
local DEFAULT_DURATIONS = { 30, 60, 120, 240, 480 }
local TICK_ON_MS = 1000
local TICK_OFF_MS = 30000
local TICK_GAP_MS = 5 * TICK_ON_MS -- a larger gap between ticks = suspend/resume or a clock step
local MAX_HOLDER_SECONDS = 365 * 86400 -- --seconds clamp: GLib timers take 32-bit values
-- pkill -f pattern. Anchored on argv[0] == python3 (what `exec python3 …` and the script's
-- `#!/usr/bin/env python3` both produce) so it can never match a `sh -c` wrapper whose own
-- command line quotes this very pattern. Verified against the live holder (README).
local HOLDER_PATTERN = "^\\S*python3\\S* \\S*keepawake-hold\\.py "

local pluginDir = noctalia.pluginDir() or "."
local holderPath = pluginDir .. "/scripts/keepawake-hold.py"
local dataDir = noctalia.pluginDataDir() or pluginDir
local lastPath = dataDir .. "/last.json"
local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
local sessionInRuntimeDir = runtimeDir ~= nil and runtimeDir ~= ""
local sessionDir = (sessionInRuntimeDir and runtimeDir or dataDir) .. "/noctalia-keep-awake"
local sessionPath = sessionDir .. "/session.json"
local v4LastPath = (noctalia.getenv("XDG_STATE_HOME") or "~/.local/state") .. "/system-awake/last.json"

local available = noctalia.commandExists("python3") and noctalia.commandExists("pkill")

-- ── Config ───────────────────────────────────────────────────────────────────

local cfg = {}

local function readConfig()
  cfg.defaultScope = noctalia.getConfig("default_scope") == "full" and "full" or "partial"
  cfg.durations = {}
  local raw = noctalia.getConfig("durations")
  if type(raw) == "table" then
    for _, value in ipairs(raw) do
      local n = tonumber(value)
      if n ~= nil and n > 0 then
        table.insert(cfg.durations, math.floor(n))
      end
    end
  end
  if #cfg.durations == 0 then
    cfg.durations = table.clone(DEFAULT_DURATIONS)
  end
  cfg.quickExtend = math.clamp(math.floor(tonumber(noctalia.getConfig("quick_extend_minutes")) or 30), 5, 240)
  cfg.notify = noctalia.getConfig("notify") ~= false
end

-- ── State ────────────────────────────────────────────────────────────────────

local status = "off" -- off | starting | on | stopping
-- { scope, unlimited, endEpoch (0 when unlimited), startedEpoch, chosenSeconds (-1 unlimited),
--   label } — chosenSeconds is the tile the user picked (what last.json records and what the
--   panel highlights); label is display-only and grows " extended" like v4.
local session = nil
-- Holder records: { gen, nonce, spawnedMs, lastLineMs, held, silent, pid, gates, lastError }
-- plus, on a replacement, { kind, newSession, extendMinutes }.
local holder = nil -- the holder that owns the current session
local pending = nil -- replacement holder during extend / set_scope / set_duration
local gen = 0
local rev = 0
local lastError = ""
local lastRemaining = nil
local last = nil -- { duration_seconds, scope, duration_label } (v4 last.json schema)
local pendingScope = nil -- IPC `scope` while off: preselects the panel toggle
local stopStartedMs = 0
local exiting = false -- set in onExit: ignore holder lines / ticks during teardown
local lastTickMs = 0 -- update() gap detector (nowMs is the wall clock, see update)
local gateWarned = false -- "display gate unavailable" is raised once per session
local orphanReason = nil -- why the owning holder ended while a replacement was still starting

local onHolderLine -- forward declaration (spawnHolder captures it in the stream closure)

local function normalizeScope(value)
  if value == "full" or value == "partial" then
    return value
  end
  return nil
end

-- ── Files ────────────────────────────────────────────────────────────────────

local function readJson(path)
  local raw = noctalia.readFile(path)
  if raw == nil then
    return nil
  end
  local value = noctalia.json.decode(raw)
  return type(value) == "table" and value or nil
end

local function writeJson(path, value)
  local text = noctalia.json.encode(value, true)
  if text == nil then
    return false
  end
  local ok, err = noctalia.writeFile(path, text)
  if not ok then
    noctalia.log(`keep-awake: cannot write {path}: {err or "?"}`)
  end
  return ok
end

local function saveSession()
  if session == nil then
    return
  end
  noctalia.mkdirAll(sessionDir)
  writeJson(sessionPath, {
    version = 1,
    scope = session.scope,
    unlimited = session.unlimited,
    endEpoch = session.endEpoch,
    startedEpoch = session.startedEpoch,
    chosenSeconds = session.chosenSeconds,
    label = session.label,
  })
end

local function clearSession()
  if noctalia.fileExists(sessionPath) then
    noctalia.removeFile(sessionPath)
  end
end

local function saveLast(durationSeconds, scope)
  last = { duration_seconds = durationSeconds, scope = scope, duration_label = format.label(durationSeconds) }
  writeJson(lastPath, last)
end

-- last.json, or the v4 file on first run (same schema: duration_seconds -1 = unlimited).
local function loadLast()
  local value = readJson(lastPath)
  local migrated = false
  if value == nil then
    value = readJson(v4LastPath)
    migrated = value ~= nil
  end
  if value == nil then
    return
  end
  local scope = normalizeScope(value.scope)
  local seconds = tonumber(value.duration_seconds)
  if scope == nil or seconds == nil or (seconds ~= -1 and seconds < 1) then
    return
  end
  last = { duration_seconds = math.floor(seconds), scope = scope, duration_label = format.label(math.floor(seconds)) }
  if migrated then
    noctalia.log(`keep-awake: imported v4 last choice from {v4LastPath} ({last.duration_label} {scope})`)
    writeJson(lastPath, last)
  end
end

-- (seconds, scope) for toggle / IPC `on` without payload: the last choice, else the
-- given fallback duration with the configured default scope.
local function lastChoice(fallbackSeconds)
  if last ~= nil then
    return last.duration_seconds, last.scope
  end
  return fallbackSeconds, cfg.defaultScope
end

-- ── Publishing ───────────────────────────────────────────────────────────────

local function currentRemaining()
  if session == nil or (status ~= "on" and status ~= "starting") then
    return ""
  end
  return format.remaining(session.unlimited and 0 or session.endEpoch - os.time(), session.unlimited)
end

-- Only a changed string crosses the VM boundary (the store notifies every watcher on
-- every set, so "publish only on change" is what keeps the renderers quiet).
local function publishRemaining()
  local text = currentRemaining()
  if text ~= lastRemaining then
    lastRemaining = text
    noctalia.state.set("keepawake_remaining", text)
  end
end

local function publish()
  rev += 1
  local s = session or {}
  local h = holder or pending
  noctalia.state.set("keepawake", {
    rev = rev,
    status = status,
    available = available,
    error = lastError,
    scope = s.scope or "",
    unlimited = s.unlimited == true,
    endEpoch = s.endEpoch or 0,
    startedEpoch = s.startedEpoch or 0,
    chosenSeconds = s.chosenSeconds or 0,
    label = s.label or "",
    gates = h ~= nil and h.gates or { screensaver = false, logind = "" },
    restarting = pending ~= nil,
    pendingScope = pendingScope,
  })
end

local function applyInterval()
  noctalia.setUpdateInterval(status == "off" and TICK_OFF_MS or TICK_ON_MS)
end

-- Remaining first, then the snapshot: a snapshot watcher that reads the remaining key
-- sees the fresh value.
local function setStatus(newStatus)
  status = newStatus
  applyInterval()
  lastTickMs = 0 -- the interval may have changed: the next tick gap is not a clock step
  publishRemaining()
  publish()
end

local function notify(title, body)
  if cfg.notify then
    noctalia.notify(title, body)
  end
end

-- ── Holder process ───────────────────────────────────────────────────────────

-- pkill by argv: with a nonce only that holder, without one every holder (startup sweep).
local function killHolder(nonce, signal, onDone)
  local pattern = HOLDER_PATTERN
  if nonce ~= nil then
    pattern ..= ".*--session " .. nonce .. "( |$)"
  end
  -- false = the async-command slot cap was hit (8 per host / 32 global): nothing was sent.
  local ok = noctalia.runAsync({ "pkill", signal, "-f", "--", pattern }, onDone)
  if not ok then
    noctalia.log(`keep-awake: pkill {signal} could not be launched (async command cap)`)
  end
  return ok
end

local function freshSession(seconds, scope)
  local now = os.time()
  local unlimited = seconds == -1
  return {
    scope = scope,
    unlimited = unlimited,
    endEpoch = unlimited and 0 or now + seconds,
    startedEpoch = now,
    chosenSeconds = seconds,
    label = format.label(seconds),
  }
end

-- Spawns one holder for `sess`; returns its record or nil when runStream refused.
-- `exec` makes python3 the process-group leader so the pid it reports is the process the
-- host signals; `python3 <path>` instead of running the script directly so a lost exec bit
-- cannot break the plugin (argv[0] is "python3" either way, which the kill pattern needs).
local function spawnHolder(sess, silent)
  gen += 1
  local record = {
    gen = gen,
    nonce = string.format("ka-%d-%d", noctalia.nowMs(), gen), -- regex-safe [a-z0-9-]; ms + gen is unique across reloads
    spawnedMs = noctalia.nowMs(),
    lastLineMs = noctalia.nowMs(),
    held = false,
    silent = silent == true,
    pid = 0,
    gates = { screensaver = false, logind = "" },
    lastError = "",
  }
  local seconds = sess.unlimited and 0 or math.clamp(sess.endEpoch - os.time(), 1, MAX_HOLDER_SECONDS)
  local cmd = table.concat({
    "exec",
    "python3",
    format.shq(holderPath),
    "--scope",
    sess.scope,
    "--seconds",
    tostring(seconds),
    "--session",
    record.nonce,
    "--heartbeat",
    tostring(HEARTBEAT_S),
    "--app",
    "keep-awake",
    "--reason",
    format.shq("Keep Awake (" .. sess.label .. ")"),
  }, " ")
  local thisGen = record.gen
  local started = noctalia.runStream(cmd, function(line)
    onHolderLine(thisGen, line)
  end)
  if not started then
    return nil
  end
  return record
end

local function parseLine(line)
  local kind = line:match("^(%S+)") or ""
  local fields = {}
  for key, value in line:gmatch("(%w+)=(%S+)") do
    fields[key] = value
  end
  return kind, fields
end

-- Full scope with a refused ScreenSaver cookie still gates everything through the logind
-- idle block; a missing logind inhibit only leaves external suspend / lid unblocked.
local function warnGates(record)
  if session == nil then
    return
  end
  -- Once per session (design: "notifyError once but stay on"): every extend / scope flip /
  -- tile click adopts a replacement holder that would otherwise repeat it.
  if session.scope == "full" and not record.gates.screensaver and not gateWarned then
    gateWarned = true
    noctalia.notifyError(tr("toast.partial_gate_title"), tr("toast.partial_gate_desc"))
  end
  if record.gates.logind == "" then
    noctalia.log("keep-awake: logind inhibit unavailable — external suspend and lid close are not blocked")
  end
end

-- ── Transitions ──────────────────────────────────────────────────────────────

local function finishOff()
  holder = nil
  if pending ~= nil then
    killHolder(pending.nonce, "-TERM")
    pending = nil
  end
  session = nil
  gateWarned = false
  orphanReason = nil
  clearSession()
  setStatus("off")
end

-- The session has no live holder any more and nothing is coming: end it with the message
-- that matches how the last holder went (expiry is a normal end, anything else a loss —
-- the locks were reclaimed by Noctalia / logind either way).
local function endWithoutHolder(reason)
  if reason == "expired" then
    finishOff()
    notify(tr("toast.expired_title"))
    return
  end
  lastError = tr("toast.lost_desc")
  finishOff()
  noctalia.notifyError(tr("toast.lost_title"), tr("toast.lost_desc"))
end

-- off -> starting. `silent` marks a resume: no last.json rewrite, no "on" notification.
local function startSession(sess, silent)
  if status ~= "off" then
    noctalia.log(`keep-awake: start ignored while {status}`)
    notify(tr("title"), tr("toast.busy"))
    return false
  end
  lastError = ""
  if not available then
    lastError = tr("error.missing_dependencies")
    noctalia.notifyError(tr("toast.failed_title"), lastError)
    publish()
    return false
  end
  session = sess
  pendingScope = nil
  saveSession() -- BEFORE the spawn, so a reload during startup still resumes
  if not silent then
    saveLast(sess.chosenSeconds, sess.scope)
  end
  holder = spawnHolder(sess, silent)
  if holder == nil then
    lastError = tr("error.spawn")
    noctalia.notifyError(tr("toast.failed_title"), lastError)
    finishOff()
    return false
  end
  setStatus("starting")
  return true
end

-- on | starting -> stopping (the `released` line or the 1 s timeout completes it).
local function stopSession()
  if status == "off" or status == "stopping" then
    return
  end
  if pending ~= nil then
    killHolder(pending.nonce, "-TERM")
    pending = nil
  end
  if holder == nil then
    finishOff()
    notify(tr("toast.disabled_title"))
    return
  end
  killHolder(holder.nonce, "-TERM")
  stopStartedMs = noctalia.nowMs()
  setStatus("stopping")
end

-- on -> on with a replacement holder for `newSession`; the old holder keeps its locks until
-- the new one reports `held` (adoptPending), so the inhibit counter never drops to zero.
local function restartSession(kind, newSession, extendMinutes)
  if status ~= "on" or session == nil then
    return false
  end
  if pending ~= nil then
    noctalia.log("keep-awake: restart ignored, a replacement holder is already starting")
    notify(tr("title"), tr("toast.busy"))
    return false
  end
  if not newSession.unlimited and newSession.endEpoch - os.time() < 1 then
    stopSession() -- the new deadline is already behind us
    return false
  end
  local record = spawnHolder(newSession, true)
  if record == nil then
    noctalia.notifyError(tr("toast.failed_title"), tr("error.spawn"))
    return false
  end
  record.kind = kind
  record.newSession = newSession
  record.extendMinutes = extendMinutes
  pending = record
  publish() -- restarting = true
  return true
end

local function adoptPending(record)
  local old = holder
  holder = record
  pending = nil
  session = record.newSession
  lastError = ""
  orphanReason = nil
  saveSession()
  if record.kind ~= "extend" then
    saveLast(session.chosenSeconds, session.scope) -- v4 rewrote last.json on every start
  end
  if old ~= nil then
    killHolder(old.nonce, "-TERM")
  end
  setStatus("on")
  if record.kind == "extend" then
    notify(tr("toast.extended_title"), tr("toast.extended_desc", { minutes = record.extendMinutes or 0 }))
  end
  warnGates(record)
end

onHolderLine = function(lineGen, line)
  if exiting then
    return -- the host is tearing this runtime down; session.json must survive a reload
  end
  local record
  if holder ~= nil and holder.gen == lineGen then
    record = holder
  elseif pending ~= nil and pending.gen == lineGen then
    record = pending
  else
    noctalia.log(`keep-awake: stale holder #{lineGen}: {line}`)
    -- A `held` from a holder nobody tracks any more (its record was dropped before it
    -- reported): the TERM sent then may have predated its exec, so end it by the nonce it
    -- just echoed (pattern-checked so holder output never reaches the pkill regex).
    local kind, fields = parseLine(line)
    if kind == "held" and type(fields.session) == "string" and fields.session:match("^ka%-%d+%-%d+$") then
      killHolder(fields.session, "-TERM")
    end
    return
  end
  record.lastLineMs = noctalia.nowMs()
  local kind, fields = parseLine(line)

  if kind == "held" then
    record.held = true
    record.pid = tonumber(fields.pid) or 0
    record.gates = {
      screensaver = fields.screensaver == "1",
      logind = (fields.logind ~= nil and fields.logind ~= "-") and fields.logind or "",
    }
    if record == pending then
      adoptPending(record)
    elseif status == "starting" then
      setStatus("on")
      if not record.silent and session ~= nil then
        local key = session.scope == "full" and "toast.enabled_desc_full" or "toast.enabled_desc_partial"
        notify(tr("toast.enabled_title"), tr(key, { scope = session.scope, label = session.label }))
      end
      warnGates(record)
    else
      -- held after a stop request: that TERM went out while `sh` had not exec'd python yet
      -- (the anchored pattern cannot match the wrapper), so re-send it now that argv matches.
      killHolder(record.nonce, "-TERM")
      publish()
    end
  elseif kind == "alive" then
    -- heartbeat: lastLineMs is all the watchdog needs
  elseif kind == "released" then
    local reason = fields.reason or "?"
    if record == pending then
      pending = nil
      local message = record.lastError ~= "" and record.lastError or tr("error.holder_released", { reason = reason })
      noctalia.log(`keep-awake: replacement holder failed: {message}`)
      noctalia.notifyError(tr("toast.failed_title"), message)
      if holder == nil and status == "on" then
        endWithoutHolder(orphanReason) -- the old holder went away mid-restart too: nothing holds
      else
        publish() -- restarting = false, old session intact
      end
      return
    end
    holder = nil
    if status == "stopping" then
      finishOff()
      notify(tr("toast.disabled_title"))
    elseif status == "starting" then
      lastError = record.lastError ~= "" and record.lastError or tr("error.holder_released", { reason = reason })
      finishOff()
      noctalia.notifyError(tr("toast.failed_title"), lastError)
    elseif pending ~= nil then
      orphanReason = reason
      publish() -- the old holder ended mid-restart; the replacement takes over on its `held`
    elseif reason == "expired" then
      finishOff()
      notify(tr("toast.expired_title"))
    else
      -- stopped from outside (sigterm/sighup) or lost its reader: the locks are gone either way
      noctalia.log(`keep-awake: holder released unexpectedly ({reason})`)
      finishOff()
      notify(tr("toast.disabled_title"), tr("toast.released_reason", { reason = reason }))
    end
  elseif kind == "error" then
    record.lastError = noctalia.string.trim(line:sub(7)) -- after "error "
    noctalia.log("keep-awake: holder: " .. line)
  elseif kind == "reacquired" then
    record.gates.screensaver = true
    gateWarned = false -- the gate is back; warn again if it goes away
    publish()
  elseif kind == "lost-owner" then
    record.gates.screensaver = false
    publish()
  else
    noctalia.log("keep-awake: holder: " .. line)
  end
end

-- ── Commands (state channel + IPC share these) ───────────────────────────────

local function cmdStart(seconds, scope)
  if status == "on" and session ~= nil then
    return restartSession("set_duration", freshSession(seconds, scope))
  end
  return startSession(freshSession(seconds, scope), false)
end

local function cmdToggle()
  if status == "on" or status == "starting" then
    stopSession()
  elseif status == "off" then
    local seconds, scope = lastChoice(FALLBACK_SECONDS)
    startSession(freshSession(seconds, scope), false)
  else
    notify(tr("title"), tr("toast.busy")) -- stopping: the off notification follows in ≤ 1 s
  end
end

local function cmdExtend(minutes)
  minutes = math.floor(tonumber(minutes) or cfg.quickExtend)
  if minutes < 1 then
    return
  end
  if status == "starting" or status == "stopping" or pending ~= nil then
    notify(tr("toast.extend_refused_title"), tr("toast.busy"))
    return
  end
  if status ~= "on" or session == nil then
    notify(tr("toast.extend_refused_title"), tr("toast.extend_off"))
    return
  end
  if session.unlimited then
    notify(tr("toast.extend_refused_title"), tr("toast.extend_unlimited"))
    return
  end
  local newEnd = session.endEpoch + minutes * 60
  restartSession("extend", {
    scope = session.scope,
    unlimited = false,
    endEpoch = newEnd,
    startedEpoch = session.startedEpoch,
    chosenSeconds = session.chosenSeconds,
    label = format.label(newEnd - session.startedEpoch) .. " extended", -- system-awake:223-227
  }, minutes)
end

-- Live scope switch preserving the remaining time (v4 Panel.qml:58-73); while off it only
-- preselects the panel toggle for this process lifetime.
local function cmdSetScope(scope)
  scope = normalizeScope(scope)
  if scope == nil then
    return
  end
  if status == "on" and session ~= nil then
    if scope == session.scope then
      return
    end
    local newSession = {
      scope = scope,
      unlimited = session.unlimited,
      endEpoch = session.endEpoch,
      startedEpoch = session.startedEpoch,
      chosenSeconds = session.chosenSeconds,
      label = session.label,
    }
    if not newSession.unlimited and newSession.endEpoch - os.time() < 1 then
      newSession = freshSession(session.chosenSeconds, scope) -- v4 fell back to the selected duration
    end
    restartSession("set_scope", newSession)
  elseif status == "off" then
    pendingScope = scope
    publish()
  end
end

local function cmdSetDuration(seconds, scope)
  if seconds == nil or (seconds ~= -1 and seconds < 1) then
    return
  end
  if status == "on" and session ~= nil then
    restartSession("set_duration", freshSession(seconds, normalizeScope(scope) or session.scope))
  else
    noctalia.log(`keep-awake: set_duration ignored while {status}`)
  end
end

local function handleCommand(cmd)
  if type(cmd) ~= "table" then
    return
  end
  local action = cmd.action
  if action == "start" then
    local seconds = tonumber(cmd.seconds)
    local defSeconds, defScope = lastChoice(cfg.durations[1] * 60)
    if seconds == nil or (seconds ~= -1 and seconds < 1) then
      seconds = defSeconds
    end
    cmdStart(math.floor(seconds), normalizeScope(cmd.scope) or defScope)
  elseif action == "stop" then
    stopSession()
  elseif action == "toggle" then
    cmdToggle()
  elseif action == "extend" then
    cmdExtend(cmd.minutes)
  elseif action == "set_scope" then
    cmdSetScope(cmd.scope)
  elseif action == "set_duration" then
    local seconds = tonumber(cmd.seconds)
    cmdSetDuration(seconds ~= nil and math.floor(seconds) or nil, cmd.scope)
  else
    noctalia.log(`keep-awake: unknown command action "{tostring(action)}"`)
  end
end

local function statusLine()
  if session == nil or status == "off" then
    return tr("status.off")
  end
  local h = holder or pending
  return tr("status.line", {
    status = status,
    scope = session.scope,
    remaining = currentRemaining(),
    screensaver = (h ~= nil and h.gates.screensaver) and "1" or "0",
    logind = (h ~= nil and h.gates.logind ~= "") and h.gates.logind or "-",
  })
end

-- ── Load ─────────────────────────────────────────────────────────────────────

-- session.json from a previous runtime (reload / Noctalia restart): respawn silently with
-- the remaining time, keeping the original start and label (v4's _firstStatusApplied).
local function resumeSession()
  local saved = readJson(sessionPath)
  if saved == nil then
    return
  end
  local now = os.time()
  local scope = normalizeScope(saved.scope)
  local unlimited = saved.unlimited == true
  local endEpoch = math.floor(tonumber(saved.endEpoch) or 0)
  local startedEpoch = math.floor(tonumber(saved.startedEpoch) or now)
  local valid = scope ~= nil and (unlimited or endEpoch - now >= RESUME_MIN_SECONDS)
  if valid and not sessionInRuntimeDir and now - startedEpoch > FALLBACK_SESSION_MAX_AGE_S then
    valid = false -- no tmpfs to expire it for us: refuse a stale file after a reboot
  end
  if not valid then
    clearSession()
    return
  end
  local chosen = tonumber(saved.chosenSeconds)
  if chosen == nil or (chosen ~= -1 and chosen < 1) then
    chosen = unlimited and -1 or endEpoch - startedEpoch
  end
  local sess = {
    scope = scope,
    unlimited = unlimited,
    endEpoch = unlimited and 0 or endEpoch,
    startedEpoch = startedEpoch,
    chosenSeconds = math.floor(chosen),
    label = type(saved.label) == "string" and saved.label or format.label(math.floor(chosen)),
  }
  noctalia.log(`keep-awake: resuming {scope} session ({unlimited and "∞" or format.remaining(endEpoch - now, false)} left)`)
  startSession(sess, true)
end

readConfig()
loadLast()
noctalia.state.watch("keepawake_cmd", handleCommand)
publishRemaining()
publish()
applyInterval()

if available then
  -- Sweep orphans (a holder outliving a SIGKILLed Noctalia) BEFORE the resume spawn: the
  -- sweep pattern carries no nonce, so it must not race a holder we are about to start.
  local swept = killHolder(nil, "-TERM", function(_result)
    resumeSession()
  end)
  if not swept then
    resumeSession() -- no sweep possible; an overlapping stray is harmless and self-releases
  end
else
  lastError = tr("error.missing_dependencies")
  noctalia.log("keep-awake: " .. lastError)
  clearSession()
  publish()
end

-- ── Callbacks ────────────────────────────────────────────────────────────────

function update()
  if exiting then
    return
  end
  local now = noctalia.nowMs()

  -- nowMs is the wall clock: a suspend/resume or an NTP step shows up as one oversized (or
  -- negative) gap between ticks. Forgive it — the holder's heartbeat timer is monotonic and
  -- did not advance during a suspend — instead of declaring a healthy holder dead.
  local gap = now - lastTickMs
  if status ~= "off" and lastTickMs ~= 0 and (gap > TICK_GAP_MS or gap < 0) then
    noctalia.log(`keep-awake: tick gap of {math.floor(gap / 1000)} s (resume or clock step), timers rebased`)
    if holder ~= nil then
      holder.lastLineMs = now
      holder.spawnedMs = now
    end
    if pending ~= nil then
      pending.lastLineMs = now
      pending.spawnedMs = now
    end
    stopStartedMs = now
  end
  lastTickMs = now

  if pending ~= nil and not pending.held and now - pending.spawnedMs > SPAWN_TIMEOUT_MS then
    killHolder(pending.nonce, "-KILL")
    local message = pending.lastError ~= "" and pending.lastError or tr("error.holder_timeout", { seconds = SPAWN_TIMEOUT_S })
    pending = nil
    noctalia.notifyError(tr("toast.failed_title"), message)
    if holder == nil and status == "on" then
      endWithoutHolder(orphanReason) -- the old holder went away mid-restart too: nothing holds
      return
    end
    publish()
  end

  if status == "starting" then
    if holder ~= nil and not holder.held and now - holder.spawnedMs > SPAWN_TIMEOUT_MS then
      killHolder(holder.nonce, "-KILL")
      lastError = holder.lastError ~= "" and holder.lastError or tr("error.holder_timeout", { seconds = SPAWN_TIMEOUT_S })
      finishOff()
      noctalia.notifyError(tr("toast.failed_title"), lastError)
    end
  elseif status == "stopping" then
    if now - stopStartedMs > STOP_TIMEOUT_MS then
      if holder ~= nil then
        killHolder(holder.nonce, "-KILL") -- the locks are reclaimed regardless
      end
      finishOff()
      notify(tr("toast.disabled_title"))
    end
  elseif status == "on" then
    if holder ~= nil and holder.held then
      -- Deadline first: a timed session that ran out during a suspend (the holder's monotonic
      -- timer lagged) ends as "ended", not as a lost holder.
      if session ~= nil and not session.unlimited and os.time() > session.endEpoch + DEADLINE_GRACE_S then
        killHolder(holder.nonce, "-KILL") -- wall clock passed the deadline (suspend / clock jump)
        finishOff()
        notify(tr("toast.expired_title"))
      elseif now - holder.lastLineMs > WATCHDOG_MS then
        killHolder(holder.nonce, "-KILL")
        lastError = tr("toast.lost_desc")
        finishOff()
        noctalia.notifyError(tr("toast.lost_title"), tr("toast.lost_desc"))
      end
    elseif holder == nil and pending == nil then
      endWithoutHolder(orphanReason) -- on with no holder at all and nothing starting
    end
    publishRemaining()
  end
end

-- Defined so a settings edit reconfigures this runtime in place (the host would otherwise
-- restart the service and kill the holder).
function onConfigChanged()
  readConfig()
end

function onEnable()
  noctalia.log("keep-awake: enabled")
end

-- The host kills the holder after this returns. "reload" and "shutdown" keep session.json
-- (while a session runs) so the next load resumes.
function onExit(_signal, reason)
  exiting = true
  -- disable/uninstall end the session for good; so does a reload/shutdown that lands in the
  -- ≤ 1 s window after the user turned it off (status stopping: the file still describes
  -- the old session and the next load would resume what was explicitly ended).
  if reason == "disable" or reason == "uninstall" or status == "stopping" or status == "off" then
    clearSession()
  end
end

-- noctalia msg plugin muty/keep-awake:service all <event> [payload…]
function onIpc(event, payload)
  payload = noctalia.string.trim(payload or "")
  if event == "toggle" then
    cmdToggle()
  elseif event == "on" or event == "start" then
    local seconds, scope
    for word in payload:gmatch("%S+") do
      local asScope = normalizeScope(string.lower(word))
      if asScope ~= nil then
        scope = asScope
      else
        local parsed = format.parseDuration(word)
        if parsed == nil then
          noctalia.notifyError(tr("toast.failed_title"), tr("error.bad_duration", { text = word }))
          return
        end
        seconds = parsed
      end
    end
    local defSeconds, defScope = lastChoice(cfg.durations[1] * 60)
    cmdStart(seconds or defSeconds, scope or defScope)
  elseif event == "off" or event == "stop" then
    stopSession()
  elseif event == "extend" then
    cmdExtend(payload ~= "" and tonumber(payload:match("^(%d+)m?$")) or nil)
  elseif event == "scope" then
    cmdSetScope(string.lower(payload))
  elseif event == "status" then
    local line = statusLine()
    noctalia.log("keep-awake: " .. line)
    notify(tr("title"), line)
  else
    noctalia.log(`keep-awake: unknown IPC event "{event}"`)
  end
end
