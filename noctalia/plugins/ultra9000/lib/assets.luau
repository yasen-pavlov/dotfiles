--!nonstrict
-- Small state shapes (U_ mark, working arc, on-job ring, row badges) as SVG files.
--
-- Noctalia v5.2.1's ui.image has no tint prop (the canvas assumed one), so instead of
-- shipping monochrome masks these are written pre-coloured from the live palette into
-- the plugin data dir — the board-09 "pre-coloured copies" fallback, made at runtime so
-- the colours still follow palette roles. File names carry the colours, so a palette
-- switch produces new files instead of fighting the image cache. Brand tool marks are
-- fixed-colour plugin assets (assets/marks/*.svg).

local M = {}

local ARC_FRAMES = 12
M.ARC_FRAMES = ARC_FRAMES

local genDir = nil

local function dir()
  if genDir == nil then
    local base = noctalia.pluginDataDir()
    if base == nil then
      return nil
    end
    genDir = base .. "/gen"
    noctalia.mkdirAll(genDir)
  end
  return genDir
end

local function hexKey(...)
  local parts = {}
  for _, v in ipairs({ ... }) do
    table.insert(parts, (tostring(v):gsub("#", "")))
  end
  return table.concat(parts, "-")
end

local function ensure(name, svg)
  local d = dir()
  if d == nil then
    return nil
  end
  local path = d .. "/" .. name .. ".svg"
  if noctalia.fileInfo(path) == nil then
    noctalia.writeFile(path, svg)
  end
  return path
end

local function svg(w, h, body)
  return string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%s" height="%s">%s</svg>',
    w, h, w, h, body
  )
end

local U_PATH = "M1 3h3v6a1 1 0 0 0 2 0V3h3v6a4 4 0 0 1-8 0Z"
local CURSOR_PATH = "M11 11h4v2h-4Z"

-- The bar mark (board 02): "U_" when running, "U" without its cursor when not. With
-- `dot`, the unread dot sits top-right in a 19 px wide box (board: 6 px, top −2, right −3
-- of the 16 px mark) — drawn into the image because v5.2.1 has no overlay container.
function M.mark(color, running, dot)
  if not running then
    return ensure("mark-off-" .. hexKey(color), svg(16, 16, string.format('<path fill="%s" d="%s"/>', color, U_PATH)))
  end
  local body = string.format('<path fill="%s" d="%s %s"/>', color, U_PATH, CURSOR_PATH)
  if dot == nil then
    return ensure("mark-on-" .. hexKey(color), svg(16, 16, body))
  end
  body = body .. string.format('<circle cx="16" cy="2.5" r="3" fill="%s"/>', dot)
  return ensure("mark-dot-" .. hexKey(color, dot), svg(19, 16, body))
end

-- Working: a half arc on a dim track (CSS border-top + border-right), 12 px box, 2 px line.
-- frame 0 is the static bar stand-in; 1..11 are the panel's pre-rotated frames.
function M.arc(color, track, frame)
  frame = frame or 0
  local body = string.format(
    '<circle cx="6" cy="6" r="5" fill="none" stroke="%s" stroke-width="2"/>'
      .. '<path d="M2.4645 2.4645A5 5 0 0 1 9.5355 9.5355" fill="none" stroke="%s" stroke-width="2"'
      .. ' transform="rotate(%d 6 6)"/>',
    track, color, frame * (360 / ARC_FRAMES)
  )
  return ensure(string.format("arc%02d-%s", frame, hexKey(color, track)), svg(12, 12, body))
end

-- On job: hollow ring (1.5 px) with a 3 px dot, 12 px box.
function M.ring(color)
  local body = string.format(
    '<circle cx="6" cy="6" r="5.25" fill="none" stroke="%s" stroke-width="1.5"/><circle cx="6" cy="6" r="1.5" fill="%s"/>',
    color, color
  )
  return ensure("ring-" .. hexKey(color), svg(12, 12, body))
end

-- The on-job pill's leading ring (board 08: no dashed border, a 9 px hollow ring instead).
function M.pillRing(color)
  local body = string.format('<circle cx="4.5" cy="4.5" r="3.75" fill="none" stroke="%s" stroke-width="1.5"/>', color)
  return ensure("pillring-" .. hexKey(color), svg(9, 9, body))
end

-- Row badges (board 03/05), 12 px. "work" uses the arc frames, "onjob" the ring.
function M.badge(kind, c, frame)
  if kind == "work" then
    return M.arc(c.purple, c.purpleLine, frame or 0)
  elseif kind == "onjob" then
    return M.ring(c.purple)
  elseif kind == "need" then
    return ensure("badge-need-" .. hexKey(c.primary), svg(12, 12, string.format(
      '<circle cx="6" cy="6" r="6" fill="%s"/><rect x="5.2" y="2.4" width="1.6" height="4.6" rx="0.6" fill="%s"/>'
        .. '<circle cx="6" cy="9.1" r="0.95" fill="%s"/>',
      c.primary, c.needText, c.needText
    )))
  elseif kind == "err" then
    return ensure("badge-err-" .. hexKey(c.errorColor), svg(12, 12, string.format(
      '<circle cx="6" cy="6" r="6" fill="%s"/><path d="M4 4L8 8M8 4L4 8" stroke="#22000a" stroke-width="1.5" stroke-linecap="round"/>',
      c.errorColor
    )))
  elseif kind == "exit" then
    return ensure("badge-exit-" .. hexKey(c.onSurfaceVariant), svg(12, 12, string.format(
      '<circle cx="6" cy="6" r="6" fill="%s"/><rect x="4" y="4" width="4" height="4" fill="#111111"/>',
      c.onSurfaceVariant
    )))
  elseif kind == "busy" then
    return ensure("badge-busy-" .. hexKey(c.busyBadge, c.busyGlyph), svg(12, 12, string.format(
      '<circle cx="6" cy="6" r="6" fill="%s"/><path d="M5 3.6L8.6 6L5 8.4Z" fill="%s"/>',
      c.busyBadge, c.busyGlyph
    )))
  end
  return nil
end

return M
