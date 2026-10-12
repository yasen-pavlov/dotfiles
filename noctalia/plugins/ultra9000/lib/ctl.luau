--!nonstrict
-- Commands to the app (contract v1): argv runAsync of
-- `env ULTRA9000_CONTROL_SOCKET=<socket> <exe> ctl <type> '<json args>'`, never through a
-- shell. exe and socket are the ones the service is connected through (the socket owner's
-- own binary), so a command can never launch a binary that doesn't speak `ctl`. Nothing is
-- sent unless the service reports a live connection.

local M = {}

local DEFAULT_COMMAND = "ultra9000"
local TIMEOUT_MS = 10000

-- The `command` setting: used to Start the app (and as the fallback ctl binary when the
-- running instance's executable was replaced on disk).
function M.command()
  local value = noctalia.getConfig("command")
  if type(value) ~= "string" then
    return DEFAULT_COMMAND
  end
  value = noctalia.string.trim(value)
  if value == "" then
    return DEFAULT_COMMAND
  end
  return noctalia.expandPath(value)
end

-- The reply is the last stdout line ({"type":"reply",...} or {"type":"disconnected"}).
local function parseReply(stdout)
  local last = nil
  for line in string.gmatch(stdout or "", "[^\n]+") do
    last = line
  end
  if last == nil then
    return nil
  end
  local ok, value = pcall(noctalia.json.decode, last)
  if ok and type(value) == "table" then
    return value
  end
  return nil
end

-- send("select_item", { itemId = "item-3", show = true }, function(reply) ... end)
-- `args` may be nil for commands without arguments. `cb` gets the decoded reply table
-- (or nil when nothing was sent or the CLI produced none).
function M.send(command, args, cb)
  local link = noctalia.state.get("link")
  if type(link) ~= "table" or link.status ~= "connected" or type(link.exe) ~= "string" or type(link.socket) ~= "string" then
    if cb then
      cb(nil)
    end
    return false
  end
  local argv = { "env", "ULTRA9000_CONTROL_SOCKET=" .. link.socket, link.exe, "ctl", command }
  if args ~= nil and next(args) ~= nil then
    local encoded = noctalia.json.encode(args)
    if encoded == nil then
      return false
    end
    table.insert(argv, encoded)
  end
  return noctalia.runAsync(argv, function(result)
    local reply = parseReply(result and result.stdout)
    if reply ~= nil and reply.ok == false then
      noctalia.log("ultra9000: " .. command .. " → " .. tostring(reply.error))
    end
    if cb then
      cb(reply)
    end
  end, TIMEOUT_MS)
end

-- Start is offered only when the app is known not to run (no live control socket) and no
-- start is pending (pressed < 20 s ago and not connected since); the service turns
-- start_requested into status "starting", the timestamp check covers the gap before that.
local START_PENDING_MS = 20000

function M.canStart(link)
  if type(link) ~= "table" or link.status ~= "not_running" then
    return false
  end
  local requested = tonumber(noctalia.state.get("start_requested"))
  return requested == nil or noctalia.nowMs() - requested >= START_PENDING_MS
end

-- Start the app: the plain command, detached.
function M.start()
  if not M.canStart(noctalia.state.get("link")) then
    return false
  end
  noctalia.runAsync({ M.command() })
  noctalia.state.set("start_requested", noctalia.nowMs())
  return true
end

return M
