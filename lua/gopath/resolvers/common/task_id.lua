---@module 'gopath.resolvers.common.task_id'
---@brief A task id under the cursor (`<area>/<slug>`), resolved to the task file through tasks.nvim.
---@description
--- A to-do list, a commit message or a handover names tasks by id. `gF` on one opens the task file: the open task in
--- `ROADMAP/tasks/`, or the finished one in `Backlog/`.
---
--- **All the knowledge is tasks.nvim's.** What an id looks like, where a vault is, which areas exist and where an open
--- or a finished task lives is answered by `tasks_nvim.resolve`; this module only turns its targets into a
--- `GopathResult`. That is also what keeps it from misreading a path: `lua/gopath` in `lua/gopath/init.lua` is not
--- an id there (a second `/`), and `docs/api` is not one either unless a vault has an area `docs` with that task.
---
--- **A soft dependency.** Without tasks.nvim (`pcall(require, "tasks_nvim.resolve")` fails) the resolver answers
--- nil, says nothing and costs one failed `require`, once. With `tasks.enable = false` it is not asked at all.
---
--- **Several targets are offered, not guessed.** The same id can name an open and a finished task (after a reopen),
--- or a task in two of `tasks.vaults`. The result then carries `alternatives`, one `GopathResult` per target, and
--- `gopath.commands` asks which one to open (`M.pick`).

local C = require("gopath.config")

local M = {}

---@type table|nil  tasks.nvim's resolver, once found
local _resolver = nil
---@type string|nil  the 'runtimepath' the last failed `require` looked through
local _missing_rtp = nil

---tasks.nvim's resolver, or nil.
---
---A miss is remembered only for the 'runtimepath' it was looked for in: a
---failed `require` walks the whole path, and hover.nvim asks on every pause of
---the cursor. A plugin that is added later (`packadd`, a lazy load on a
---command) changes 'runtimepath', so it is found on the next lookup rather
---than after a restart.
---@return table|nil
local function resolver()
  if _resolver then return _resolver end
  local rtp = vim.o.runtimepath
  if _missing_rtp == rtp and not package.loaded["tasks_nvim.resolve"] then return nil end
  local ok, mod = pcall(require, "tasks_nvim.resolve")
  if ok and type(mod) == "table" and type(mod.resolve_at) == "function" then
    _resolver, _missing_rtp = mod, nil
    return mod
  end
  _missing_rtp = rtp
  return nil
end

---`tasks.vaults` with `~` and environment variables expanded: tasks.nvim takes
---each entry as a path as written, and an unexpanded one names no directory.
---@param vaults any
---@return string[]|nil
local function expand_vaults(vaults)
  if type(vaults) ~= "table" then return nil end
  local out = {}
  for _, v in ipairs(vaults) do
    if type(v) == "string" and v ~= "" then out[#out + 1] = vim.fs.normalize(v) end
  end
  return out
end

---@param target table  a `Tasks.ResolveTarget`
---@return GopathResult
local function result_of(target)
  return {
    kind = "file",
    path = (target.path or ""):gsub("\\", "/"),
    language = vim.bo.filetype or "text",
    range = { line = target.line or 1, col = 1 },
    chain = nil,
    source = "tasks",
    confidence = 0.95,
    exists = true,
    task = { id = target.id, kind = target.kind, title = target.title, root = target.root },
  }
end

---The task id under the cursor as a result, or nil (no id there, an id no vault knows, tasks.nvim missing, the
---feature off). With several targets the first is the result and `alternatives` lists all of them.
---@return GopathResult|nil
function M.resolve()
  local cfg = C.get().tasks
  if cfg == false or (type(cfg) == "table" and cfg.enable == false) then return nil end
  local mod = resolver()
  if not mod then return nil end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local roots = type(cfg) == "table" and expand_vaults(cfg.vaults) or nil
  local ok, targets = pcall(mod.resolve_at, 0, row, col, { roots = roots })
  if not ok or type(targets) ~= "table" or #targets == 0 then return nil end
  local first = result_of(targets[1])
  if #targets > 1 then
    local all = {}
    for i, t in ipairs(targets) do
      all[i] = result_of(t)
    end
    first.alternatives = all
  end
  return first
end

---@param res GopathResult
---@return string
local function label(res)
  local t = res.task or {}
  local where = t.kind == "done" and "finished" or "open"
  return ("%s  %s (%s)  %s"):format(t.id or "?", t.title or "", where, t.root or "")
end

---Ask which of `res.alternatives` to open; `on_choice(nil)` when the picker is dismissed.
---@param res GopathResult
---@param on_choice fun(choice: GopathResult|nil)
---@return nil
function M.pick(res, on_choice)
  local items = res.alternatives or { res }
  local ok_kit, kit = pcall(require, "ui.kit")
  if ok_kit and type(kit.select) == "function" then
    kit.select({
      items = items,
      title = "gopath: task id in several places — pick one",
      format_item = label,
      on_select = on_choice,
      on_cancel = function()
        on_choice(nil)
      end,
    })
    return
  end
  vim.ui.select(
    items,
    { prompt = "gopath: task id in several places — pick one", format_item = label },
    on_choice
  )
end

---Forget whether tasks.nvim was found. For the specs.
---@return nil
function M._reset()
  _resolver, _missing_rtp = nil, nil
end

---Whether task ids can resolve, and why not when they cannot: for `:checkhealth`.
---@return boolean ok
---@return string message
function M.status()
  local cfg = C.get().tasks
  if cfg == false or (type(cfg) == "table" and cfg.enable == false) then
    return false, "task ids are not resolved (tasks = false / tasks.enable = false)"
  end
  if not resolver() then
    return false,
      "tasks.nvim not installed (or too old for tasks_nvim.resolve) — task ids are read as paths"
  end
  local vaults = type(cfg) == "table" and expand_vaults(cfg.vaults) or nil
  if vaults and #vaults > 0 then
    local missing = {}
    for _, v in ipairs(vaults) do
      if vim.fn.isdirectory(v) ~= 1 then missing[#missing + 1] = v end
    end
    if #missing == #vaults then
      return false, "none of tasks.vaults is a directory: " .. table.concat(missing, ", ")
    end
    if #missing > 0 then
      return true,
        "task ids resolve; these tasks.vaults are no directory: " .. table.concat(missing, ", ")
    end
    return true,
      "gF on a task id (<area>/<slug>) opens the task file, in " .. #vaults .. " vault(s)"
  end
  local ok_vault, vault = pcall(require, "tasks_nvim.vault")
  local root = ok_vault and type(vault.root) == "function" and vault.root() or nil
  if not root then
    return false,
      "tasks.nvim has no vault (no setup({ vault = ... }), no $TASKS_VAULT) and tasks.vaults is empty — nothing to resolve against"
  end
  return true, "gF on a task id (<area>/<slug>) opens the task file, in " .. root
end

return M
