--!nonstrict
-- [[launcher_provider]] u9 (prefix /u9): live items by title, project or tool → select it
-- and show the window; "New agent / terminal / Neovim in <project>" → new item; when the
-- app isn't running, one result: Start Ultra 9000. Results keep the app's sidebar order
-- (score only ranks matches; ties fall back to snapshot order).

local model = require("./lib/model.luau")
local ctl = require("./lib/ctl.luau")

local tr = noctalia.tr

local KINDS = {
  { kind = "agent", key = "launcher.new_agent", glyph = "plus" },
  { kind = "shell", key = "launcher.new_terminal", glyph = "terminal-2" },
  { kind = "neovim", key = "launcher.new_neovim", glyph = "code" }, -- v5.2.1's Tabler set has no vim glyph
}

local function match(query, text)
  if query == "" then
    return 0
  end
  return noctalia.fuzzyScore(query, text)
end

function onQuery(text)
  local query = noctalia.string.trim(text or "")
  local link = model.link()
  if not model.running(link) then
    if ctl.canStart(link) then
      launcher.setResults(text, {
        { id = "start", title = tr("panel.start"), subtitle = tr("launcher.start_subtitle", { command = ctl.command() }), glyph = "player-play" },
      })
    else
      local status = link.status
      local title = (status == "protocol" or status == "incompatible") and tr("launcher.protocol") or tr("launcher.starting")
      launcher.setResults(text, { { id = "none", title = title, glyph = "robot" } })
    end
    return
  end
  local s = link.snapshot
  local projects = model.projectsById(s)
  local now = noctalia.nowMs()
  local results = {}
  local order = 0
  for _, p in ipairs(s.projects or {}) do
    for _, id in ipairs(p.itemIds or {}) do
      local it = model.itemsById(s)[id]
      if it ~= nil then
        local hay = table.concat({ it.title or "", p.name or "", it.toolLabel or "", it.tool or "" }, " ")
        local score = match(query, hay)
        if score ~= nil then
          order += 1
          local pill = model.pill(it, now)
          local sub = { p.name or "", model.subline(it, now) }
          if pill ~= nil then
            table.insert(sub, pill.text)
          end
          table.insert(results, {
            id = "item:" .. it.id,
            title = it.title,
            subtitle = table.concat(sub, " · "),
            badge = it.toolGlyph or "•",
            score = 2000 + score - order / 1000,
          })
        end
      end
    end
  end
  for pi, p in ipairs(s.projects or {}) do
    for ki, k in ipairs(KINDS) do
      local title = tr(k.key, { project = p.name or "" })
      local score = match(query, title)
      if score ~= nil then
        table.insert(results, {
          id = "new:" .. k.kind .. ":" .. p.id,
          title = title,
          subtitle = projects[p.id] and projects[p.id].parentPath or "",
          glyph = k.glyph,
          score = 1000 + score - (pi * 3 + ki) / 1000,
        })
      end
    end
  end
  launcher.setResults(text, results)
end

function onActivate(id)
  if id == "start" then
    ctl.start()
    return
  end
  local itemId = string.match(id, "^item:(.+)$")
  if itemId ~= nil then
    ctl.send("select_item", { itemId = itemId, show = true })
    return
  end
  local kind, projectId = string.match(id, "^new:(%a+):(.+)$")
  if kind ~= nil then
    ctl.send("new_item", { projectId = projectId, kind = kind })
  end
end
