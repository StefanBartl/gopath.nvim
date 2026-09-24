---@module 'gopath.util.known_dirs'
---@brief Resolve one entry of `env_variable_resolution.shorten_known_dirs`.
---@description
--- A "known dir" is a directory gopath can locate on its own at runtime
--- without requiring a real environment variable to be set for it -- e.g.
--- `vim.fn.stdpath("config")` for the running Neovim's own config directory.
--- An entry is either a plain absolute-path string, or a zero-arg function
--- computing one (needed for anything only knowable once Neovim is running,
--- like stdpath()). Shared by the forward resolver (`env_path`, expanding
--- `$VAR` while navigating) and the reverse one (`env_shorten`, rewriting an
--- absolute path on the current line back to `$VAR`).

local M = {}

---@param resolver string|(fun(): string)
---@return string|nil
function M.resolve(resolver)
  if type(resolver) == "function" then
    local ok, v = pcall(resolver)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
  end
  if type(resolver) == "string" and resolver ~= "" then return resolver end
  return nil
end

return M
