--!nonstrict
-- [[service]] link: the only entry that talks to the app's event stream.
--
-- One `runStream("<exe> ctl watch --client noctalia")`; every line is NDJSON from the app
-- (contract v1): snapshot | ping (every 5 s) | disconnected | error. The newest snapshot
-- is published as state "link" = { status, snapshot, exe, socket, at }; the bar, panel,
-- menu and launcher only watch it, and send commands through the same exe + socket.
--
-- status: not_running | starting (Start pressed, waiting for the socket) | connecting |
--         connected | protocol (the app rejected our protocol) | incompatible (the
--         socket owner's binary never spoke the protocol)
--
-- Which binary: the owner of the newest live control socket
-- ($XDG_RUNTIME_DIR/ultra-9000/control-<pid>.sock, pid alive), via /proc/<pid>/exe — the
-- process that created a control socket supports `ctl` by construction. `command` is used
-- only when that exe is gone (replaced by an upgrade) and to Start the app. Without a live
-- socket nothing is spawned: the installed v0.2.0 binary ignores argv and would open a
-- second window. ULTRA9000_CONTROL_SOCKET pins the CLI to the socket we checked.
--
-- runStream has no exit callback and no stop handle, so the stream reports its own pid
-- first (the shell prints $$, then execs the CLI under the same pid). Heartbeat: no line
-- for 12 s → kill that pid and re-check. A stream killed without ever speaking the
-- protocol marks that binary incompatible: no restart until the socket pid or `command`
-- changes.

local ctl = require("./lib/ctl.luau")

local HEARTBEAT_MS = 12000
local IDLE_POLL_MS = 1000
local FAST_POLL_MS = 250
local START_PENDING_MS = 20000

local runtimeDir = nil
do
  local xdg = noctalia.getenv("XDG_RUNTIME_DIR")
  if type(xdg) == "string" and string.sub(xdg, 1, 1) == "/" then
    runtimeDir = xdg .. "/ultra-9000"
  end
end

local generation = 0
local stream = nil -- { gen, pid, lastLineAt, spoke, owner, exe, socket }
local resolving = nil -- owner pid whose exe is being resolved
local incompatible = nil -- owner pid whose binary never spoke the protocol
local protocolRejected = false
local lastRevision = -1
local published = { status = "", revision = -2 }
local startUntil = 0
local interval = 0

local function now()
  return noctalia.nowMs()
end

local function setInterval(ms)
  if ms ~= interval then
    interval = ms
    noctalia.setUpdateInterval(ms)
  end
end

local function publish(status, snapshot)
  local revision = snapshot and snapshot.revision or -1
  if published.status == status and published.revision == revision and status ~= "connected" then
    return
  end
  published = { status = status, revision = revision }
  noctalia.state.set("link", {
    status = status,
    snapshot = snapshot,
    exe = stream and stream.exe or nil,
    socket = stream and stream.socket or nil,
    at = now(),
  })
end

-- The "nothing to talk to" status: still starting after Start, else not running.
local function publishIdle()
  publish(now() < startUntil and "starting" or "not_running", nil)
end

local function shellQuote(s)
  return "'" .. string.gsub(s, "'", "'\\''") .. "'"
end

-- The newest live control socket (the CLI's own discovery rule): pid, path.
local function liveSocket()
  if runtimeDir == nil then
    return nil
  end
  local names = noctalia.listDir(runtimeDir)
  if type(names) ~= "table" then
    return nil
  end
  local bestPid, bestPath, bestMtime = nil, nil, -1
  for _, name in ipairs(names) do
    local pid = string.match(name, "^control%-(%d+)%.sock$")
    if pid ~= nil and noctalia.fileInfo("/proc/" .. pid) ~= nil then
      local path = runtimeDir .. "/" .. name
      local info = noctalia.fileInfo(path)
      local mtime = info and info.mtime or 0
      if mtime > bestMtime then
        bestPid, bestPath, bestMtime = pid, path, mtime
      end
    end
  end
  return bestPid, bestPath
end

local function killStream()
  if stream ~= nil and stream.pid ~= nil then
    noctalia.runAsync({ "kill", tostring(stream.pid) })
  end
  stream = nil
  generation += 1 -- late lines from the old child are ignored
end

local function onLine(gen, line)
  if stream == nil or gen ~= stream.gen then
    return
  end
  stream.lastLineAt = now()
  local ok, msg = pcall(noctalia.json.decode, line)
  if not ok or type(msg) ~= "table" then
    return
  end
  local kind = msg.type
  if kind == "spawned" then
    stream.pid = tonumber(msg.pid)
    return
  end
  if kind == "snapshot" or kind == "ping" or kind == "disconnected" or kind == "error" then
    stream.spoke = true
  end
  if kind == "snapshot" then
    if msg.protocol ~= 1 then
      protocolRejected = true
      publish("protocol", nil)
      return
    end
    local revision = tonumber(msg.revision) or 0
    if revision < lastRevision then
      return -- stale; the app only ever moves forward within one connection
    end
    lastRevision = revision
    protocolRejected = false
    if startUntil > 0 then
      startUntil = 0
      noctalia.state.set("start_requested", 0) -- the start landed; Start may be offered again later
    end
    publish("connected", msg)
  elseif kind == "disconnected" then
    lastRevision = -1 -- a new connection (maybe a new app run) starts a new revision sequence
    if protocolRejected then
      publish("protocol", nil) -- the CLI reconnects and is rejected again; stay put
    else
      publishIdle()
    end
  elseif kind == "error" and msg.error == "protocol" then
    protocolRejected = true
    publish("protocol", nil)
  end
end

local function startStream(owner, socket, exe)
  generation += 1
  local gen = generation
  stream = { gen = gen, pid = nil, lastLineAt = now(), spoke = false, owner = owner, exe = exe, socket = socket }
  lastRevision = -1
  local cmd = "printf '{\"type\":\"spawned\",\"pid\":%s}\\n' \"$$\"; ULTRA9000_CONTROL_SOCKET="
    .. shellQuote(socket)
    .. " exec "
    .. shellQuote(exe)
    .. " ctl watch --client noctalia"
  local ok = noctalia.runStream(cmd, function(line)
    onLine(gen, line)
  end)
  if not ok then
    stream = nil
    return
  end
  if published.status ~= "connected" and published.status ~= "protocol" then
    -- keep showing the last snapshot (if any) until the new stream speaks
    local previous = noctalia.state.get("link")
    publish("connecting", type(previous) == "table" and previous.snapshot or nil)
  end
end

-- /proc/<pid>/exe of the socket owner, else `command` when that binary was replaced.
local function resolveAndStart(owner, socket)
  resolving = owner
  noctalia.runAsync({ "readlink", "/proc/" .. owner .. "/exe" }, function(result)
    if resolving ~= owner then
      return
    end
    resolving = nil
    local exe = noctalia.string.trim(result and result.stdout or "")
    if exe == "" or string.find(exe, " (deleted)", 1, true) or noctalia.fileInfo(exe) == nil then
      exe = ctl.command()
    end
    if stream == nil and incompatible ~= owner then
      startStream(owner, socket, exe)
    end
  end, 2000)
end

local function tick()
  local t = now()
  local owner, socket = liveSocket()
  if stream ~= nil then
    if owner ~= stream.owner then
      killStream() -- the instance went away or a newer one appeared
    elseif t - stream.lastLineAt > HEARTBEAT_MS then
      if not stream.spoke then
        incompatible = stream.owner
        noctalia.log("ultra9000: " .. tostring(stream.exe) .. " never spoke the control protocol; not retrying")
      end
      killStream()
    else
      return
    end
  end
  if owner == nil then
    incompatible = nil
    protocolRejected = false
    publishIdle()
  elseif owner == incompatible then
    publish("incompatible", nil)
  elseif resolving == nil then
    resolveAndStart(owner, socket)
  end
end

function update()
  tick()
  setInterval((stream == nil and now() < startUntil) and FAST_POLL_MS or IDLE_POLL_MS)
end

function onConfigChanged()
  -- `command` is the fallback binary: forget a verdict about it and reconnect
  incompatible = nil
  resolving = nil
  killStream()
  publishIdle()
  tick()
end

function onExit()
  killStream()
end

-- After "Start Ultra 9000": "starting" until the first snapshot or 20 s, and poll for the
-- socket fast meanwhile (board 09: reconnect "immediate after Start").
noctalia.state.watch("start_requested", function(value)
  if (tonumber(value) or 0) == 0 then
    return
  end
  startUntil = now() + START_PENDING_MS
  if published.status == "not_running" then
    publish("starting", nil)
  end
  setInterval(FAST_POLL_MS)
end)

-- `noctalia msg plugin muty/ultra9000:link all dump` logs the link state.
function onIpc(event)
  if event == "dump" then
    noctalia.log(string.format(
      "ultra9000 link: status=%s revision=%s stream=%s pid=%s exe=%s incompatible=%s",
      published.status, tostring(published.revision), tostring(stream ~= nil),
      tostring(stream and stream.pid), tostring(stream and stream.exe), tostring(incompatible)
    ))
  end
end

setInterval(IDLE_POLL_MS)
tick()
