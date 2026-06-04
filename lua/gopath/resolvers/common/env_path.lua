---@module 'gopath.resolvers.common.env_path'
--- Resolves paths prefixed with environment variable references.
--- Supports $VAR/rest, ${VAR}/rest, $VAR\rest and ${VAR}\rest syntax.
---
--- IMPORTANT: This resolver deliberately bypasses vim.fn.expand("<cfile>")
--- and reads the raw line text directly. expand() would corrupt tokens like
--- $REPOS_DIR\foo by prepending cwd before env_path ever runs.

local U   = require("gopath.util.path")
local LOC = require("gopath.util.location")

local M = {}

-- ---------------------------------------------------------------------------
-- Token extraction (raw, no expand())
-- ---------------------------------------------------------------------------

--- Extract the raw token at the cursor from the current line without calling
--- vim.fn.expand(), which would corrupt $ prefixes.
--- Accepts $, {, } as valid token characters in addition to path characters.
---@return string|nil
local function raw_token_at_cursor()
    local line = vim.api.nvim_get_current_line()
    local col  = vim.api.nvim_win_get_cursor(0)[2] + 1 -- convert to 1-based

    -- Characters valid inside a path token including env-var syntax.
    -- Backslash included for Windows paths.
    local path_chars = "[%w/\\%.%-%_:%(%)%+~@%$%{%}]"

    local start_col = col
    while start_col > 1 do
        if not line:sub(start_col - 1, start_col - 1):match(path_chars) then
            break
        end
        start_col = start_col - 1
    end

    local end_col = col
    while end_col <= #line do
        if not line:sub(end_col, end_col):match(path_chars) then
            break
        end
        end_col = end_col + 1
    end
    end_col = end_col - 1

    if start_col > end_col then
        return nil
    end

    local tok = line:sub(start_col, end_col):gsub("^%s+", ""):gsub("%s+$", "")
    return tok ~= "" and tok or nil
end

-- ---------------------------------------------------------------------------
-- Parsing helpers
-- ---------------------------------------------------------------------------

--- Try to match a $VAR or ${VAR} prefix in raw token.
--- Both forward-slash and backslash separators are accepted.
---@param raw string
---@return string|nil var_name
---@return string|nil remainder  -- path after the variable reference and separator
local function parse_env_token(raw)
    if not raw or raw == "" then
        return nil, nil
    end

    -- ${VAR}/rest  or  ${VAR}\rest  or  ${VAR} (no separator)
    local var, rest = raw:match("^%$%{([%w_]+)%}[/\\]?(.*)")
    if var then
        return var, rest or ""
    end

    -- $VAR/rest  or  $VAR\rest  or  $VAR (no separator)
    -- Use [/\\] as the required separator to avoid matching $VAR.field chains.
    -- Also accept end-of-string so bare "$VAR" resolves to the directory.
    var, rest = raw:match("^%$([%w_]+)[/\\](.*)")
    if var then
        return var, rest or ""
    end

    -- Bare "$VAR" with nothing after it
    var = raw:match("^%$([%w_]+)$")
    if var then
        return var, ""
    end

    return nil, nil
end

--- Resolve an environment variable name to its string value.
--- vim.env is checked first (reflects runtime vim.env assignments);
--- os.getenv is used as fallback for variables inherited from the shell.
---@param name string
---@return string|nil
local function resolve_var(name)
    -- vim.env can be nil in some minimal Neovim builds; guard it.
    if type(vim.env) == "table" then
        local v = vim.env[name]
        if type(v) == "string" and v ~= "" then
            return v
        end
    end

    local v = os.getenv(name)
    if type(v) == "string" and v ~= "" then
        return v
    end

    return nil
end

--- Join a resolved variable value with the path remainder.
--- Normalizes all separators to forward slashes, then strips duplicate
--- slashes introduced by trailing separators in the variable value.
---@param base string  resolved variable value, e.g. "E:\repos\" or "/home/user/repos"
---@param rest string  remainder after the variable, e.g. "WKDBooks/foo.md"
---@return string      absolute path with forward slashes, no trailing slash
local function join_env_path(base, rest)
    -- Normalize both parts: backslash -> forward slash, strip trailing slash.
    base = base:gsub("\\", "/"):gsub("/$", "")
    rest = rest:gsub("\\", "/"):gsub("^/+", "")

    if rest == "" then
        return base
    end

    return base .. "/" .. rest
end

-- ---------------------------------------------------------------------------
-- Public resolver
-- ---------------------------------------------------------------------------

--- Main resolver entry point required by the GopathResult contract.
--- Returns a GopathResult when the token under the cursor starts with
--- a resolvable environment variable reference, nil otherwise.
---@return GopathResult|nil
function M.resolve()
    -- Guard: respect the user's opt-in/opt-out flag.
    local cfg = require("gopath.config").get()
    local opt = cfg.env_variable_resolution
    if not (opt and opt.enable) then
        return nil
    end

    -- Read the raw token directly from the line buffer.
    -- Do NOT use P.expand_cfile() here: vim.fn.expand() would resolve $VAR
    -- relative to cwd before we can intercept it.
    local raw = raw_token_at_cursor()
    if not raw then
        return nil
    end

    local var_name, remainder = parse_env_token(raw)
    if not var_name then
        return nil -- Token does not start with an env-var reference.
    end

    local var_value = resolve_var(var_name)
    if not var_value then
        if cfg.dev_mode then
            vim.notify(
                string.format("[gopath/env_path] Variable not set: $%s", var_name),
                vim.log.levels.DEBUG
            )
        end
        return nil
    end

    -- Separate an optional :line or :line:col suffix from the path component.
    -- LOC.parse_location handles all known formats (:N, :N:M, (N), +N).
    local parsed_loc = LOC.parse_location(remainder or "")
    local clean_path = parsed_loc.path or (remainder or "")

    -- Build the absolute path and let Neovim canonicalize it.
    local joined = join_env_path(var_value, clean_path)
    local abs    = vim.fn.fnamemodify(joined, ":p")

    -- fnamemodify(":p") may re-introduce a trailing separator on directories;
    -- strip it so downstream exists() works correctly.
    abs = abs:gsub("[/\\]$", "")

    local exists = U.exists(abs)

    if cfg.dev_mode then
        vim.notify(
            string.format(
                "[gopath/env_path] $%s=%s  ->  %s  (exists=%s)",
                var_name, var_value, abs, tostring(exists)
            ),
            vim.log.levels.DEBUG
        )
    end

    return {
        language   = vim.bo.filetype or "text",
        kind       = "file",
        path       = abs,
        range      = LOC.create_range(parsed_loc.line, parsed_loc.col),
        chain      = nil,
        source     = "env-path",
        confidence = exists and 0.95 or 0.4,
        exists     = exists,
    }
end

return M
