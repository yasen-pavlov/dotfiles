--!nonstrict
-- Colours from board 08 (Tokens): a Noctalia palette role wherever one matches, a hard-coded
-- hex only where no role exists. Every hard-coded hex has a light-palette pair, chosen by
-- the luminance of the palette's `surface` (< 0.5 → dark set). Tool tiles and marks are
-- brand-fixed in every palette.

local M = {}

local function channel(hex, from)
  local v = tonumber(string.sub(hex, from, from + 1), 16) / 255
  if v <= 0.03928 then
    return v / 12.92
  end
  return ((v + 0.055) / 1.055) ^ 2.4
end

local function luminance(hex)
  if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x") then
    return 0
  end
  return 0.2126 * channel(hex, 2) + 0.7152 * channel(hex, 4) + 0.0722 * channel(hex, 6)
end

local function role(name, fallback)
  local ok, value = pcall(noctalia.getColor, name)
  if ok and type(value) == "string" then
    return value
  end
  return fallback
end

-- Resolved per call (cheap): a palette switch rebuilds widgets/panels, and services re-read.
function M.colors()
  local surface = role("surface", "#212121")
  local dark = luminance(surface) < 0.5
  local onSurface = role("on_surface", "#b0bec5")
  local c = {
    dark = dark,
    surface = surface,
    onSurface = onSurface,
    onSurfaceVariant = role("on_surface_variant", "#8c8b8b"),
    primary = role("primary", "#ff9800"),
    errorColor = role("error", "#ff5370"),
    secondary = role("secondary", "#82aaff"),
    -- tile + marks: fixed in every palette
    tile = "#2b2b2b",
    tileLine = "#3b3b3b",
    needText = "#1d1200",
    busyBadge = "#3a4549",
    busyGlyph = "#c5d0d5",
  }
  if dark then
    c.title = "#e4ebee"
    c.purple = "#c792ea"
    c.purpleLine = "#54426a"
    c.unread = "#eeffff"
    c.project = "#a3a9ac"
    c.path = "#6d6d6d"
    c.errLine = "#6b2a35"
    c.turnText, c.turnLine = "#e4ebee", "#5a5a5a"
    c.seenText, c.seenLine = "#a3a3a3", "#3a3a3a"
    c.exitLine = "#353535"
    c.busyLine = "#404040"
    c.disabled = "#5f5f5f"
    c.footerLine = "#2c2c2c"
    c.kbdFill, c.kbdLine = "#1b1b1b", "#3c3c3c"
  else
    c.title = onSurface
    c.purple = "#7e57c2"
    c.purpleLine = "#c9b8e6"
    c.unread = onSurface
    c.project = "#5b6469"
    c.path = "#8a8a8a"
    c.errLine = "#f0b3bd"
    c.turnText, c.turnLine = onSurface, "#9e9e9e"
    c.seenText, c.seenLine = "#7a7a7a", "#d6d6d6"
    c.exitLine = "#dcdcdc"
    c.busyLine = "#cfcfcf"
    c.disabled = "#a0a0a0"
    c.footerLine = "#e0e0e0"
    c.kbdFill, c.kbdLine = "#ffffff", "#d0d0d0"
  end
  return c
end

return M
