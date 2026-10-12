--!nonstrict
-- Read-only helpers over the app's snapshot (contract v1). The plugin never infers or
-- reorders anything: projects/items are rendered in snapshot order, "waiting" is the
-- app's own waiting.nextItemId, and every count below is a plain tally of item states.

local M = {}
local ctl = require("./ctl.luau")

local tr = noctalia.tr

-- The service publishes one value: { status, snapshot, command, at }.
-- status: "not_running" | "connecting" | "connected" | "protocol"
function M.link()
  local link = noctalia.state.get("link")
  if type(link) ~= "table" then
    return { status = "not_running" }
  end
  return link
end

-- Translation key for the app's state while there is no snapshot to show.
function M.offlineKey(link)
  local status = link and link.status
  if status == "protocol" or status == "incompatible" then
    return "tooltip.protocol"
  elseif status == "starting" then
    return "tooltip.starting"
  elseif status == "connecting" then
    return "tooltip.connecting"
  end
  return "tooltip.not_running"
end

-- Connected, or reconnecting with the last snapshot still on screen.
function M.running(link)
  return (link.status == "connected" or link.status == "connecting") and type(link.snapshot) == "table"
end

function M.itemsById(snap)
  local out = {}
  for _, it in ipairs(snap.items or {}) do
    out[it.id] = it
  end
  return out
end

function M.projectsById(snap)
  local out = {}
  for _, p in ipairs(snap.projects or {}) do
    out[p.id] = p
  end
  return out
end

local function isBusyShell(it)
  return it.kind ~= "agent" and type(it.foregroundJob) == "table"
end
M.isBusyShell = isBusyShell

-- Bar segments (board 02), in the fixed order needs you · error · working · on job,
-- plus the unread flag. Busy shells, exited items and seen turns never count.
function M.counts(snap)
  local c = { need = 0, err = 0, work = 0, onjob = 0, unread = 0, seen = 0, busy = 0, live = 0, jobs = 0 }
  for _, it in ipairs(snap.items or {}) do
    c.live += 1
    local s = it.state
    if s == "needs-you" then
      c.need += 1
    elseif s == "error" then
      c.err += 1
    elseif s == "working" then
      c.work += 1
    elseif s == "on-job" then
      c.onjob += 1
      c.jobs += math.max(1, #(it.jobs or {}))
    elseif s == "your-turn" then
      if it.unread then
        c.unread += 1
      else
        c.seen += 1
      end
    end
    if isBusyShell(it) then
      c.busy += 1
    end
  end
  return c
end

function M.projectsWithItems(snap)
  local n = 0
  for _, p in ipairs(snap.projects or {}) do
    if #(p.itemIds or {}) > 0 then
      n += 1
    end
  end
  return n
end

-- "<1m", "4m", "2h", "3d" — no seconds (the app's age format).
function M.age(sinceMs, nowMs)
  if type(sinceMs) ~= "number" or sinceMs <= 0 then
    return ""
  end
  local mins = math.floor(math.max(0, nowMs - sinceMs) / 60000)
  if mins < 1 then
    return tr("age.now")
  elseif mins < 60 then
    return tr("age.minutes", { n = mins })
  elseif mins < 24 * 60 then
    return tr("age.hours", { n = math.floor(mins / 60) })
  end
  return tr("age.days", { n = math.floor(mins / 1440) })
end

local function earliestJob(it)
  local t = nil
  for _, job in ipairs(it.jobs or {}) do
    if type(job.startedAtMs) == "number" and job.startedAtMs > 0 and (t == nil or job.startedAtMs < t) then
      t = job.startedAtMs
    end
  end
  return t or it.stateSinceMs
end

local home = noctalia.getenv("HOME") or ""

function M.tildePath(path)
  if type(path) ~= "string" then
    return ""
  end
  if home ~= "" and string.sub(path, 1, #home) == home then
    return "~" .. string.sub(path, #home + 1)
  end
  return path
end

-- Pill (board 05/08): { kind, text } or nil. kind selects the colours.
function M.pill(it, nowMs)
  local s = it.state
  if s == "working" then
    return { kind = "work", text = tr("pill.working") }
  elseif s == "starting" then
    return { kind = "work", text = tr("pill.starting") }
  elseif s == "on-job" then
    local n = #(it.jobs or {})
    local age = M.age(earliestJob(it), nowMs)
    if n > 1 then
      return { kind = "onjob", text = tr("pill.on_jobs", { n = n, age = age }) }
    end
    return { kind = "onjob", text = tr("pill.on_job", { age = age }) }
  elseif s == "needs-you" then
    return { kind = "need", text = tr("pill.needs_you") }
  elseif s == "your-turn" then
    return { kind = it.unread and "turn" or "seen", text = tr("pill.your_turn") }
  elseif s == "error" then
    return { kind = "err", text = tr("pill.error") }
  elseif s == "exited" then
    return { kind = "exit", text = tr("pill.exited") }
  end
  if isBusyShell(it) then
    return { kind = "cmd", text = tostring(it.foregroundJob.command or "") }
  end
  return nil
end

-- Badge shape next to the title (board 03): need | err | work | onjob | exit | busy | nil.
function M.badge(it)
  local s = it.state
  if s == "needs-you" then
    return "need"
  elseif s == "error" then
    return "err"
  elseif s == "working" or s == "starting" then
    return "work"
  elseif s == "on-job" then
    return "onjob"
  elseif s == "exited" then
    return "exit"
  elseif isBusyShell(it) then
    return "busy"
  end
  return nil
end

-- Sub line (board 05): "OMP · opus 5.5 · 4m", "Shell · ~/code/harbor · 2m",
-- "OMP · kimi-k3 · bench, lint", "Codex · gpt-6.1 · exit 2 · 5m", "Neovim · ~/dir".
function M.subline(it, nowMs)
  local parts = { it.toolLabel or it.tool or "" }
  local s = it.state
  if it.kind ~= "agent" then
    if s == "exited" or s == "error" then
      if type(it.exitCode) == "number" then
        table.insert(parts, tr("sub.exit", { code = it.exitCode }))
      end
      table.insert(parts, M.age(it.stateSinceMs, nowMs))
    else
      table.insert(parts, M.tildePath(it.cwd))
      if isBusyShell(it) then
        table.insert(parts, M.age(it.foregroundJob.sinceMs, nowMs))
      end
    end
  else
    if type(it.model) == "string" and it.model ~= "" then
      table.insert(parts, it.model)
    end
    if s == "on-job" and #(it.jobs or {}) > 0 then
      local labels = {}
      for _, job in ipairs(it.jobs) do
        table.insert(labels, tostring(job.label or job.kind or ""))
      end
      table.insert(parts, table.concat(labels, ", "))
    else
      if (s == "error" or s == "exited") and type(it.exitCode) == "number" then
        table.insert(parts, tr("sub.exit", { code = it.exitCode }))
      end
      if s ~= "unknown" then
        table.insert(parts, M.age(it.stateSinceMs, nowMs))
      end
    end
  end
  local out = {}
  for _, p in ipairs(parts) do
    if p ~= "" then
      table.insert(out, p)
    end
  end
  return table.concat(out, " · ")
end

-- Summary under the panel title: "9 live · 3 projects".
function M.summary(snap)
  local c = M.counts(snap)
  if c.live == 0 then
    return tr("panel.nothing_running")
  end
  local projects = M.projectsWithItems(snap)
  return tr(projects == 1 and "panel.summary_one" or "panel.summary", { live = c.live, projects = projects })
end

-- The project an action without an explicit target goes to: the given item's, else
-- the item the app shows, else the first pinned project, else the first project.
function M.defaultProject(snap, itemId)
  local items = M.itemsById(snap)
  if itemId ~= nil and items[itemId] ~= nil then
    return items[itemId].projectId
  end
  for _, it in ipairs(snap.items or {}) do
    if it.selected then
      return it.projectId
    end
  end
  for _, p in ipairs(snap.projects or {}) do
    if p.pinned then
      return p.id
    end
  end
  local first = (snap.projects or {})[1]
  return first and first.id or nil
end

local function names(list, limit)
  local shown = {}
  for i = 1, math.min(limit, #list) do
    table.insert(shown, list[i].title)
  end
  local text = table.concat(shown, ", ")
  if #list > limit then
    text = text .. " " .. tr("tooltip.more", { n = #list - limit })
  end
  return text
end

-- Tooltip rows (board 04) for barWidget.setTooltip: Noctalia v5.2.1 tooltips are
-- key/value rows (key in `secondary`, value right-aligned, ellipsized), so the title and
-- the click hint become rows too.
function M.tooltipRows(link, nowMs)
  if not M.running(link) then
    local rows = { { key = tr("app.name"), value = tr(M.offlineKey(link)) } }
    if link.status ~= "protocol" and link.status ~= "incompatible" then
      table.insert(rows, { key = "", value = tr("tooltip.kept") })
    end
    if ctl.canStart(link) then
      table.insert(rows, { key = tr("tooltip.middle"), value = tr("tooltip.start") })
    end
    return rows
  end
  local snap = link.snapshot
  local projects = M.projectsById(snap)
  local items = M.itemsById(snap)
  local c = M.counts(snap)
  local live = c.live
  local nProjects = M.projectsWithItems(snap)
  local title = nProjects >= 4 and tr("tooltip.live_in", { n = live, p = nProjects }) or tr("tooltip.live", { n = live })
  local rows = { { key = tr("app.name"), value = title } }

  local by = { need = {}, err = {}, work = {}, onjob = {}, busy = {} }
  for _, it in ipairs(snap.items or {}) do
    if it.state == "needs-you" then
      table.insert(by.need, it)
    elseif it.state == "error" then
      table.insert(by.err, it)
    elseif it.state == "working" then
      table.insert(by.work, it)
    elseif it.state == "on-job" then
      table.insert(by.onjob, it)
    end
    if isBusyShell(it) then
      table.insert(by.busy, it)
    end
  end
  local function projectName(it)
    local p = projects[it.projectId]
    return p and p.name or ""
  end

  if #by.need == 1 then
    local it = by.need[1]
    local word = it.attention == "question" and tr("tooltip.question") or tr("tooltip.needs_you")
    rows[#rows + 1] = { key = word, value = table.concat({ it.title, projectName(it), M.age(it.stateSinceMs, nowMs) }, " · ") }
  elseif #by.need > 1 then
    rows[#rows + 1] = { key = tr("tooltip.needs_you"), value = names(by.need, 2) }
  end
  if #by.err == 1 then
    local it = by.err[1]
    local parts = { it.title }
    if type(it.exitCode) == "number" then
      table.insert(parts, tr("sub.exit", { code = it.exitCode }))
    end
    table.insert(parts, M.age(it.stateSinceMs, nowMs))
    rows[#rows + 1] = { key = tr("tooltip.error"), value = table.concat(parts, " · ") }
  elseif #by.err > 1 then
    rows[#rows + 1] = { key = tr("tooltip.error"), value = names(by.err, 2) }
  end
  local nameBusy = live < 10
  if #by.work > 0 then
    rows[#rows + 1] = {
      key = tr("tooltip.working"),
      value = (#by.work <= 2 and nameBusy) and names(by.work, 2) or tostring(#by.work),
    }
  end
  if #by.onjob == 1 and nameBusy then
    local it = by.onjob[1]
    local n = math.max(1, #(it.jobs or {}))
    rows[#rows + 1] = {
      key = tr("tooltip.on_job"),
      value = table.concat({ it.title, tr("tooltip.jobs", { n = n }), M.age(earliestJob(it), nowMs) }, " · "),
    }
  elseif #by.onjob > 0 then
    rows[#rows + 1] = {
      key = tr("tooltip.on_job"),
      value = (#by.onjob <= 2 and nameBusy) and names(by.onjob, 2)
        or (tostring(#by.onjob) .. " · " .. tr("tooltip.jobs", { n = c.jobs })),
    }
  end
  if c.unread + c.seen > 0 then
    local parts = {}
    if c.unread > 0 then
      table.insert(parts, tr("tooltip.unread", { n = c.unread }))
    end
    if c.seen > 0 then
      table.insert(parts, tr("tooltip.seen", { n = c.seen }))
    end
    rows[#rows + 1] = { key = tr("tooltip.your_turn"), value = table.concat(parts, " · ") }
  end
  if #by.busy == 1 then
    local it = by.busy[1]
    rows[#rows + 1] = {
      key = tr("tooltip.shells"),
      value = tr("tooltip.shell_in", { cmd = it.foregroundJob.command, project = projectName(it) })
        .. " · " .. M.age(it.foregroundJob.sinceMs, nowMs),
    }
  elseif #by.busy > 1 then
    rows[#rows + 1] = { key = tr("tooltip.shells"), value = tr("tooltip.busy", { n = #by.busy }) }
  end

  local nextId = snap.waiting and snap.waiting.nextItemId
  if nextId ~= nil and items[nextId] ~= nil then
    rows[#rows + 1] = { key = tr("tooltip.middle"), value = tr("tooltip.jump_to", { title = items[nextId].title }) }
  else
    local visible = snap.app and snap.app.windowVisible
    rows[#rows + 1] = { key = tr("tooltip.middle"), value = visible and tr("tooltip.hide") or tr("tooltip.show") }
  end
  return rows
end

-- Tool mark asset (brand-fixed, assets/marks/<tool>.svg) or nil for custom tools.
local MARKS = { omp = true, claude = true, codex = true, pi = true, shell = true, neovim = true }
function M.markPath(it)
  local tool = it.tool
  if tool == nil or not MARKS[tool] then
    if it.kind == "shell" then
      tool = "shell"
    elseif it.kind == "neovim" then
      tool = "neovim"
    else
      return nil
    end
  end
  return "assets/marks/" .. tool .. ".svg"
end

return M
