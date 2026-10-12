--!nonstrict
-- [[panel]] panel: the app's sidebar, one click away (boards 05, 06, 07).
--
-- Projects and rows render exactly in snapshot order; nothing moves when a state changes.
-- The row the app shows is filled (surface_variant); the keyboard focus ring (secondary)
-- is separate and appears with the first key (or at once with `panel-toggle … keys`).
--
-- Noctalia v5.2.1 differences from the canvas, and the fallbacks used here:
--   * no overlay container: the state badge and unread dot sit after the title (board 09
--     fallback) instead of on the tile;
--   * ui.image cannot tint or rotate: shapes are pre-coloured SVGs (lib/assets.luau), the
--     working arc turns by swapping 12 pre-rotated frames every 92 ms (board 08/09);
--   * native context menus open only from a ui.button's right click: each row carries a
--     ⋯ button (right click → native row menu; left click → the same actions inline, like
--     the close question), and the header/project + buttons do "new agent" on click and
--     open their menu on right click;
--   * no floating overlay and no scroll-to-row: the edge chip lives in the footer, and a
--     row is scrolled into view by rendering the list cut after it with scrollToBottomRev
--     (plus a spacer when it must land at the top), then the full list again.

local model = require("./lib/model.luau")
local theme = require("./lib/theme.luau")
local assets = require("./lib/assets.luau")
local ctl = require("./lib/ctl.luau")

local tr = noctalia.tr

-- Base sizes (× ui_scale): board 08. Noctalia pads a panel's content by PANEL_PAD on every
-- side (Style::panelPadding), so the content box = manifest size − 2 × PANEL_PAD.
local PANEL_PAD = 14
local CONTENT_W = 360 - 2 * PANEL_PAD
local CONTENT_H = 600 - 2 * PANEL_PAD
local HEADER_H = 32
local KBD_H = 15
local CHIP_H = 24
-- hairline + PANEL_PAD + hint row; the panel's own PANEL_PAD below mirrors it (footer())
local FOOTER_H = 1 + PANEL_PAD + KBD_H
local SECTION_GAP = 8
local LIST_H = CONTENT_H - HEADER_H - FOOTER_H - 2 * SECTION_GAP
local LIST_W = CONTENT_W - 14 -- scrollbar 6 + gap 8
local ROW_H = 42
local PROJECT_H = 26
local PINNED_EMPTY_H = 22
local GROUP_GAP = 10
local TILE = 25
local MARK = 15
local BADGE = 10
local DOT = 6.67
local ROW_PAD_L, ROW_PAD_R = 8.33, 6.67
local ROW_GAP = 9
local MORE_W = 22
local TEXT_W = LIST_W - ROW_PAD_L - ROW_PAD_R - TILE - ROW_GAP - MORE_W - ROW_GAP
local ARC_STEP_MS = 92
local TRANSPARENT = "#00000000"

local KEY_ACTIONS = {
  Up = "up", Down = "down", Home = "home", End = "end",
  Return = "enter", KP_Enter = "enter", Delete = "close",
  j = "jump", n = "new_agent", t = "new_terminal", e = "new_neovim", w = "close", o = "palette", h = "window",
  -- the same physical keys on Bulgarian phonetic (keysym matching, see plugin.toml)
  Cyrillic_shorti = "jump", Cyrillic_en = "new_agent", Cyrillic_te = "new_terminal", Cyrillic_ie = "new_neovim",
  Cyrillic_ve = "close", Cyrillic_o = "palette", Cyrillic_ha = "window",
}

local CLOSE_REASONS = {
  ["agent-working"] = "confirm.agent_working",
  ["agent-needs-you"] = "confirm.agent_needs_you",
  ["foreground-job"] = "confirm.foreground_job",
  ["neovim"] = "confirm.neovim",
  ["unmonitored-agent"] = "confirm.unmonitored_agent",
}

local link = model.link()
local isOpen = false
local focusId = nil
local hoverId = nil
local hoverControl = nil
local confirm = nil -- { itemId, reason }
local actionsFor = nil -- item id whose inline action list is open
local arcFrame = 0
local arcAccum = 0
local renderedMinute = -1
local scrollOffset = 0 -- px, from onScroll
local scrollRev = 0
local reveal = nil -- { itemId, pad, frames }
local layoutY = {} -- item id → { y, h } in base px, from the last full render
local frameTickOn = false

local render

-- ── helpers ────────────────────────────────────────────────────────────────

local function uiScale()
  local ok, value = pcall(noctalia.getSetting, "accessibility.ui_scale")
  if ok and type(value) == "number" and value > 0 then
    return value
  end
  return 1
end

local function snap()
  return link.snapshot
end

-- Items in visible order (projects in snapshot order, each project's itemIds in order).
local function visibleItems()
  local s = snap()
  if s == nil then
    return {}
  end
  local byId = model.itemsById(s)
  local out = {}
  for _, p in ipairs(s.projects or {}) do
    for _, id in ipairs(p.itemIds or {}) do
      if byId[id] ~= nil then
        table.insert(out, byId[id])
      end
    end
  end
  return out
end

local function indexOf(list, id)
  for i, it in ipairs(list) do
    if it.id == id then
      return i
    end
  end
  return nil
end

local function selectedId()
  for _, it in ipairs(visibleItems()) do
    if it.selected then
      return it.id
    end
  end
  return nil
end

local function itemById(id)
  if id == nil or snap() == nil then
    return nil
  end
  return model.itemsById(snap())[id]
end

local function projectById(id)
  if id == nil or snap() == nil then
    return nil
  end
  return model.projectsById(snap())[id]
end

-- Agent/terminal text for native menu labels, which reject > 512 bytes: at most 120
-- codepoints (≤ 480 bytes) plus "…". Invalid UTF-8 falls back to a byte cut.
local function clip(text)
  text = tostring(text or "")
  local n = utf8.len(text)
  if n == nil then
    return string.sub(text, 1, 360) .. "…"
  end
  if n <= 120 then
    return text
  end
  return string.sub(text, 1, utf8.offset(text, 121) - 1) .. "…"
end

local function approxWidth(text, size)
  return (utf8.len(text or "") or #(text or "")) * size * 0.53
end

local function close()
  panel.close()
end

-- ── commands ───────────────────────────────────────────────────────────────

local function selectItem(id)
  ctl.send("select_item", { itemId = id, show = true })
  close()
end

local function jump()
  local s = snap()
  if s == nil or s.waiting == nil or s.waiting.nextItemId == nil then
    return
  end
  ctl.send("jump_to_waiting", nil)
  close()
end

local function toggleWindow()
  ctl.send("set_window_visible", { visible = "toggle" })
end

local function newItem(projectId, kind)
  if projectId == nil then
    return
  end
  ctl.send("new_item", { projectId = projectId, kind = kind })
end

local function openPalette(projectId)
  ctl.send("open_palette", projectId and { projectId = projectId } or nil)
  close()
end

local function requestQuit()
  ctl.send("request_quit", nil)
  close()
end

-- The item's state as the close question saw it (board 07: if it changed, ask again).
local function closeStamp(it)
  local fg = type(it.foregroundJob) == "table" and tostring(it.foregroundJob.command) or ""
  return tostring(it.state) .. "|" .. tostring(it.stateSinceMs) .. "|" .. fg
end

local function closeItem(id, confirmed)
  local it = itemById(id)
  if it == nil then
    return
  end
  ctl.send("close_item", { itemId = id, confirmed = confirmed }, function(reply)
    if reply == nil or reply.ok ~= true then
      confirm = nil
      render()
      return
    end
    if reply.result == "needs-confirmation" then
      local current = itemById(id) or it
      confirm = { itemId = id, reason = reply.reason, stamp = closeStamp(current) }
      actionsFor = nil
      focusId = id
    else
      -- closed: the link watcher moves the ring when the snapshot drops the row
      confirm = nil
    end
    render()
  end)
end

-- Confirm the pending question; unchanged item → confirmed, else re-ask the app.
local function confirmClose()
  if confirm == nil then
    return
  end
  local it = itemById(confirm.itemId)
  if it == nil then
    confirm = nil
    render()
    return
  end
  closeItem(it.id, closeStamp(it) == confirm.stamp)
end

local function startApp()
  ctl.start()
end

-- ── scrolling a row into view ──────────────────────────────────────────────

local function revealItem(id)
  local pos = layoutY[id]
  if pos == nil then
    return
  end
  local top = scrollOffset / uiScale()
  if pos.y >= top and pos.y + pos.h <= top + LIST_H then
    return
  end
  local pad = 0
  if pos.y < top then
    pad = math.max(0, LIST_H - pos.h) -- land at the top
  end
  reveal = { itemId = id, pad = pad, frames = 0 }
  scrollRev += 1
  render()
end

-- ── context menus (native; only from a ui.button right click) ──────────────

function onRowMenu(action, id)
  local it = itemById(id)
  if it == nil then
    return
  end
  if action == "show" then
    selectItem(id)
  elseif action == "new_agent" then
    newItem(it.projectId, "agent")
  elseif action == "new_terminal" then
    newItem(it.projectId, "shell")
  elseif action == "new_neovim" then
    newItem(it.projectId, "neovim")
  elseif action == "jump" then
    jump()
  elseif action == "close" then
    focusId = id
    closeItem(id, false)
  end
end

function onProjectMenu(action, projectId)
  if action == "new_agent" then
    newItem(projectId, "agent")
  elseif action == "new_terminal" then
    newItem(projectId, "shell")
  elseif action == "new_neovim" then
    newItem(projectId, "neovim")
  elseif action == "palette" then
    openPalette(projectId)
  end
end

function onWindowMenu(action)
  if action == "window" then
    toggleWindow()
  elseif action == "palette" then
    openPalette(nil)
  elseif action == "quit" then
    requestQuit()
  end
end

local function rowMenuItems(it)
  local p = projectById(it.projectId)
  local s = snap()
  local waiting = s and s.waiting and s.waiting.nextItemId ~= nil
  return {
    { kind = "header", label = clip(it.title) },
    { id = "show", label = tr("menu.show_in_app") },
    { id = "new_agent", label = tr("menu.new_agent_in", { project = clip(p and p.name or "") }) },
    { id = "new_terminal", label = tr("menu.new_terminal_here") },
    { id = "new_neovim", label = tr("menu.new_neovim_here") },
    { kind = "separator" },
    { id = "jump", label = tr("menu.jump"), enabled = waiting },
    { kind = "separator" },
    { id = "close", label = tr("menu.close") },
  }
end

local function openRowMenu(it)
  panel.openContextMenu({ items = rowMenuItems(it), onActivate = "onRowMenu", context = it.id })
end

local function openProjectMenu(projectId)
  local p = projectById(projectId)
  if p == nil then
    return
  end
  panel.openContextMenu({
    items = {
      { kind = "header", label = clip(p.name) },
      { id = "new_agent", label = tr("menu.new_agent") },
      { id = "new_terminal", label = tr("menu.new_terminal") },
      { id = "new_neovim", label = tr("menu.new_neovim") },
      { kind = "separator" },
      { id = "palette", label = tr("menu.palette_for_project") },
    },
    onActivate = "onProjectMenu",
    context = projectId,
  })
end

local function openWindowMenu()
  local s = snap()
  local visible = s and s.app and s.app.windowVisible
  panel.openContextMenu({
    items = {
      { id = "window", label = visible and tr("menu.hide_app") or tr("menu.show_app") },
      { id = "palette", label = tr("menu.palette") },
      { kind = "separator" },
      { id = "quit", label = tr("menu.quit") },
    },
    onActivate = "onWindowMenu",
  })
end

-- ── building blocks ────────────────────────────────────────────────────────

local function kbd(c, key)
  return ui.row({ paddingH = 4, height = KBD_H, radius = 3, fill = c.kbdFill, border = c.kbdLine, borderWidth = 1, align = "center" }, {
    ui.label({ text = key, fontSize = 10, color = c.onSurfaceVariant }),
  })
end

local function hint(c, key, text)
  return ui.row({ key = "hint-" .. key, gap = 5, align = "center" }, {
    kbd(c, key),
    ui.label({ text = text, fontSize = 11, color = c.onSurfaceVariant }),
  })
end

local function tile(c, it)
  local mark = model.markPath(it)
  local child
  if mark ~= nil then
    child = ui.image({ path = mark, width = MARK, height = MARK, opacity = it.state == "exited" and 0.55 or 1 })
  else
    child = ui.glyph({ name = "robot", size = 13, color = c.title })
  end
  return ui.row({
    width = TILE, height = TILE, radius = 6.67, fill = c.tile, border = c.tileLine, borderWidth = 1,
    align = "center", justify = "center",
  }, { child })
end

local PILL_COLORS = {
  work = function(c) return c.purple, c.purpleLine, TRANSPARENT end,
  onjob = function(c) return c.purple, TRANSPARENT, TRANSPARENT end,
  need = function(c) return c.needText, c.primary, c.primary end,
  turn = function(c) return c.turnText, c.turnLine, TRANSPARENT end,
  seen = function(c) return c.seenText, c.seenLine, TRANSPARENT end,
  err = function(c) return c.errorColor, c.errLine, TRANSPARENT end,
  exit = function(c) return c.onSurfaceVariant, c.exitLine, TRANSPARENT end,
  cmd = function(c) return c.onSurface, c.busyLine, TRANSPARENT end,
}

local function pillWidth(p)
  local w = approxWidth(p.text, 10.5) + 2 * 5.83 + 2
  if p.kind == "onjob" then
    w += 7.5 + 3.33 - 2.5
  end
  return w
end

local function pill(c, p)
  local text, border, fill = PILL_COLORS[p.kind](c)
  local children = {}
  if p.kind == "onjob" then
    table.insert(children, ui.image({ path = assets.pillRing(c.purple), width = 7.5, height = 7.5 }))
  end
  table.insert(children, ui.label({
    text = p.text,
    fontSize = p.kind == "cmd" and 10 or 10.5,
    fontWeight = p.kind == "need" and "semibold" or (p.kind == "cmd" and "normal" or "medium"),
    fontFamily = p.kind == "cmd" and "JetBrainsMono Nerd Font" or "SF Pro Text",
    color = text,
    maxLines = 1,
  }))
  return ui.row({
    height = 15.83, paddingH = p.kind == "onjob" and 3.33 or 5.83, radius = 8, gap = 3.33, align = "center",
    fill = fill, border = border, borderWidth = 1,
  }, children)
end

local function moreButton(c, it, shown)
  return ui.button({
    key = "more-" .. it.id,
    glyph = "dots-vertical",
    glyphSize = 14,
    variant = "ghost",
    width = MORE_W,
    height = MORE_W,
    opacity = shown and 1 or 0,
    tooltip = tr("panel.row_actions"),
    onClick = function()
      actionsFor = (actionsFor ~= it.id) and it.id or nil
      confirm = nil
      focusId = it.id
      render()
    end,
    onRightClick = function()
      openRowMenu(it)
    end,
  })
end

local function itemRow(c, it, index)
  local focused = focusId == it.id
  local hovered = hoverId == it.id
  local fill = it.selected and "surface_variant" or (hovered and "surface_variant/0.35" or TRANSPARENT)
  local badgeKind = model.badge(it)
  local now = noctalia.nowMs()
  local p = model.pill(it, now)

  local titleW = TEXT_W
  local titleRow = {}
  if badgeKind ~= nil then
    titleW -= BADGE + 4
  end
  if it.unread then
    titleW -= DOT + 4
  end
  local truncated = approxWidth(it.title, 13) > titleW
  table.insert(titleRow, ui.label({
    text = it.title, fontSize = 13, color = it.state == "exited" and c.onSurface or c.title,
    maxLines = 1, maxWidth = titleW,
  }))
  if badgeKind ~= nil then
    table.insert(titleRow, ui.image({ path = assets.badge(badgeKind, c, arcFrame), width = BADGE, height = BADGE }))
  end
  if it.unread then
    table.insert(titleRow, ui.box({ width = DOT, height = DOT, radius = DOT / 2, fill = c.unread }))
  end

  local subW = TEXT_W
  local sub = {}
  if p ~= nil then
    subW -= pillWidth(p) + 6
  end
  table.insert(sub, ui.label({
    text = model.subline(it, now), fontSize = 11, color = c.onSurfaceVariant, maxLines = 1, maxWidth = subW, flexGrow = 1,
  }))
  if p ~= nil then
    table.insert(sub, pill(c, p))
  end

  return ui.row({
    key = "row-" .. it.id,
    height = ROW_H,
    paddingH = (ROW_PAD_L + ROW_PAD_R) / 2,
    gap = ROW_GAP,
    align = "center",
    radius = 9,
    fill = fill,
    border = focused and c.secondary or TRANSPARENT,
    borderWidth = focused and 2 or 0,
    tooltip = truncated and it.title or "",
    onClick = function()
      selectItem(it.id)
    end,
    onHover = function(state)
      if state == "true" then
        hoverId = it.id
      elseif hoverId == it.id then
        hoverId = nil
      end
      render()
    end,
  }, {
    tile(c, it),
    ui.column({ flexGrow = 1, gap = 1, justify = "center" }, {
      ui.row({ gap = 4, align = "center" }, titleRow),
      ui.row({ gap = 6, align = "center" }, sub),
    }),
    moreButton(c, it, focused or hovered or it.selected or actionsFor == it.id),
  })
end

-- `icon` is a Tabler glyph name, or `{ image = path }` for a brand mark (v5.2.1's Tabler set
-- has no Neovim glyph, so that line shows the same mark asset as the Neovim tile).
local function menuLine(c, key, icon, label, k, enabled, onClick)
  local hovered = hoverControl == key
  local lead
  if type(icon) == "table" then
    lead = ui.image({ path = icon.image, width = 14, height = 14, opacity = enabled and 1 or 0.55 })
  else
    lead = ui.glyph({ name = icon, size = 14, color = enabled and c.onSurfaceVariant or c.disabled })
  end
  return ui.row({
    key = key, height = 28, paddingH = 8, radius = 6, gap = 8, align = "center",
    fill = (hovered and enabled) and "surface/0.6" or TRANSPARENT,
    onClick = enabled and onClick or "",
    onHover = function(state)
      hoverControl = state == "true" and key or (hoverControl ~= key and hoverControl or nil)
      render()
    end,
  }, {
    lead,
    ui.label({ text = label, fontSize = 13, color = enabled and c.title or c.disabled, flexGrow = 1, maxLines = 1, maxWidth = LIST_W - 90 }),
    k and kbd(c, k) or ui.spacer({ width = 1 }),
  })
end

-- Inline action list (the row menu for a left click on ⋯).
local function actionsBlock(c, it)
  local p = projectById(it.projectId)
  local s = snap()
  local waiting = s and s.waiting and s.waiting.nextItemId ~= nil
  return ui.column({
    key = "actions-" .. it.id, fill = "surface_variant", radius = 9, padding = 6, gap = 0,
    border = c.secondary, borderWidth = 2,
  }, {
    ui.row({ gap = ROW_GAP, align = "center", height = 32, paddingH = 2 }, {
      tile(c, it),
      ui.label({ text = it.title, fontSize = 13, fontWeight = "medium", color = c.title, maxLines = 1, maxWidth = LIST_W - 80, flexGrow = 1 }),
      ui.button({ key = "actions-x", glyph = "x", glyphSize = 13, variant = "ghost", width = MORE_W, height = MORE_W,
        tooltip = tr("panel.cancel"), onClick = function() actionsFor = nil; render() end }),
    }),
    menuLine(c, "a-show", "app-window", tr("menu.show_in_app"), "↵", true, function() selectItem(it.id) end),
    menuLine(c, "a-agent", "plus", tr("menu.new_agent_in", { project = p and p.name or "" }), "n", true,
      function() actionsFor = nil; newItem(it.projectId, "agent"); render() end),
    menuLine(c, "a-term", "terminal-2", tr("menu.new_terminal_here"), "t", true,
      function() actionsFor = nil; newItem(it.projectId, "shell"); render() end),
    menuLine(c, "a-nvim", { image = model.markPath({ kind = "neovim" }) }, tr("menu.new_neovim_here"), "e", true,
      function() actionsFor = nil; newItem(it.projectId, "neovim"); render() end),
    menuLine(c, "a-jump", "arrow-big-right-lines", tr("menu.jump"), "j", waiting, function() jump() end),
    menuLine(c, "a-close", "x", tr("menu.close"), "w", true, function() closeItem(it.id, false) end),
  })
end

-- The close question, in place of the row (board 05/07).
local function confirmBlock(c, it)
  local reasonKey = CLOSE_REASONS[confirm.reason or ""] or "confirm.generic"
  local why = tr(reasonKey, {
    tool = it.toolLabel or it.tool or "",
    command = (type(it.foregroundJob) == "table" and it.foregroundJob.command) or "",
  })
  return ui.column({
    key = "confirm-" .. it.id, fill = "surface_variant", radius = 9, padding = 8, gap = 8,
    border = c.secondary, borderWidth = 2,
  }, {
    ui.row({ gap = ROW_GAP, align = "center" }, {
      tile(c, it),
      ui.label({ text = tr("confirm.question", { title = it.title }), fontSize = 13, fontWeight = "medium", color = c.title, maxLines = 1, maxWidth = LIST_W - 60 }),
    }),
    ui.label({ text = why, fontSize = 11, color = c.onSurfaceVariant, maxLines = 2, maxWidth = LIST_W - 24 }),
    ui.row({ gap = 8, justify = "end", align = "center" }, {
      ui.button({ key = "confirm-cancel", text = tr("panel.cancel"), variant = "outline", controlSize = "sm",
        onClick = function() confirm = nil; render() end }),
      ui.button({ key = "confirm-close", text = tr("confirm.close_button"), variant = "destructive", controlSize = "sm",
        onClick = confirmClose }),
    }),
  })
end

local function projectHeader(c, p)
  return ui.row({ key = "proj-" .. p.id, height = PROJECT_H, paddingH = 6, gap = 7, align = "center" }, {
    ui.label({ text = string.upper(p.name or ""), fontSize = 11, fontWeight = "semibold", color = c.project, maxLines = 1, maxWidth = 150 }),
    ui.label({ text = p.parentPath or "", fontSize = 11, color = c.path, maxLines = 1, maxWidth = LIST_W - 60 - approxWidth(p.name, 11.6), flexGrow = 1 }),
    ui.button({
      key = "proj-add-" .. p.id, glyph = "plus", glyphSize = 13, variant = "ghost", width = 22, height = 22,
      tooltip = tr("panel.project_add_tooltip", { project = p.name or "" }),
      onClick = function() newItem(p.id, "agent") end,
      onRightClick = function() openProjectMenu(p.id) end,
    }),
  })
end

-- ── list ───────────────────────────────────────────────────────────────────

local function buildList(c, s)
  local byId = model.itemsById(s)
  local children = {}
  local y = 0
  local positions = {}
  local cutAfter = reveal and reveal.itemId or nil
  local done = false
  local index = 0
  for gi, p in ipairs(s.projects or {}) do
    if done then
      break
    end
    if gi > 1 then
      table.insert(children, ui.box({ key = "gap-" .. p.id, height = GROUP_GAP, fill = TRANSPARENT }))
      y += GROUP_GAP
    end
    table.insert(children, projectHeader(c, p))
    y += PROJECT_H
    local ids = p.itemIds or {}
    if #ids == 0 and p.pinned then
      table.insert(children, ui.row({ key = "pinned-" .. p.id, height = PINNED_EMPTY_H, paddingH = 6, align = "center" }, {
        ui.label({ text = tr("panel.pinned_nothing"), fontSize = 11, color = c.onSurfaceVariant }),
      }))
      y += PINNED_EMPTY_H
    end
    for _, id in ipairs(ids) do
      local it = byId[id]
      if it ~= nil then
        index += 1
        local node
        local h = ROW_H
        if confirm ~= nil and confirm.itemId == id then
          node = confirmBlock(c, it)
          h = 112
        elseif actionsFor == id then
          node = actionsBlock(c, it)
          h = 6 * 28 + 32 + 16
        else
          node = itemRow(c, it, index)
        end
        positions[id] = { y = y, h = h }
        table.insert(children, node)
        y += h
        if cutAfter == id then
          done = true
          break
        end
      end
    end
  end
  if reveal ~= nil and reveal.pad > 0 then
    table.insert(children, ui.box({ key = "reveal-pad", height = reveal.pad, fill = TRANSPARENT }))
  end
  if reveal == nil then
    layoutY = positions
  end
  return children
end

-- Rows that need you but sit outside the visible part of the list (board 05 edge chip).
local function offscreenNeeds(s)
  local top = scrollOffset / uiScale()
  local below, above, first = 0, 0, nil
  for _, it in ipairs(visibleItems()) do
    if it.state == "needs-you" then
      local pos = layoutY[it.id]
      if pos ~= nil then
        if pos.y + pos.h > top + LIST_H then
          below += 1
          first = first or it
        elseif pos.y < top then
          above += 1
          first = first or it
        end
      end
    end
  end
  return below + above, first, below > 0
end

-- ── screens ────────────────────────────────────────────────────────────────

local function header(c, running)
  local s = snap()
  local children = {
    ui.image({ path = "assets/app-icon.svg", width = 26.67, height = 26.67 }),
    ui.column({ gap = 1, justify = "center", flexGrow = 1 }, {
      ui.label({ text = tr("app.name"), fontSize = 16, fontWeight = "semibold", color = c.title }),
      ui.label({
        text = running and model.summary(s) or tr(model.offlineKey(link)),
        fontSize = 11, color = c.onSurfaceVariant, maxLines = 1,
      }),
    }),
  }
  if running then
    local counts = model.counts(s)
    local waitingId = s.waiting and s.waiting.nextItemId
    local waitingItem = itemById(waitingId)
    local enabled = waitingItem ~= nil
    local hovered = hoverControl == "jump" and enabled
    local jumpChildren = {
      ui.glyph({ name = "arrow-big-right-lines", size = 15, color = enabled and c.onSurface or c.disabled }),
      ui.label({ text = tr("panel.jump"), fontSize = 13, fontWeight = "medium", color = enabled and c.title or c.disabled }),
    }
    if counts.need > 0 then
      table.insert(jumpChildren, ui.row({ height = 15.83, paddingH = 5, radius = 8, fill = c.primary, align = "center" }, {
        ui.label({ text = tostring(counts.need), fontSize = 10.5, fontWeight = "semibold", color = c.needText }),
      }))
    end
    table.insert(children, ui.row({
      key = "jump", height = 32, paddingH = 8, gap = 6, radius = 9, align = "center",
      fill = hovered and "surface_variant/0.35" or TRANSPARENT,
      tooltip = enabled and tr("panel.jump_tooltip", { title = waitingItem.title }) or tr("panel.nothing_waiting"),
      onClick = enabled and jump or "",
      onHover = function(state)
        hoverControl = state == "true" and "jump" or (hoverControl ~= "jump" and hoverControl or nil)
        render()
      end,
    }, jumpChildren))
    local defaultProject = projectById(model.defaultProject(s, focusId))
    table.insert(children, ui.button({
      key = "add", glyph = "plus", glyphSize = 16, variant = "ghost", width = 32, height = 32,
      tooltip = defaultProject and tr("panel.add_tooltip", { project = defaultProject.name }) or tr("menu.new_agent"),
      onClick = function()
        if defaultProject then
          newItem(defaultProject.id, "agent")
        end
      end,
      onRightClick = function()
        if defaultProject then
          openProjectMenu(defaultProject.id)
        end
      end,
    }))
    local visible = s.app and s.app.windowVisible
    table.insert(children, ui.button({
      key = "window", glyph = visible and "app-window-filled" or "app-window", glyphSize = 16, variant = "ghost",
      width = 32, height = 32,
      tooltip = visible and tr("panel.hide_tooltip") or tr("panel.show_tooltip"),
      onClick = toggleWindow,
      onRightClick = openWindowMenu,
    }))
  end
  return ui.row({ key = "header", height = HEADER_H, gap = 10, align = "center" }, children)
end

-- The hint row (or the edge chip in its place) is centred and sits on the footer's bottom
-- edge; with FOOTER_H that leaves PANEL_PAD above the hints, the same as the panel padding
-- below them. The taller chip keeps the same bottom edge, so the list never resizes.
local function footer(c, hints, rowH)
  return ui.column({ key = "footer", height = FOOTER_H, gap = 0, justify = "space_between" }, {
    ui.separator({ color = c.footerLine, thickness = 1, spacing = 0 }),
    ui.row({ height = rowH or KBD_H, gap = 14, align = "center", justify = "center" }, hints),
  })
end

local function listHints(c, s)
  local count, first, below = offscreenNeeds(s)
  if count > 0 and first ~= nil then
    local key = "edge"
    local hovered = hoverControl == key
    local hints = {
      ui.row({
        key = key, height = CHIP_H, paddingH = 8, radius = 12, gap = 7, align = "center",
        fill = hovered and c.tileLine or c.tile, border = "outline", borderWidth = 1,
        onClick = function() revealItem(first.id) end,
        onHover = function(state)
          hoverControl = state == "true" and key or (hoverControl ~= key and hoverControl or nil)
          render()
        end,
      }, {
        ui.row({ width = 14, height = 14, radius = 7, fill = c.primary, align = "center", justify = "center" }, {
          ui.label({ text = "!", fontSize = 9, fontWeight = "heavy", color = c.needText }),
        }),
        ui.label({ text = tr("panel.more_need", { n = count }), fontSize = 11, fontWeight = "medium", color = c.title }),
        ui.glyph({ name = below and "arrow-down" or "arrow-up", size = 12, color = c.onSurfaceVariant }),
      }),
    }
    return hints, CHIP_H
  end
  return {
    hint(c, "↵", tr("hint.show")),
    hint(c, "j", tr("hint.waiting")),
    hint(c, "n", tr("hint.new")),
    hint(c, "w", tr("hint.close")),
    hint(c, "1–9", tr("hint.row")),
  }
end

local function notRunningBody(c)
  local status = link.status
  local protocol = status == "protocol" or status == "incompatible"
  local canStart = ctl.canStart(link)
  local title
  if protocol then
    title = tr("panel.protocol_title")
  elseif status == "connecting" then
    title = tr("panel.connecting")
  elseif canStart then
    title = tr("panel.not_running_title")
  else
    title = tr("panel.starting")
  end
  local children = {
    ui.label({ text = title, fontSize = 14.17, fontWeight = "semibold", color = c.title, textAlign = "center" }),
    ui.label({
      text = protocol and tr("panel.protocol_body") or tr("panel.not_running_body"),
      fontSize = 11.67, color = c.onSurfaceVariant, maxWidth = 270, maxLines = 3, textAlign = "center",
    }),
  }
  if canStart then
    table.insert(children, ui.button({ key = "start", text = tr("panel.start") .. "  ↵", variant = "secondary", onClick = startApp }))
    table.insert(children, ui.label({
      text = tr("panel.start_note", { command = ctl.command() }),
      fontSize = 10, color = c.onSurfaceVariant, maxWidth = 280, maxLines = 3, textAlign = "center",
    }))
  end
  return ui.column({ key = "off", flexGrow = 1, gap = 8, align = "center", justify = "center", paddingH = 16 }, children)
end

local function emptyBody(c, s)
  local children = {}
  for gi, p in ipairs(s.projects or {}) do
    if gi > 1 then
      table.insert(children, ui.box({ key = "gap-" .. p.id, height = GROUP_GAP, fill = TRANSPARENT }))
    end
    table.insert(children, projectHeader(c, p))
    if p.pinned then
      table.insert(children, ui.row({ key = "pinned-" .. p.id, height = PINNED_EMPTY_H, paddingH = 6, align = "center" }, {
        ui.label({ text = tr("panel.pinned_nothing"), fontSize = 11, color = c.onSurfaceVariant }),
      }))
    end
  end
  table.insert(children, ui.column({ key = "empty", flexGrow = 1, gap = 8, align = "center", justify = "center", paddingH = 16 }, {
    ui.label({ text = tr("panel.empty_title"), fontSize = 14.17, fontWeight = "semibold", color = c.title }),
    ui.label({ text = tr("panel.empty_body"), fontSize = 11.67, color = c.onSurfaceVariant, maxWidth = 270, maxLines = 3, textAlign = "center" }),
    ui.row({ gap = 8, justify = "center" }, {
      ui.button({ key = "empty-new", text = tr("panel.new_agent") .. "  n", variant = "secondary", controlSize = "sm",
        onClick = function() newItem(model.defaultProject(s, nil), "agent") end }),
      ui.button({ key = "empty-palette", text = tr("panel.open_palette") .. "  o", variant = "outline", controlSize = "sm",
        onClick = function() openPalette(nil) end }),
    }),
  }))
  return ui.column({ key = "emptybody", flexGrow = 1, gap = 0 }, children)
end

-- A working badge is on screen: a working/starting row rendered as a row (not as the
-- close question or the action list) inside the scrolled viewport. Only then does the
-- arc turn (board 09), so off-screen work costs no frame ticks.
local function workingInView(s)
  local top = scrollOffset / uiScale()
  for _, it in ipairs(s.items or {}) do
    if (it.state == "working" or it.state == "starting")
      and not (confirm ~= nil and confirm.itemId == it.id) and actionsFor ~= it.id then
      local pos = layoutY[it.id]
      if pos ~= nil and pos.y + pos.h > top and pos.y < top + LIST_H then
        return true
      end
    end
  end
  return false
end

local function syncFrameTick(s)
  local want = isOpen and (reveal ~= nil or (s ~= nil and model.running(link) and workingInView(s)))
  if want ~= frameTickOn then
    frameTickOn = want
    panel.setNeedsFrameTick(want)
  end
end

render = function()
  if not isOpen then
    return
  end
  local c = theme.colors()
  local running = model.running(link)
  local s = snap()
  local body, hints, rowH
  if not running then
    body = notRunningBody(c)
    hints = ctl.canStart(link) and { hint(c, "↵", tr("hint.start")), hint(c, "Esc", tr("hint.close_panel")) }
      or { hint(c, "Esc", tr("hint.close_panel")) }
  elseif #(s.items or {}) == 0 then
    body = emptyBody(c, s)
    hints = { hint(c, "n", tr("hint.new_agent")), hint(c, "o", tr("hint.palette")), hint(c, "Esc", tr("hint.close_panel")) }
  else
    body = ui.scroll({
      key = "list", flexGrow = 1, gap = 0, scrollToBottomRev = scrollRev,
      onScroll = "onListScroll",
    }, buildList(c, s))
    hints, rowH = listHints(c, s)
  end
  panel.render(ui.column({ gap = SECTION_GAP, flexGrow = 1 }, {
    header(c, running),
    body,
    footer(c, hints, rowH),
  }))
  renderedMinute = math.floor(noctalia.nowMs() / 60000)
  syncFrameTick(s)
end

-- ── keyboard ───────────────────────────────────────────────────────────────

local function moveFocus(action)
  local list = visibleItems()
  if #list == 0 then
    return
  end
  local idx = indexOf(list, focusId)
  if idx == nil then
    -- first key: the ring starts on the item the app shows
    idx = indexOf(list, selectedId()) or 1
    if action == "home" then
      idx = 1
    elseif action == "end" then
      idx = #list
    end
  elseif action == "up" then
    idx = math.max(1, idx - 1)
  elseif action == "down" then
    idx = math.min(#list, idx + 1)
  elseif action == "home" then
    idx = 1
  elseif action == "end" then
    idx = #list
  end
  focusId = list[idx].id
  confirm = nil
  actionsFor = nil
  render()
  revealItem(focusId)
end

local function focusedOrSelected()
  return itemById(focusId) or itemById(selectedId())
end

function onKey(chord, pressed)
  if not pressed then
    return
  end
  local running = model.running(link)
  if not running then
    if chord == "Return" or chord == "KP_Enter" then
      if link.status == "not_running" then
        startApp()
      end
    end
    return
  end
  local s = snap()
  local digit = tonumber(chord)
  if digit ~= nil then
    local list = visibleItems()
    if list[digit] ~= nil then
      selectItem(list[digit].id)
    end
    return
  end
  local action = KEY_ACTIONS[chord]
  if action == nil then
    return
  end
  if confirm ~= nil then
    if action == "close" or action == "enter" then
      confirmClose()
      return
    elseif action == "up" or action == "down" then
      confirm = nil
      render()
      return
    end
  end
  if action == "up" or action == "down" or action == "home" or action == "end" then
    moveFocus(action)
  elseif action == "enter" then
    if focusId ~= nil and itemById(focusId) ~= nil then
      selectItem(focusId)
    end
  elseif action == "jump" then
    jump()
  elseif action == "new_agent" or action == "new_terminal" or action == "new_neovim" then
    local kind = action == "new_agent" and "agent" or (action == "new_terminal" and "shell" or "neovim")
    actionsFor = nil
    newItem(model.defaultProject(s, focusId), kind)
    render()
  elseif action == "close" then
    local it = itemById(focusId)
    if it ~= nil then
      actionsFor = nil
      closeItem(it.id, false)
    end
  elseif action == "palette" then
    local it = focusedOrSelected()
    openPalette(it and it.projectId or nil)
  elseif action == "window" then
    toggleWindow()
  end
end

-- ── lifecycle ──────────────────────────────────────────────────────────────

function onListScroll(offset)
  local value = tonumber(offset) or 0
  if math.abs(value - scrollOffset) < 0.5 then
    return
  end
  scrollOffset = value
  render() -- the edge chip depends on what is in view
end

function onFrameTick(deltaMs)
  local s = snap()
  if reveal ~= nil then
    reveal.frames += 1
    if reveal.frames >= 2 then
      reveal = nil
      render()
      return
    end
  end
  if s ~= nil and workingInView(s) then
    arcAccum += tonumber(deltaMs) or 16
    if arcAccum >= ARC_STEP_MS then
      arcAccum = arcAccum % ARC_STEP_MS
      arcFrame = (arcFrame + 1) % assets.ARC_FRAMES
      render()
    end
  else
    syncFrameTick(s)
  end
end

function onOpen(context)
  isOpen = true
  hoverId = nil
  hoverControl = nil
  confirm = nil
  actionsFor = nil
  scrollOffset = 0
  reveal = nil
  frameTickOn = false
  link = model.link()
  -- `noctalia msg panel-toggle muty/ultra9000:panel keys`: show the ring at once (a
  -- keybind open); a click open shows no ring until the first key (board 07).
  focusId = (context == "keys") and selectedId() or nil
  panel.setWantsSecondTicks(true)
  render()
end

function onClose()
  isOpen = false
  frameTickOn = false
  panel.setNeedsFrameTick(false)
  panel.setWantsSecondTicks(false)
end

-- Second ticks only matter for ages: re-render on the minute boundary.
function update()
  if isOpen and math.floor(noctalia.nowMs() / 60000) ~= renderedMinute then
    render()
  end
end

noctalia.state.watch("link", function(value)
  -- the old visible order, so a vanished focused row hands the ring to its neighbour
  local before = visibleItems()
  link = type(value) == "table" and value or { status = "not_running" }
  if confirm ~= nil and itemById(confirm.itemId) == nil then
    confirm = nil
  end
  if actionsFor ~= nil and itemById(actionsFor) == nil then
    actionsFor = nil
  end
  if focusId ~= nil and itemById(focusId) == nil then
    local idx = indexOf(before, focusId)
    local nextFocus = nil
    if idx ~= nil then
      for i = idx + 1, #before do
        if itemById(before[i].id) ~= nil then
          nextFocus = before[i].id
          break
        end
      end
      if nextFocus == nil then
        for i = idx - 1, 1, -1 do
          if itemById(before[i].id) ~= nil then
            nextFocus = before[i].id
            break
          end
        end
      end
    end
    focusId = nextFocus
  end
  render()
end)

noctalia.setUpdateInterval(60000)
