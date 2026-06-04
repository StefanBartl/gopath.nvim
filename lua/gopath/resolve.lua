---@module 'gopath.resolve'
---@brief Orchestrates providers to produce a GopathResult.
---@description
--- Entry point for all cursor-based resolution. Tries resolvers in this order:
---   1. Help (:h subject) — always, all filetypes.
---   2. Env var path ($VAR/...) — always, before filetoken sees raw token.
---   3. Filetoken — always, all filetypes; short-circuits only when the file
---      actually *exists* on disk so that language-specific resolvers (e.g. Lua
---      require_path) can run first when the raw token is not a real path.
---   4. Language-specific pipeline (lsp / treesitter / builtin) — only when the
---      filetype has a config entry and is not disabled.
---   5. Filetoken fallback — the non-existing filetoken result from step 3, if any.
---   6. Raw cfile — last resort.

local C    = require("gopath.config")
local REG  = require("gopath.registry")
local safe = require("gopath.util.safe")
local LOG  = require("gopath.util.log")

local M = {}

---@class GopathResolveOpts
---@field order string[]|nil
---@field timeout_ms integer|nil

---Resolve the entity under the cursor using configured providers.
---@param opts GopathResolveOpts|nil
---@return GopathResult|nil, string|nil  result, error
function M.resolve_at_cursor(opts)
  local cfg = C.get()
  local ft  = vim.bo.filetype or "text"

  -- 1. Help resolver (all filetypes, very cheap)
  do
    local help = require("gopath.resolvers.common.help").resolve()
    if help then return help, nil end
  end

  -- 2. Environment variable path ($VAR/foo.md, ${VAR}/foo.md).
  --    Runs before filetoken so that the $ prefix is caught here and
  --    filetoken never receives a raw env-var token it cannot handle.
  do
    local ev_cfg = cfg.env_variable_resolution
    if not ev_cfg or ev_cfg.enable ~= false then
      local ok, env = pcall(function()
        return require("gopath.resolvers.common.env_path").resolve()
      end)
      if ok and env then return env, nil end
    end
  end

  -- 3. Filetoken: short-circuit only on confirmed-existing files.
  --    Non-existing result is saved so language resolvers get priority.
  local ftok_fallback = nil
  do
    local ftok = require("gopath.resolvers.common.filetoken").resolve()
    if ftok then
      if ftok.exists then
        return ftok, nil
      end
      ftok_fallback = ftok
    end
  end

  -- 4. Language-specific pipeline
  local lang = cfg.languages[ft]

  if lang == false or (type(lang) == "table" and lang.enable == false) then
    LOG.debug("language disabled for filetype: " .. ft)
    return ftok_fallback or nil, "language-disabled"
  end

  local lang_enabled = type(lang) == "table"

  if lang_enabled then
    local order
    if cfg.mode == "lsp" then
      order = { "lsp" }
    elseif cfg.mode == "treesitter" then
      order = { "treesitter" }
    elseif cfg.mode == "builtin" then
      order = { "builtin" }
    else
      order = (opts and opts.order) or cfg.order or { "lsp", "treesitter", "builtin" }
    end

    for _, provider in ipairs(order) do
      local ok, result = safe.call(function()
        return REG.run_language_pipeline(ft, provider, {
          timeout_ms = (opts and opts.timeout_ms) or cfg.lsp_timeout_ms,
        })
      end)
      if ok and result then
        return result, nil
      end
    end
  end

  -- 5. Return the filetoken non-exist result (more specific than raw cfile)
  if ftok_fallback then
    return ftok_fallback, nil
  end

  -- 6. Last resort: raw cfile
  local cfile = vim.fn.expand("<cfile>")
  if cfile and cfile ~= "" then
    return {
      language   = ft,
      kind       = "file",
      path       = cfile,
      range      = nil,
      chain      = nil,
      source     = "builtin-fallback",
      confidence = 0.5,
      exists     = false,
    }, nil
  end

  return nil, "no-match"
end

return M
