---@module 'gopath.env_shorten'
---@brief Reverse of env_path resolution, but structural rather than literal:
--- rewrites an absolute path whose root segment is a configured directory
--- name (default "repos") into a `$VAR` reference -- independent of drive
--- letter, and independent of what $VAR actually resolves to on THIS
--- machine (so text stays correct across machines/OSes where the value
--- differs, e.g. E:\repos on one box, /home/x/repos on another).
---
--- Recognised root forms, all immediately followed by the segment name:
---   <letter>:\  or  <letter>:/    Windows drive root   (E:\repos\..., C:/repos/...)
---   /                             POSIX absolute root   (/repos/...)
---   ~/  or  ~\                    home-relative         (~/repos/...)
---   (nothing)                     already root-relative (repos/...)
---@see gopath.resolvers.common.env_path for the forward direction (expand
--- $VAR -> absolute path)

local LOG = require("gopath.util.log")

local M = {}

-- Characters that continue a path/word token. A match is only accepted when
-- the character BEFORE its root marker is none of these (or there is none --
-- start of line). This is what stops ".../foo/repos/..." (a plain nested
-- folder that happens to be named "repos") from being mistaken for a
-- repos-root reference: the "/" right before "repos" there is itself
-- preceded by "o", a word character, so it fails the boundary check.
local BOUNDARY_CHARS = "[%w_%.%-:/\\~]"

---@internal
---@param line string
---@param pos integer  1-based index into `line`
---@return boolean
local function is_token_boundary(line, pos)
  if pos <= 1 then return true end
  return not line:sub(pos - 1, pos - 1):match(BOUNDARY_CHARS)
end

---Length of the root marker (drive letter, POSIX root, or `~`) starting at
---`pos`, or 0 when the segment is already root-relative (no marker at all).
---@internal
---@param line string
---@param pos integer
---@return integer
local function root_marker_len(line, pos)
  local rest = line:sub(pos)
  local m = rest:match("^%a:[/\\]+") or rest:match("^~[/\\]+") or rest:match("^[/\\]+")
  return m and #m or 0
end

---Rewrite every root-relative occurrence of `segment` (e.g. "repos") in
---`line` to `$var_name`, trying every recognised root form. Case-insensitive
---on both the segment name and (on Windows) the drive letter, since path
---case never carries meaning there.
---@internal
---@param line string
---@param segment string
---@param var_name string
---@return string result
---@return integer replacements
local function shorten_segment(line, segment, var_name)
  local seg_lower = segment:lower()
  local seg_len = #segment
  local repl = "$" .. var_name

  local out, count, i, n = {}, 0, 1, #line
  while i <= n do
    local matched = false
    if is_token_boundary(line, i) then
      local root_len = root_marker_len(line, i)
      local seg_start = i + root_len
      local candidate = line:sub(seg_start, seg_start + seg_len - 1)
      if candidate:lower() == seg_lower then
        local after = line:sub(seg_start + seg_len, seg_start + seg_len)
        -- A bare "repos" with no drive/root/`~` marker before it is weak
        -- evidence on its own -- it could just as easily be an ordinary word
        -- in a sentence ("clone the repos"). Require an explicit trailing
        -- separator in that case; a marked root may still end the whole
        -- line/token bare ("E:\repos" alone is a valid directory reference).
        local after_ok = root_len > 0 and (after == "" or not after:match("[%w_%.%-]"))
          or (root_len == 0 and after:match("[/\\]") ~= nil)
        if after_ok then
          out[#out + 1] = repl
          i = seg_start + seg_len
          count = count + 1
          matched = true
        end
      end
    end
    if not matched then
      out[#out + 1] = line:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(out), count
end

---Rewrite every occurrence of every configured `{segment, var}` pair in
---`line`, longest segment name first (so e.g. a configured "repos-archive"
---is tried before a shorter "repos" that would otherwise shadow it).
---@param line string
---@param seg_var_pairs { segment: string, var: string }[]
---@return string result
---@return integer replacements
function M.shorten(line, seg_var_pairs)
  local ordered = vim.deepcopy(seg_var_pairs)
  table.sort(ordered, function(a, b)
    return #a.segment > #b.segment
  end)

  local total = 0
  for _, p in ipairs(ordered) do
    local n
    line, n = shorten_segment(line, p.segment, p.var)
    total = total + n
  end
  return line, total
end

---Apply `M.shorten` to the current line in place, using the configured
---`env_variable_resolution.shorten_dirs` map (default `{ repos = "REPOS_DIR" }`).
---@return nil
function M.shorten_current_line()
  local cfg = require("gopath.config").get()
  local opt = cfg.env_variable_resolution
  local dirs = (opt and opt.shorten_dirs) or { repos = "REPOS_DIR" }

  local pairs_list = {}
  for segment, var_name in pairs(dirs) do
    pairs_list[#pairs_list + 1] = { segment = segment, var = var_name }
  end

  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  local result, count = M.shorten(line, pairs_list)

  if count == 0 then
    LOG.warn("nothing to shorten on this line")
    return
  end

  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { result })
  LOG.info(string.format("shortened %d occurrence%s", count, count == 1 and "" or "s"))
end

return M
