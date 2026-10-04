--!nonstrict
-- Shared formatting helpers for muty/keep-awake, loaded with require("./lib/format.luau")
-- (plugin API 22). Every entry gets its own module instance, so this file stays pure —
-- no noctalia.* calls, no state — and the same code serves the service, the bar widget,
-- the tile and the panel.

local M = {}

-- Duration label, byte-compatible with v4's format_label (system-awake:72-86 /
-- Main.qml:163-172) so persisted duration_label values keep matching:
--   -1 -> "∞", 1800 -> "30m", 3600 -> "1h", 5400 -> "1h30m", 3900 -> "1h05m".
function M.label(seconds)
  if seconds == -1 then
    return "∞"
  end
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds >= 3600 then
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if m == 0 then
      return `{h}h`
    end
    return string.format("%dh%02dm", h, m)
  end
  return `{math.floor(seconds / 60)}m`
end

-- Vague, minute-granular remaining text (v4 rendered Time.formatVagueHumanReadableDuration):
-- unlimited -> "∞"; under a minute -> "<1m"; otherwise rounded UP to whole minutes and
-- rendered with label(), e.g. "29m", "1h05m". The text changes at most once a minute,
-- which is what keeps the bar relayout and the cross-VM state copies rare.
function M.remaining(secondsLeft, unlimited)
  if unlimited then
    return "∞"
  end
  secondsLeft = tonumber(secondsLeft) or 0
  if secondsLeft < 60 then
    return "<1m"
  end
  return M.label(math.ceil(secondsLeft / 60) * 60)
end

-- IPC duration payloads -> seconds, -1 for unlimited, nil when unparseable or < 1 s
-- (v4 refused sub-second durations because `timeout 0s` meant forever, Main.qml:176-181).
-- Accepts "30m", "2h", "1h30m", "90s", "unlimited" | "inf" | "∞" | "-1", or a bare
-- integer (seconds).
function M.parseDuration(text)
  local s = (string.lower(tostring(text or "")):gsub("%s+", ""))
  if s == "" then
    return nil
  end
  if s == "unlimited" or s == "inf" or s == "infinite" or s == "forever" or s == "∞" or s == "-1" then
    return -1
  end
  local seconds
  local h, m = s:match("^(%d+)h(%d+)m?$")
  if h ~= nil then
    seconds = tonumber(h) * 3600 + tonumber(m) * 60
  elseif s:match("^%d+h$") then
    seconds = tonumber(s:sub(1, -2)) * 3600
  elseif s:match("^%d+m$") then
    seconds = tonumber(s:sub(1, -2)) * 60
  elseif s:match("^%d+s$") then
    seconds = tonumber(s:sub(1, -2))
  elseif s:match("^%d+$") then
    seconds = tonumber(s)
  else
    return nil
  end
  if seconds == nil or seconds < 1 then
    return nil
  end
  return math.floor(seconds)
end

-- POSIX single-quoting for the one place a value is spliced into a /bin/sh command line
-- (noctalia.runStream has no argv form). The parentheses drop gsub's second return value.
function M.shq(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

return M
