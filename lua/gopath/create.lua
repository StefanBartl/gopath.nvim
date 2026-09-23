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
--- The confirm dialog itself prefers ui.nvim's `ui.kit.confirm` (declared
--- dependency, same soft-fallback convention as `gopath.util.cross` /
--- `gopath.util.log`); when ui.nvim is missing it falls back to `vim.ui.select`.

local LOG = require("gopath.util.log")
local CROSS = require("gopath.util.cross")
local PATH = require("gopath.util.path")
local FILETREE_UTIL = require("gopath.util.filetree")

local M = {}

local uv = vim.uv or vim.loop

---@type fun(parent_dir: string, name: string): boolean, ("file"|"directory")?, string?
---the lib.nvim.fs.create_entry function, or nil when this lib.nvim checkout
---predates it
local create_entry

---@type fun(path: string, content: string): boolean, string?
---the lib.nvim.fs.write.to_file function, used when `create_entry` is
---missing from an older lib.nvim checkout; nil only when lib.nvim itself (or
---both of these submodules) is unavailable
local write_to_file

-- lib.nvim is gopath's hard dependency (see bindings/keymaps.lua) -- if it
-- were genuinely absent, setup() would already have failed before this
-- module is ever reached. What CAN legitimately be missing is a single
-- submodule on an older checkout (LUA-05): `fs.create_entry` is preferred,
-- `fs.write.to_file` is the fallback for a checkout that predates it, and
-- only a checkout missing *both* leaves file creation unavailable.
do
  local ok, mod = pcall(require, "lib.nvim.fs.create_entry")
  if ok then
    create_entry = mod
  else
    local ok2, mod2 = pcall(require, "lib.nvim.fs.write.to_file")
    if ok2 then
      write_to_file = mod2
      vim.schedule(function()
        LOG.warn(
          "lib.nvim is missing 'fs.create_entry' (older checkout?) — "
            .. "falling back to 'fs.write.to_file' for file creation."
        )
      end)
    else
      vim.schedule(function()
        LOG.error(
          "lib.nvim not found, or too old to provide 'fs.create_entry' / "
            .. "'fs.write.to_file' — file creation is unavailable."
        )
      end)
    end
  end
end

-- ── File creation ────────────────────────────────────────────────────────────

---Create empty file at `path`, creating parent directories as needed.
---@internal
---@param path string
---@return boolean ok
---@return string|nil err
local function touch(path)
  local native = CROSS.to_native(path)

  if create_entry then
    local dir = vim.fn.fnamemodify(native, ":h")
    local name = vim.fn.fnamemodify(native, ":t")
    local ok, _, path_or_err = create_entry(dir, name)
    if not ok then return false, path_or_err end
    -- The path searches cache directory listings; a file created now would
    -- otherwise stay invisible to the next lookup until those caches expire.
    PATH.invalidate_caches()
    return true, nil
  end

  if not write_to_file then return false, "lib.nvim not available — cannot create files" end

  local ok_write, err = write_to_file(native, "")
  if not ok_write then return false, err or ("could not open " .. native) end
  PATH.invalidate_caches()
  return true, nil
end

-- ── Nearest existing ancestor directory ──────────────────────────────────────

---Find the nearest existing ancestor directory of `path` (walking from the
---full path up to its root segment). Pure query — does not open anything.
---@internal
---@param path string
---@return string|nil dir  absolute, normalized
local function find_nearest_existing_dir(path)
  if not path or path == "" then return nil end
  local norm = (vim.fs.normalize and vim.fs.normalize(path)) or path
  local segs = {}
  for s in norm:gmatch("[^/\\]+") do
    segs[#segs + 1] = s
  end

  for i = #segs, 1, -1 do
    local candidate = table.concat(segs, "/", 1, i)
    local cwd = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
    local try_paths = { candidate, "/" .. candidate, cwd .. "/" .. candidate }

    for _, p in ipairs(try_paths) do
      local ok_norm, pn = pcall(vim.fs.normalize, p)
      if ok_norm then
        local st = uv.fs_stat(pn)
        if st and st.type == "directory" then return pn end
      end
    end
  end
  return nil
end

-- ── filetree.nvim (soft dependency) ──────────────────────────────────────────

---Set cwd to `dir` and hand it to filetree.nvim's tree (rooted + focused there).
---@internal
---@param dir string
---@return nil
local function open_in_filetree(dir)
  local adapter = FILETREE_UTIL.adapter()
  if not adapter then
    LOG.warn("filetree.nvim not available — could not open: " .. dir)
    return
  end
  local ok_cd = pcall(vim.cmd.cd, vim.fn.fnameescape(dir))
  if not ok_cd then LOG.warn("Could not set cwd to: " .. dir) end
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

-- ── Confirm dialog (ui.kit, soft dependency) ────────────────────────

---@type table|nil  ui.kit module, or nil when unavailable
local kit
do
  local ok, mod = pcall(require, "ui.kit")
  if ok and type(mod) == "table" and type(mod.confirm) == "function" then
    kit = mod
  else
    kit = nil
    vim.schedule(function()
      LOG.debug(
        "optional dependency 'ui.nvim' not found — using vim.ui.select "
          .. "fallback for the create-on-missing prompt. Add it to your plugin "
          .. "spec (dependencies = { 'StefanBartl/ui.nvim' }) for the themed dialog."
      )
    end)
  end
end

---Ask the user to pick one of `choices` (button dialog via ui.kit, or
---vim.ui.select when ui.kit is unavailable).
---@internal
---@param question string
---@param choices string[]
---@param on_choice fun(choice: string|nil)  nil = cancelled
---@return nil
local function ask(question, choices, on_choice)
  if kit then
    kit.confirm({
      question = question,
      choices = choices,
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
  if nearest_dir and FILETREE_UTIL.adapter() then choices[#choices + 1] = FILETREE end
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
