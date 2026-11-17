--!nonstrict
-- Shared formatting helpers for muty/borg-backup, loaded with require("./lib/format.luau")
-- (plugin API 22). Every entry gets its own module instance, so this file stays pure: no
-- noctalia.* calls and no state. Word-bearing helpers take the entry's `tr` so every
-- user-visible word still comes from translations/<lang>.json.

local M = {}

-- Non-negative integer from a decoded JSON value, else nil. Fractions are rejected, not
-- floored: the files only ever carry integers, so 123.9 is malformed data.
function M.count(value)
  if type(value) ~= "number" or value ~= value or value < 0 or value >= 2 ^ 53 or value ~= math.floor(value) then
    return nil
  end
  return value
end

-- 2683828 -> "2,683,828" (sep from translations; any UTF-8 string).
function M.thousands(n, sep)
  local digits = tostring(math.floor(math.max(0, tonumber(n) or 0)))
  local head = #digits % 3
  local parts = {}
  if head > 0 then
    table.insert(parts, digits:sub(1, head))
  end
  for i = head + 1, #digits, 3 do
    table.insert(parts, digits:sub(i, i + 2))
  end
  return table.concat(parts, sep)
end

-- Decimal sizes exactly like borg's format_file_size: "123 B", "2.15 GB", "475.81 GB".
local UNITS = { "", "k", "M", "G", "T", "P", "E", "Z" }
function M.bytes(n)
  local value = math.max(0, tonumber(n) or 0)
  local index = 1
  -- Same rounding test as borg: 999.996 kB is shown as "1.00 MB", not "1000.00 kB".
  while index < #UNITS and math.floor(value * 100 + 0.5) / 100 >= 1000 do
    value /= 1000
    index += 1
  end
  if index == 1 then
    return string.format("%d B", math.floor(value + 0.5))
  end
  return string.format("%.2f %sB", value, UNITS[index])
end

-- Progress estimate: floor(min(nfiles / expected, 0.99) * 100), nil without a baseline.
function M.percent(nfiles, expected)
  if type(expected) ~= "number" or expected <= 0 then
    return nil
  end
  local ratio = math.min((tonumber(nfiles) or 0) / expected, 0.99)
  return math.floor(ratio * 100)
end

-- Wall-time duration: "45s", "3m 26s", "1h 05m".
function M.duration(seconds, tr)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds < 60 then
    return tr("duration.seconds", { s = seconds })
  elseif seconds < 3600 then
    return tr("duration.minutes", { m = math.floor(seconds / 60), s = string.format("%02d", seconds % 60) })
  end
  return tr("duration.hours", { h = math.floor(seconds / 3600), m = string.format("%02d", math.floor((seconds % 3600) / 60)) })
end

-- Coarse age of a past instant: "just now", "12 min ago", "5 h ago", "3 d ago".
function M.ago(seconds, tr)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if seconds < 60 then
    return tr("time.just_now")
  elseif seconds < 3600 then
    return tr("time.minutes_ago", { n = math.floor(seconds / 60) })
  elseif seconds < 86400 then
    return tr("time.hours_ago", { n = math.floor(seconds / 3600) })
  end
  return tr("time.days_ago", { n = math.floor(seconds / 86400) })
end

-- Coarse distance to a future instant: "now", "in 12 min", "in 5 h", "in 3 d".
function M.fromNow(seconds, tr)
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds < 60 then
    return tr("time.now")
  elseif seconds < 3600 then
    return tr("time.in_minutes", { n = math.floor(seconds / 60) })
  elseif seconds < 86400 then
    return tr("time.in_hours", { n = math.floor(seconds / 3600) })
  end
  return tr("time.in_days", { n = math.floor(seconds / 86400) })
end

return M
