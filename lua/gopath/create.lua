---@module 'gopath.create'
---@brief Offer to create a resolved-but-missing file, then hand it back to the caller.
---@description
--- Used by `gopath.open` (passive: gP/g|/g\/g}, honors `create_on_missing.enable`)
--- and by the dedicated `check` keymap/command (explicit user action, always offers
--- regardless of `create_on_missing.enable`; see `gopath.commands.check_under_cursor`).
---
--- A directory can't be opened in an editor buffer the way a file can, so when the
--- unresolved path has an existing ancestor directory, the confirm dialog offers a
--- second choice — "Open in filetree" — that hands the directory to filetree.nvim
--- (soft dependency; the button is only shown when it is installed and set up)
--- instead of silently `:edit`-ing the directory (which used to dump you into
--- netrw with no warning).
---
--- The confirm dialog itself prefers lib.nvim's `ui.kit.confirm` (declared
--- dependency, same soft-fallback convention as `gopath.util.cross` /
--- `gopath.util.log`); when lib.nvim is missing it falls back to `vim.ui.select`.

local LOG   = require("gopath.util.log")
local CROSS = require("gopath.util.cross")

local M = {}

local uv = vim.uv or vim.loop

---@type fun(parent_dir: string, name: string): boolean, ("file"|"directory")?, string?
---the lib.nvim.fs.create_entry function, or nil when lib.nvim is unavailable
local create_entry
do
  local ok, mod = pcall(require, "lib.nvim.fs.create_entry")
  if ok then
    create_entry = mod
  else
    vim.schedule(function()
      LOG.warn(
        "optional dependency 'lib.nvim' not found — using a built-in "
          .. "mkdir+open fallback for file creation."
      )
    end)
  end
end

-- ── File creation ────────────────────────────────────────────────────────────

---Create empty file at `path`, creating parent directories as needed.
---@param path string
---@return boolean ok
---@return string|nil err
local function touch(path)
  local native = CROSS.to_native(path)

  if create_entry then
    local dir = vim.fn.fnamemodify(native, ":h")
    local name = vim.fn.fnamemodify(native, ":t")
    local ok, _, path_or_err = create_entry(dir, name)
    if not ok then
      return false, path_or_err
    end
    return true, nil
  end

  local dir = vim.fn.fnamemodify(native, ":h")
  if dir ~= "" and dir ~= "." then
    local ok_mkdir = pcall(vim.fn.mkdir, dir, "p")
    if not ok_mkdir then
      return false, "mkdir failed: " .. dir
    end
  end
  local f, err = io.open(native, "w")
  if not f then
    return false, err or ("could not open " .. native)
  end
  f:close()
  return true, nil
end

-- ── Nearest existing ancestor directory ──────────────────────────────────────

---Find the nearest existing ancestor directory of `path` (walking from the
---full path up to its root segment). Pure query — does not open anything.
---@param path string
---@return string|nil dir  absolute, normalized
local function find_nearest_existing_dir(path)
  if not path or path == "" then return nil end
  local norm = (vim.fs.normalize and vim.fs.normalize(path)) or path
  local segs = {}
  for s in norm:gmatch("[^/\\]+") do segs[#segs + 1] = s end

  for i = #segs, 1, -1 do
    local candidate = table.concat(segs, "/", 1, i)
    local cwd = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
    local try_paths = { candidate, "/" .. candidate, cwd .. "/" .. candidate }

    for _, p in ipairs(try_paths) do
      local ok_norm, pn = pcall(vim.fs.normalize, p)
      if ok_norm then
        local st = uv.fs_stat(pn)
        if st and st.type == "directory" then
          return pn
        end
      end
    end
  end
  return nil
end

-- ── filetree.nvim (soft dependency) ──────────────────────────────────────────

---Return the active filetree.nvim adapter when the plugin is installed and
---has completed setup(), else nil. Never throws.
---@return table|nil
local function filetree_adapter()
  local ok, filetree = pcall(require, "filetree")
  if not ok or type(filetree) ~= "table" or not filetree.is_initialized() then
    return nil
  end
  local ok_adapter, adapter = pcall(filetree.adapter)
  if not ok_adapter or type(adapter) ~= "table" then
    return nil
  end
  return adapter
end

---Set cwd to `dir` and hand it to filetree.nvim's tree (rooted + focused there).
---@param dir string
local function open_in_filetree(dir)
  local adapter = filetree_adapter()
  if not adapter then
    LOG.warn("filetree.nvim not available — could not open: " .. dir)
    return
  end
  local ok_cd = pcall(vim.cmd.cd, vim.fn.fnameescape(dir))
  if not ok_cd then
    LOG.warn("Could not set cwd to: " .. dir)
  end
  local opened = false
  if type(adapter.toggle_at) == "function" then
    opened = adapter.toggle_at("left", { dir = dir }) and true or false
  end
  if not opened and type(adapter.set_root) == "function" then
    opened = adapter.set_root(dir) and true or false
  end
  if opened then
    LOG.info("Opened in filetree: " .. dir)
  else
    LOG.error("Could not open in filetree: " .. dir)
  end
end

-- ── Confirm dialog (lib.nvim.ui.kit, soft dependency) ────────────────────────

---@type table|nil  lib.nvim.ui.kit module, or nil when unavailable
local kit
do
  local ok, mod = pcall(require, "lib.nvim.ui.kit")
  if ok and type(mod) == "table" and type(mod.confirm) == "function" then
    kit = mod
  else
    kit = nil
    vim.schedule(function()
      LOG.debug(
        "optional dependency 'lib.nvim' not found — using vim.ui.select "
          .. "fallback for the create-on-missing prompt. Add it to your plugin "
          .. "spec (dependencies = { 'StefanBartl/lib.nvim' }) for the themed dialog."
      )
    end)
  end
end

---Ask the user to pick one of `choices` (button dialog via lib.nvim, or
---vim.ui.select when lib.nvim is unavailable).
---@param question string
---@param choices string[]
---@param on_choice fun(choice: string|nil)  nil = cancelled
local function ask(question, choices, on_choice)
  if kit then
    kit.confirm({
      question  = question,
      choices   = choices,
      on_answer = on_choice,
    })
    return
  end
  vim.ui.select(choices, { prompt = question }, function(choice)
    on_choice(choice)
  end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

local CREATE = "Create file"
local FILETREE = "Open in filetree"
local CANCEL = "Cancel"

---Offer to create `res.path` when it does not exist.
---On "Create file": creates the file (+ parent dirs), marks `res.exists = true`
---and calls `on_created(res)` so the caller can open/jump into it.
---On "Open in filetree" (only offered when a nearest existing ancestor
---directory was found and filetree.nvim is installed + set up): hands that
---directory to filetree.nvim and sets it as cwd; `on_created` is not called.
---On decline / cancel / failure: notifies and does not call `on_created`.
---@param res GopathResult
---@param on_created fun(res: GopathResult)
---@param opts { force?: boolean }|nil  force=true bypasses `create_on_missing.enable`
--- (use for explicit user actions like the `check` keymap)
function M.offer(res, on_created, opts)
  opts = opts or {}
  local cfg = require("gopath.config").get().create_on_missing or {}
  if cfg.enable == false and not opts.force then
    LOG.error("File not found: " .. tostring(res.path))
    return
  end

  if cfg.confirm == false then
    -- Silent mode: skip the dialog and create directly.
    local ok, err = touch(res.path)
    if not ok then
      LOG.error("Could not create file: " .. tostring(err))
      return
    end
    res.exists = true
    LOG.info("Created: " .. tostring(res.path))
    on_created(res)
    return
  end

  local nearest_dir = find_nearest_existing_dir(res.path)
  local choices = { CREATE }
  if nearest_dir and filetree_adapter() then
    choices[#choices + 1] = FILETREE
  end
  choices[#choices + 1] = CANCEL

  ask("gopath: '" .. tostring(res.path) .. "' not found", choices, function(choice)
    if choice == CREATE then
      local ok, err = touch(res.path)
      if not ok then
        LOG.error("Could not create file: " .. tostring(err))
        return
      end
      res.exists = true
      LOG.info("Created: " .. tostring(res.path))
      on_created(res)
    elseif choice == FILETREE and nearest_dir then
      open_in_filetree(nearest_dir)
    else
      LOG.warn("File not created: " .. tostring(res.path))
    end
  end)
end

return M
