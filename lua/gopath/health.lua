---@module 'gopath.health'
---@brief :checkhealth gopath — verifies all plugin dependencies and config.

local M = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local ok_s   = vim.health.ok    or vim.health.report_ok
local warn_s  = vim.health.warn  or vim.health.report_warn
local err_s   = vim.health.error or vim.health.report_error
local info_s  = vim.health.info  or vim.health.report_info
local start_s = vim.health.start or vim.health.report_start

local function exe(bin)
  return vim.fn.executable(bin) == 1
end

local function require_ok(mod)
  local ok, _ = pcall(require, mod)
  return ok
end

-- ── Sections ─────────────────────────────────────────────────────────────────

local function check_neovim()
  start_s("Neovim version")
  local v = vim.version()
  if v.major > 0 or v.minor >= 9 then
    ok_s(string.format("Neovim %d.%d.%d (>= 0.9 required)", v.major, v.minor, v.patch))
  else
    err_s(string.format("Neovim %d.%d.%d detected — gopath.nvim requires 0.9+", v.major, v.minor, v.patch))
  end
  if v.major > 0 or v.minor >= 10 then
    ok_s("vim.fs.joinpath available (Neovim 0.10+)")
  else
    info_s("vim.fs.joinpath not available (Neovim < 0.10) — using string concat fallback")
  end
end

local function check_external_tools()
  start_s("External CLI tools")

  if exe("fd") then
    ok_s("fd found — used by tailsearch + truncated.finder")
  elseif exe("fdfind") then
    ok_s("fdfind found — used by tailsearch + truncated.finder")
  else
    warn_s("fd / fdfind not found — install fd-find for best performance\n"
        .. "  tailsearch and truncated.finder will fall back to rg")
  end

  if exe("rg") then
    ok_s("rg (ripgrep) found — used as fallback search tool")
  else
    warn_s("rg not found — install ripgrep for fallback search\n"
        .. "  Without fd AND rg, suffix search and live-search fallback are unavailable")
  end

  if exe("git") then
    ok_s("git found — used for git-root detection in tailsearch roots")
  else
    warn_s("git not found — git-root detection will be skipped in tailsearch")
  end
end

local function check_lsp()
  start_s("LSP")
  local clients = vim.lsp.get_active_clients and vim.lsp.get_active_clients()
              or (vim.lsp.get_clients and vim.lsp.get_clients()) or {}
  if #clients > 0 then
    local names = {}
    for _, c in ipairs(clients) do names[#names + 1] = c.name end
    ok_s(string.format("%d active LSP client(s): %s", #clients, table.concat(names, ", ")))
  else
    info_s("No active LSP clients in current buffer — language resolvers need LSP")
  end
end

local function check_which_key()
  start_s("which-key")
  local ok_cfg, cfg_mod = pcall(require, "gopath.config")
  local which_key_enabled = ok_cfg and cfg_mod.get().which_key ~= false

  if require_ok("which-key") then
    if which_key_enabled then
      ok_s("which-key.nvim installed — probe keymap label registered")
    else
      info_s("which-key.nvim installed, but which_key = false in config")
    end
  else
    info_s("which-key.nvim not installed — optional, no label for the probe keymap")
  end
end

local function check_open_nvim()
  start_s("open.nvim")
  if require_ok("open_nvim") then
    ok_s("open.nvim installed — external files routed through its 'default' handler (WSL-aware)")
  else
    info_s("open.nvim not installed — external files use gopath's built-in per-OS opener\n"
        .. "  install StefanBartl/open.nvim for shared handlers and WSL support")
  end
end

local function check_lib_nvim()
  start_s("lib.nvim")
  -- Required: the :Gopath command layer (lib.nvim.usercmd.composer)
  -- registers unconditionally, no pcall fallback.
  if require_ok("lib.nvim.usercmd.composer") then
    ok_s("lib.nvim detected (:Gopath command layer available)")
  else
    warn_s("lib.nvim not found — :Gopath will fail to register\n"
        .. "  install StefanBartl/lib.nvim as a dependency")
  end
  if require_ok("lib.nvim.ui.kit") then
    ok_s("lib.nvim installed — create-on-missing dialog uses ui.kit.confirm, notify styling active")
  else
    info_s("lib.nvim not installed — create-on-missing dialog falls back to vim.ui.select,\n"
        .. "  notify/cross-path helpers use built-in fallbacks\n"
        .. "  install StefanBartl/lib.nvim for the themed dialog and consistent styling")
  end
end

local function check_filetree_nvim()
  start_s("filetree.nvim")
  local ok_ft, filetree = pcall(require, "filetree")
  if ok_ft and type(filetree) == "table" and filetree.is_initialized() then
    ok_s("filetree.nvim installed and set up — create-on-missing dialog offers 'Open in filetree'")
  elseif ok_ft then
    info_s("filetree.nvim installed but setup() not called (or not yet run) — "
        .. "'Open in filetree' choice unavailable until then")
  else
    info_s("filetree.nvim not installed — create-on-missing dialog has no 'Open in filetree' choice\n"
        .. "  install StefanBartl/filetree.nvim to open the nearest existing ancestor "
        .. "directory there instead of just creating the file")
  end
end

local function check_treesitter()
  start_s("Tree-sitter")
  if require_ok("nvim-treesitter") then
    ok_s("nvim-treesitter installed")
  else
    info_s("nvim-treesitter not installed — treesitter-based resolvers disabled")
  end
  local ft = vim.bo.filetype
  if ft and ft ~= "" then
    local ok_ts = pcall(function()
      local p = require("nvim-treesitter.parsers")
      if not p.has_parser(ft) then error("no parser") end
    end)
    if ok_ts then
      ok_s("Parser available for filetype: " .. ft)
    else
      info_s("No Tree-sitter parser for filetype '" .. ft .. "'")
    end
  end
end

local function check_config()
  start_s("Configuration")
  local ok, cfg_mod = pcall(require, "gopath.config")
  if not ok then
    err_s("Could not load gopath.config — plugin may not be set up")
    return
  end
  local cfg = cfg_mod.get()

  info_s("mode = " .. (cfg.mode or "hybrid"))
  info_s("order = " .. vim.inspect(cfg.order or { "lsp", "treesitter", "builtin" }))

  if cfg.linepath and cfg.linepath.enable then
    ok_s("linepath.enable = true  (whole-line path extraction active)")
  else
    warn_s("linepath.enable = false — whole-line scanning disabled")
  end

  local ts = cfg.tailsearch or {}
  if ts.enable ~= false then
    ok_s("tailsearch.enable = true  (suffix-based filesystem search active)")
    info_s("  max_components   = " .. tostring(ts.max_components or 6))
    info_s("  ask_on_ambiguous = " .. tostring(ts.ask_on_ambiguous ~= false))
    if ts.roots then
      info_s("  roots (custom)   = " .. vim.inspect(ts.roots))
    else
      info_s("  roots            = auto (bufdir -> cwd -> git root -> stdpaths)")
    end
  else
    warn_s("tailsearch.enable = false — suffix search disabled")
  end

  local alt = cfg.alternate or {}
  if alt.enable then
    ok_s("alternate.enable = true  (Levenshtein fuzzy fallback active)")
    info_s("  similarity_threshold = " .. tostring(alt.similarity_threshold or 75))
  else
    info_s("alternate.enable = false")
  end

  local ext = cfg.external or {}
  if ext.enable then
    ok_s("external.enable = true  (images/PDFs open in system viewer)")
  else
    info_s("external.enable = false")
  end

  local com = cfg.create_on_missing or {}
  if com.enable ~= false then
    ok_s("create_on_missing.enable = true  (offers to create missing files)")
    info_s("  confirm = " .. tostring(com.confirm ~= false)
        .. "  (dialog: lib.nvim ui.kit.confirm / vim.ui.select — see below)")
  else
    info_s("create_on_missing.enable = false — 'gC'/:GopathCheck still offers to create")
  end

  start_s("Keymaps")
  local maps = cfg.mappings or {}
  local function km(name)
    local v = maps[name]
    if v and v ~= false then
      info_s(string.format("  %-16s %s", name .. " =", vim.inspect(v)))
    end
  end
  km("open_here")
  km("open_split")
  km("open_vsplit")
  km("open_tab")
  km("copy_location")
  km("debug")
  km("probe")
  km("check")
end

local function check_truncated()
  start_s("Truncated path cache")
  local ok_cfg, cfg_mod = pcall(require, "gopath.config")
  if not ok_cfg then return end
  local cfg = cfg_mod.get()

  if not (cfg.truncated and cfg.truncated.enable) then
    info_s("truncated path resolution is disabled in config")
    return
  end

  ok_s("truncated.enable = true")

  if require_ok("gopath.truncated.finder") then
    ok_s("gopath.truncated.finder loaded (live search backend)")
  else
    err_s("gopath.truncated.finder failed to load")
  end

  local ok_cache, cache = pcall(require, "gopath.truncated.cache")
  if not ok_cache then
    err_s("gopath.truncated.cache failed to load")
    return
  end

  local ok_load = pcall(function() cache.load_from_disk() end)
  if ok_load then
    local state = cache._get_state and cache._get_state() or {}
    local n     = #(state.paths or {})
    local built = state.last_built
    if n > 0 then
      ok_s(string.format("Cache loaded: %d files indexed (last built: %s)",
        n, built and os.date("%Y-%m-%d %H:%M", built) or "unknown"))
    else
      warn_s("Cache is empty — run :Gopath cache build to index the filesystem")
    end
    info_s("  use_cache  = " .. tostring(cfg.truncated.use_cache ~= false))
    info_s("  max_depth  = " .. tostring(cfg.truncated.max_depth or 6))
  else
    warn_s("Could not load cache from disk — run :Gopath cache build")
  end
end

local function check_languages()
  start_s("Language resolvers")
  local ok_cfg, cfg_mod = pcall(require, "gopath.config")
  if not ok_cfg then return end
  local cfg = cfg_mod.get()
  local langs = cfg.languages or {}

  if not next(langs) then
    info_s("No language-specific resolvers configured")
    return
  end

  for ft, lang_cfg in pairs(langs) do
    if lang_cfg == false or (type(lang_cfg) == "table" and lang_cfg.enable == false) then
      info_s(ft .. ": disabled")
    else
      ok_s(ft .. ": enabled")
    end
  end
end

-- ── Entry point ───────────────────────────────────────────────────────────────

function M.check()
  check_neovim()
  check_external_tools()
  check_lsp()
  check_open_nvim()
  check_lib_nvim()
  check_filetree_nvim()
  check_treesitter()
  check_which_key()
  check_config()
  check_truncated()
  check_languages()
end

return M
