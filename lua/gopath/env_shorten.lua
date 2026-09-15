---@module 'gopath.env_shorten'
---@brief Reverse of env_path resolution: rewrites an absolute directory
--- prefix on the current line back into a `$VAR` reference, e.g. turns
--- `E:\repos\gopath.nvim` into `$REPOS_DIR\gopath.nvim`.
---@see gopath.resolvers.common.env_path for the forward direction (expand
--- $VAR -> absolute path)

local LOG = require("gopath.util.log")

local M = {}

---Resolve an environment variable name to its string value.
--- vim.env is checked first (reflects runtime vim.env assignments);
--- os.getenv is used as fallback for variables inherited from the shell.
---@internal
---@param name string
---@return string|nil
local function resolve_var(name)
  if type(vim.env) == "table" then
    local v = vim.env[name]
    if type(v) == "string" and v ~= "" then return v end
  end
  local v = os.getenv(name)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

---Replace every case-insensitive occurrence of `needle` in `haystack` with
---`repl`, using plain substring matching (no Lua patterns) so backslashes,
---colons, and drive letters never need escaping.
---@internal
---@param haystack string
---@param needle string
---@param repl string
---@return string result
---@return integer replacements
local function replace_ci(haystack, needle, repl)
  if needle == "" then return haystack, 0 end
  local hay_lower, needle_lower = haystack:lower(), needle:lower()
  local nlen = #needle
  local out, count, i, n = {}, 0, 1, #haystack
  while i <= n do
    if hay_lower:sub(i, i + nlen - 1) == needle_lower then
      out[#out + 1] = repl
      i = i + nlen
      count = count + 1
    else
      out[#out + 1] = haystack:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out), count
end

---Rewrite every occurrence of a configured env var's directory value found
---in `line` to `$VAR`. Both backslash and forward-slash spellings of the
---value are tried (the variable itself is stored with one separator style,
---but the line may use either), and matching is case-insensitive since
---Windows paths are.
---@param line string
---@param var_names string[]
---@return string result
---@return integer replacements
function M.shorten(line, var_names)
  local total = 0
  for _, name in ipairs(var_names) do
    local value = resolve_var(name)
    if value then
      -- Strip a trailing separator so the one already in `line` after the
      -- match is left untouched (…\repos\foo -> $REPOS_DIR\foo, not \\foo).
      local base = value:gsub("[/\\]+$", "")
      local back_slashed = (base:gsub("/", "\\"))
      local forward_slashed = (base:gsub("\\", "/"))
      for _, needle in ipairs({ back_slashed, forward_slashed }) do
        local n
        line, n = replace_ci(line, needle, "$" .. name)
        total = total + n
      end
    end
  end
  return line, total
end

---Apply `M.shorten` to the current line in place, using the configured
---`env_variable_resolution.shorten_vars` list (default `{"REPOS_DIR"}`).
---@return nil
function M.shorten_current_line()
  local cfg = require("gopath.config").get()
  local opt = cfg.env_variable_resolution
  local var_names = (opt and opt.shorten_vars) or { "REPOS_DIR" }

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  local result, count = M.shorten(line, var_names)

  if count == 0 then
    LOG.warn("nothing to shorten on this line (checked: " .. table.concat(var_names, ", ") .. ")")
    return
  end

  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { result })
  LOG.info(string.format("shortened %d occurrence%s", count, count == 1 and "" or "s"))
end

return M
