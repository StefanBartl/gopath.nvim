---@module 'gopath.env_shorten'
---@brief Reverse of env_path resolution, in two flavours.
---@description
--- 1. Structural (`M.shorten`/`M.shorten_current_line`, :GopathToReposDir):
---    rewrites an absolute path whose root segment is a configured directory
---    NAME (default "repos") into a `$VAR` reference -- independent of drive
---    letter, and independent of what $VAR actually resolves to on THIS
---    machine (so text stays correct across machines/OSes where the value
---    differs, e.g. E:\repos on one box, /home/x/repos on another). Meant
---    for a personal convention ("all my repos live under a folder named
---    repos"), configured via `env_variable_resolution.shorten_dirs`.
---
---    Recognised root forms, all immediately followed by the segment name:
---      <letter>:\  or  <letter>:/    Windows drive root   (E:\repos\..., C:/repos/...)
---      /                             POSIX absolute root   (/repos/...)
---      ~/  or  ~\                    home-relative         (~/repos/...)
---      (nothing)                     already root-relative (repos/...)
---
--- 2. Literal (`M.shorten_known`/`M.shorten_current_line_known`,
---    :GopathToNvimDir): rewrites literal occurrences of a computed absolute
---    DIRECTORY (e.g. `vim.fn.stdpath("config")`) into a `$VAR` reference.
---    Unlike (1) this does NOT match on a bare folder name -- "nvim" alone
---    would false-positive on unrelated folders -- it matches the full
---    resolved path, case- and separator-insensitively. Configured via
---    `env_variable_resolution.shorten_known_dirs` (see gopath.util.known_dirs).
---
--- Both flavours also recognise a RELATIVE path that only resolves under a
--- configured root once joined to the current buffer's own directory --
--- typically a Markdown link (`[text](path)`/`![alt](path)`), since those
--- are document-relative by convention, the same assumption
--- `gopath.resolvers.common.linepath` makes when resolving one. A relative
--- link path is resolved against `vim.fn.expand("%:p:h")`, and only
--- rewritten (to the absolute+abbreviated form, e.g. `./assets/a.png` in a
--- file under `$NVIM_CONFIG_DIR/docs/x/` becomes
--- `$NVIM_CONFIG_DIR/docs/x/assets/a.png`) when the resolved absolute path
--- actually falls under one of the configured roots -- an unrelated relative
--- link, or a URL (a Markdown link's path is very often one), is left
--- untouched: a URL is never treated as a relative filesystem path, since
--- resolving one against the buffer directory and matching it by PREFIX
--- against a configured root can spuriously "match" through the buffer's
--- OWN path rather than anything about the URL -- see `skip_relative_resolution`.
--- `:GopathToReposDir`/`:GopathToNvimDir` also take
--- a visual range (`:'<,'>GopathToNvimDir`): with one, only the selected
--- span is rewritten (tried as a literal match first, then as a relative
--- candidate), leaving the rest of the line alone -- see
--- `gopath.util.selection`.
---@see gopath.resolvers.common.env_path for the forward direction (expand
--- $VAR -> absolute path)

local LOG = require("gopath.util.log")
local KNOWN_DIRS = require("gopath.util.known_dirs")
local SELECTION = require("gopath.util.selection")
local URL = require("gopath.util.url")

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

---Rewrite every literal occurrence of the absolute directory `abs_dir` in
---`line` to `$var_name`. Unlike `shorten_segment` (a structural match on a
---bare folder NAME) this matches a full absolute path literally -- case- and
---separator-insensitively -- for a "well-known" directory that has one
---correct value on this machine rather than being a free-form user folder.
---@internal
---@param line string
---@param abs_dir string
---@param var_name string
---@return string result
---@return integer replacements
local function shorten_prefix(line, abs_dir, var_name)
  local norm_dir = abs_dir:gsub("\\", "/"):gsub("/$", "")
  if norm_dir == "" then return line, 0 end
  local dir_lower = norm_dir:lower()
  local dir_len = #norm_dir
  local repl = "$" .. var_name

  local out, count, i, n = {}, 0, 1, #line
  while i <= n do
    local matched = false
    if is_token_boundary(line, i) then
      -- Same length as norm_dir when sliced: gsub("\\","/") only ever swaps
      -- one character for one character, so the index alignment below holds.
      local candidate = line:sub(i, i + dir_len - 1):gsub("\\", "/")
      if candidate:lower() == dir_lower then
        local after = line:sub(i + dir_len, i + dir_len)
        if after == "" or after:match("[/\\]") or not after:match("[%w_%.%-]") then
          out[#out + 1] = repl
          i = i + dir_len
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

---Rewrite every literal occurrence of every configured `{var, dir}` pair
---in `line` (see `shorten_prefix`), longest directory first for the same
---shadowing reason as `M.shorten`.
---@param line string
---@param var_dir_pairs { var: string, dir: string }[]
---@return string result
---@return integer replacements
function M.shorten_known(line, var_dir_pairs)
  local ordered = vim.deepcopy(var_dir_pairs)
  table.sort(ordered, function(a, b)
    return #a.dir > #b.dir
  end)

  local total = 0
  for _, p in ipairs(ordered) do
    local n
    line, n = shorten_prefix(line, p.dir, p.var)
    total = total + n
  end
  return line, total
end

-- ── Relative paths (typically Markdown links) resolved against bufdir ──────

---Whether `path` is NOT a plausible relative FILESYSTEM path -- either
---already absolute (Windows drive, POSIX/UNC root, `~`-relative: the
---literal/structural passes above already handle genuinely absolute text,
---and joining it to the buffer directory would just produce garbage), or a
---URL (`scheme://…`, `mailto:…`, a bare `www.…`/known-TLD host). A Markdown
---link's path is very often a URL, not a file reference at all, and joining
---one to the buffer directory then matching it against a configured root by
---PREFIX is actively dangerous, not just pointless: a buffer that itself
---lives under the configured root turns `https://github.com/x` into
---`$VAR/docs/https:/github.com/x` -- the known-dir prefix matches because
---the buffer's own path is in front, not because the URL has anything to do
---with it. Checked with `nil` opts (built-in schemes/TLDs only, regardless
---of the user's own `url.schemes`/`url.tlds`/`url.enable`): this is a
---defensive exclusion, not the url feature itself, so it stays maximally
---inclusive rather than following that config.
---@internal
---@param path string
---@return boolean
local function skip_relative_resolution(path)
  if path:match("^%a:[/\\]") or path:match("^[/\\]") or path:match("^~[/\\]?$") then return true end
  return URL.is_strict_url(path) or URL.is_loose_url(path)
end

---Every Markdown-link path span in `line` -- matches both `[text](path)` and
---`![alt](path)`, since both end in the same `](...)`. 1-indexed;
---`start_col`/`end_col` bound the path text itself, excluding `(`/`)`. Empty
---parens (`[x]()`) are skipped.
---@internal
---@param line string
---@return { start_col: integer, end_col: integer, path: string }[]
local function markdown_link_spans(line)
  local out = {}
  local init = 1
  while true do
    local s, e, path = line:find("%]%(([^%)]*)%)", init)
    if not s then break end
    if path ~= "" then out[#out + 1] = { start_col = s + 2, end_col = e - 1, path = path } end
    init = e + 1
  end
  return out
end

---Resolve `path` (assumed relative) against `bufdir`, and run `apply`
---(bound to one pairs list -- `M.shorten`'s or `M.shorten_known`'s) against
---the resulting absolute path. Returns the shortened form only when `apply`
---actually matched something in it (i.e. the resolved path falls under a
---configured root) -- nil when `path` is already absolute, `bufdir` is
---unknown (unnamed buffer), or the resolved path matches no configured root.
---@internal
---@param path string
---@param bufdir string
---@param apply fun(abs: string): string, integer
---@return string|nil
local function shorten_relative_candidate(path, bufdir, apply)
  if path == "" or bufdir == "" or skip_relative_resolution(path) then return nil end
  local abs = vim.fs.normalize(bufdir .. "/" .. path)
  local shortened, n = apply(abs)
  if n > 0 then return shortened end
  return nil
end

---Rewrite every Markdown-link path in `line` that is relative AND resolves
---(against `bufdir`) under a configured root, replacing just that path span
---with its shortened absolute form -- e.g. `![x](./assets/a.png)` in a file
---under `$NVIM_CONFIG_DIR/docs/x/` becomes
---`![x]($NVIM_CONFIG_DIR/docs/x/assets/a.png)`. An unrelated relative link,
---or one that is already absolute, is left untouched (the caller's own
---literal/structural pass handles an already-absolute one).
---@internal
---@param line string
---@param bufdir string
---@param apply fun(abs: string): string, integer
---@return string result
---@return integer replacements
local function shorten_markdown_links(line, bufdir, apply)
  local spans = markdown_link_spans(line)
  if #spans == 0 then return line, 0 end

  local out, count, last = {}, 0, 1
  for _, span in ipairs(spans) do
    local shortened = shorten_relative_candidate(span.path, bufdir, apply)
    if shortened then
      out[#out + 1] = line:sub(last, span.start_col - 1)
      out[#out + 1] = shortened
      last = span.end_col + 1
      count = count + 1
    end
  end
  out[#out + 1] = line:sub(last)
  return table.concat(out), count
end

-- ── Bare relative paths located under a root ────────────────────────────────

local uv = vim.uv or vim.loop

-- A path-ish token in running text: no spaces, no brackets/quotes/commas.
local TOKEN_CLASS = "[%w_%.%-%+@/\\]+"

---Search limits for `find_dir_under`, from `env_variable_resolution.root_search`.
---nil when the feature is switched off.
---@internal
---@return { max_depth: integer, max_dirs: integer, excluded: table<string, true> }|nil
local function root_search_opts()
  local cfg = require("gopath.config").get()
  local rs = (cfg.env_variable_resolution or {}).root_search
  if type(rs) == "table" and rs.enable == false then return nil end
  rs = type(rs) == "table" and rs or {}
  local excluded = {}
  for _, name in ipairs((cfg.truncated or {}).excluded_dirs or {}) do
    excluded[name:lower()] = true
  end
  return {
    max_depth = tonumber(rs.max_depth) or 3,
    max_dirs = tonumber(rs.max_dirs) or 4000,
    excluded = excluded,
  }
end

---Per-command search state: the resolved limits plus every directory listing
---read so far, so a line with several path tokens scans each directory once.
---@class GopathRootSearchCtx
---@field o? { max_depth: integer, max_dirs: integer, excluded: table<string, true> }|false  nil = not resolved yet, false = switched off
---@field listing table<string, { name: string, type: string|nil }[]|false>

---@internal
---@return GopathRootSearchCtx
local function new_search_ctx()
  return { o = nil, listing = {} }
end

---@internal
---@param ctx GopathRootSearchCtx
---@param dir string
---@return { name: string, type: string|nil }[]
local function list_dir(ctx, dir)
  local hit = ctx.listing[dir]
  if hit then return hit end
  local out = {}
  local handle = uv.fs_scandir(dir)
  while handle do
    local entry, etype = uv.fs_scandir_next(handle)
    if not entry then break end
    out[#out + 1] = { name = entry, type = etype }
  end
  ctx.listing[dir] = out
  return out
end

---Breadth-first search below `root` for a directory named `name` (compared
---case-insensitively) for which `accept(rel)` holds, `rel` being its path
---relative to `root` with `/` separators. Shallowest candidates are tried
---first, so `root/name` beats `root/x/y/name`. Directory symlinks are matched
---but never descended into (no cycles, no wandering off the root), neither is
---a dot directory (`.git`, `.venv`, `.claude/worktrees` -- full of copies of
---the very paths being looked up), and a directory is only scanned while the
---scan budget lasts.
---@internal
---@param root string  absolute directory, `/` separators, no trailing slash
---@param name string
---@param ctx GopathRootSearchCtx
---@param o { max_depth: integer, max_dirs: integer, excluded: table<string, true> }
---@param accept fun(rel: string): boolean
---@return string|nil rel
local function find_dir_under(root, name, ctx, o, accept)
  local lname = name:lower()
  local queue, head, scanned = { { rel = "", depth = 0 } }, 1, 0
  while head <= #queue and scanned < o.max_dirs do
    local item = queue[head]
    head = head + 1
    scanned = scanned + 1
    for _, e in ipairs(list_dir(ctx, item.rel == "" and root or (root .. "/" .. item.rel))) do
      local etype = e.type
      if etype == "directory" or etype == "link" or etype == "junction" then
        local rel = item.rel == "" and e.name or (item.rel .. "/" .. e.name)
        if e.name:lower() == lname then
          if accept(rel) then return rel end
        elseif etype == "directory" and item.depth + 1 < o.max_depth then
          if e.name:sub(1, 1) ~= "." and not o.excluded[e.name:lower()] then
            queue[#queue + 1] = { rel = rel, depth = item.depth + 1 }
          end
        end
      end
    end
  end
  return nil
end

---Locate a bare relative path (`first/rest`, e.g.
---`wkdbook-myplugins/casedesk.nvim/ROADMAP/ROADMAP.md`) below one of
---`roots`: the directory named by its first segment is searched for under
---each root (a few levels deep -- the path was typically abbreviated from the
---middle), and the whole path must then exist. Existence is required on
---purpose: a short relative path like `src/main.lua` otherwise "matches" any
---unrelated `src` directory somewhere below a root.
---@internal
---@param tok string  relative path with at least one separator
---@param roots { var: string, dir: string }[]
---@param ctx GopathRootSearchCtx
---@return string|nil shortened  `$VAR/<found dir>/<rest>`, same separator style as `tok`
local function locate_under_roots(tok, roots, ctx)
  local first = tok:match("^([^/\\]+)")
  if not first or first == "." or first == ".." then return nil end
  -- A `..` anywhere would let the existence check below walk out of the root
  -- and report a file that is not under it at all.
  for seg in tok:gmatch("[^/\\]+") do
    if seg == ".." then return nil end
  end
  if ctx.o == nil then ctx.o = root_search_opts() or false end
  local o = ctx.o
  if not o then return nil end

  local rest = tok:sub(#first + 1)
  local rest_slash = rest:gsub("\\", "/")
  local sep = (tok:find("/", 1, true) or not tok:find("\\", 1, true)) and "/" or "\\"

  for _, root in ipairs(roots) do
    local dir = vim.fs.normalize(root.dir):gsub("/+$", "")
    if dir:match("^%a:$") then dir = dir .. "/" end -- a drive root: "E:" alone means "cwd on E:"
    if dir ~= "" and uv.fs_stat(dir) then
      local rel = find_dir_under(dir, first, ctx, o, function(candidate)
        return uv.fs_stat((dir:gsub("/$", "")) .. "/" .. candidate .. rest_slash) ~= nil
      end)
      if rel then return "$" .. root.var .. sep .. rel:gsub("/", sep) .. rest:gsub("[/\\]", sep) end
    end
  end
  return nil
end

---Shortened form of ONE bare relative path `tok`, or nil. Tried in order:
---(1) it exists relative to `bufdir` and that resolves under a configured
---root (`apply`) -- the actual file the writer meant; (2) it is found below a
---root by `locate_under_roots`. An absolute path, a URL, or anything starting
---with `./`/`../` is never a candidate.
---@internal
---@param tok string
---@param bufdir string
---@param apply fun(abs: string): string, integer
---@param roots { var: string, dir: string }[]
---@param ctx? GopathRootSearchCtx
---@return string|nil
local function shorten_bare_relative(tok, bufdir, apply, roots, ctx)
  if not tok:find("[/\\]") or skip_relative_resolution(tok) then return nil end
  -- A path that exists next to the buffer IS that file: either it falls under
  -- a root (rewritten from where it really is) or it does not, and then a
  -- same-named path somewhere below a root is a different file -- not a
  -- candidate.
  if bufdir ~= "" and uv.fs_stat(bufdir .. "/" .. (tok:gsub("\\", "/"))) then
    return shorten_relative_candidate(tok, bufdir, apply)
  end
  return locate_under_roots(tok, roots, ctx or new_search_ctx())
end

---Rewrite every bare relative path token in `line` that
---`shorten_bare_relative` can place under a root. Tokens that already start
---with `$`/`~`, follow a drive colon, or are a URL are left alone.
---@internal
---@param line string
---@param bufdir string
---@param apply fun(abs: string): string, integer
---@param roots { var: string, dir: string }[]
---@return string result
---@return integer replacements
local function shorten_bare_tokens(line, bufdir, apply, roots)
  if #roots == 0 then return line, 0 end
  local ctx = new_search_ctx()
  local out, count, last, init = {}, 0, 1, 1
  while true do
    local s, e = line:find(TOKEN_CLASS, init)
    if not s then break end
    init = e + 1
    local tok = line:sub(s, e):gsub("%.+$", "")
    local prev = s > 1 and line:sub(s - 1, s - 1) or ""
    if tok ~= "" and not prev:match("[:~%$]") then
      local replacement = shorten_bare_relative(tok, bufdir, apply, roots, ctx)
      if replacement then
        out[#out + 1] = line:sub(last, s - 1)
        out[#out + 1] = replacement
        last = s + #tok
        count = count + 1
      end
    end
  end
  out[#out + 1] = line:sub(last)
  return table.concat(out), count
end

-- ── Buffer-facing entry points ──────────────────────────────────────────────

---Replace the whole line at `row`, reporting the replacement count or why
---nothing changed.
---@internal
---@param row integer
---@param compute fun(line: string): string, integer
---@return nil
local function replace_line(row, compute)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local result, count = compute(line)

  if count == 0 then
    LOG.warn("nothing to shorten on this line")
    return
  end

  local ok = pcall(vim.api.nvim_buf_set_lines, 0, row - 1, row, false, { result })
  if not ok then
    LOG.warn("buffer is not modifiable — nothing was changed")
    return
  end
  LOG.info(string.format("shortened %d occurrence%s", count, count == 1 and "" or "s"))
end

---Replace just `line:sub(scol, ecol)` at `row` with `compute`'s result of
---that span, leaving the rest of the line untouched.
---@internal
---@param row integer
---@param scol integer
---@param ecol integer
---@param compute fun(span_text: string): string, integer
---@return nil
local function replace_span(row, scol, ecol, compute)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local before, target, after = line:sub(1, scol - 1), line:sub(scol, ecol), line:sub(ecol + 1)
  local result, count = compute(target)

  if count == 0 then
    LOG.warn("nothing to shorten in the selection")
    return
  end

  local ok =
    pcall(vim.api.nvim_buf_set_lines, 0, row - 1, row, false, { before .. result .. after })
  if not ok then
    LOG.warn("buffer is not modifiable — nothing was changed")
    return
  end
  LOG.info(string.format("shortened %d occurrence%s", count, count == 1 and "" or "s"))
end

---@internal
---@return { segment: string, var: string }[]
local function repos_dir_pairs()
  local cfg = require("gopath.config").get()
  local opt = cfg.env_variable_resolution
  local dirs = (opt and opt.shorten_dirs) or { repos = "REPOS_DIR" }
  local pairs_list = {}
  for segment, var_name in pairs(dirs) do
    pairs_list[#pairs_list + 1] = { segment = segment, var = var_name }
  end
  return pairs_list
end

---The `{var, dir}` roots for the structural repos map: `dir` is what the
---variable actually holds on THIS machine, so a variable that is not set
---here contributes no root (nothing to search under).
---@internal
---@param pairs_list { segment: string, var: string }[]
---@return { var: string, dir: string }[]
local function repos_dir_roots(pairs_list)
  local roots = {}
  for _, p in ipairs(pairs_list) do
    local dir = vim.env[p.var]
    if type(dir) == "string" and dir ~= "" then roots[#roots + 1] = { var = p.var, dir = dir } end
  end
  return roots
end

---@internal
---@return { var: string, dir: string }[]
local function known_dir_pairs()
  local cfg = require("gopath.config").get()
  local opt = cfg.env_variable_resolution
  local known = (opt and opt.shorten_known_dirs) or {}
  local pairs_list = {}
  for var_name, resolver in pairs(known) do
    local dir = KNOWN_DIRS.resolve(resolver)
    if dir then pairs_list[#pairs_list + 1] = { var = var_name, dir = dir } end
  end
  return pairs_list
end

---Apply `M.shorten` to the current line (or, with `opts.selection`, just the
---visually selected span of it -- `:'<,'>GopathToReposDir`) in place, using
---the configured `env_variable_resolution.shorten_dirs` map (default
---`{ repos = "REPOS_DIR" }`). A relative Markdown-link path that resolves
---under a configured root is rewritten too -- see the module doc.
---@param opts { selection?: boolean }|nil
---@return nil
function M.shorten_current_line(opts)
  opts = opts or {}
  local pairs_list = repos_dir_pairs()
  local apply = function(abs)
    return M.shorten(abs, pairs_list)
  end
  local roots = repos_dir_roots(pairs_list)

  if opts.selection then
    local span = SELECTION.span()
    if not span then
      LOG.warn("no (single-line) selection to shorten")
      return
    end
    replace_span(span.row, span.start_col, span.end_col, function(text)
      local literal, n = M.shorten(text, pairs_list)
      if n > 0 then return literal, n end
      local bufdir = vim.fn.expand("%:p:h")
      local relative = shorten_relative_candidate(text, bufdir, apply)
      if relative then return relative, 1 end
      local lead, core, trail = text:match("^(%s*)(.-)(%s*)$")
      local bare = shorten_bare_relative(core, bufdir, apply, roots)
      if bare then return lead .. bare .. trail, 1 end
      return text, 0
    end)
    return
  end

  local bufdir = vim.fn.expand("%:p:h")
  replace_line(vim.api.nvim_win_get_cursor(0)[1], function(line)
    local after_md, n_md = shorten_markdown_links(line, bufdir, apply)
    local after_lit, n_lit = M.shorten(after_md, pairs_list)
    local result, n_bare = shorten_bare_tokens(after_lit, bufdir, apply, roots)
    return result, n_md + n_lit + n_bare
  end)
end

---Apply `M.shorten_known` to the current line (or, with `opts.selection`,
---just the visually selected span -- `:'<,'>GopathToNvimDir`) in place,
---using the configured `env_variable_resolution.shorten_known_dirs` map
---(default includes `NVIM_CONFIG_DIR = vim.fn.stdpath("config")`). A
---relative Markdown-link path that resolves under a configured root is
---rewritten too -- see the module doc.
---@param opts { selection?: boolean }|nil
---@return nil
function M.shorten_current_line_known(opts)
  opts = opts or {}
  local pairs_list = known_dir_pairs()
  if #pairs_list == 0 then
    LOG.warn("no known directories configured (env_variable_resolution.shorten_known_dirs)")
    return
  end
  local apply = function(abs)
    return M.shorten_known(abs, pairs_list)
  end

  if opts.selection then
    local span = SELECTION.span()
    if not span then
      LOG.warn("no (single-line) selection to shorten")
      return
    end
    replace_span(span.row, span.start_col, span.end_col, function(text)
      local literal, n = M.shorten_known(text, pairs_list)
      if n > 0 then return literal, n end
      local bufdir = vim.fn.expand("%:p:h")
      local relative = shorten_relative_candidate(text, bufdir, apply)
      if relative then return relative, 1 end
      local lead, core, trail = text:match("^(%s*)(.-)(%s*)$")
      local bare = shorten_bare_relative(core, bufdir, apply, pairs_list)
      if bare then return lead .. bare .. trail, 1 end
      return text, 0
    end)
    return
  end

  local bufdir = vim.fn.expand("%:p:h")
  replace_line(vim.api.nvim_win_get_cursor(0)[1], function(line)
    local after_md, n_md = shorten_markdown_links(line, bufdir, apply)
    local after_lit, n_lit = M.shorten_known(after_md, pairs_list)
    local result, n_bare = shorten_bare_tokens(after_lit, bufdir, apply, pairs_list)
    return result, n_md + n_lit + n_bare
  end)
end

---Shorten ONE absolute path to its `$VAR` form: the same two passes the
---`:Gopath to-nvim-dir` / `:Gopath to-repos-dir` commands apply to a buffer
---line, for a caller that holds the path as a string (images.nvim's
---`:Image paste env` builds its link path this way). The literal well-known
---directories (`shorten_known_dirs`, default `NVIM_CONFIG_DIR`) are tried
---first -- they name one exact machine-local directory, so they are the more
---specific claim -- then the structural repos root (`shorten_dirs`, default
---`REPOS_DIR`). Separators are normalized to `/` first. A relative path, a
---URL, or a path under no configured root yields nil: nothing to shorten.
---@param abs string An absolute file-system path (either slash style)
---@return string|nil shortened `$VAR/rest`, or nil when no configured root matches
---@return string|nil var The variable name used (e.g. "REPOS_DIR"), when shortened
function M.shorten_path(abs)
  if type(abs) ~= "string" or abs == "" then return nil, nil end
  local path = (abs:gsub("\\", "/"))
  if not (path:match("^%a:/") or path:match("^/") or path:match("^~/")) then return nil, nil end

  local known = known_dir_pairs()
  if #known > 0 then
    local out, n = M.shorten_known(path, known)
    if n > 0 then return out, out:match("^%$([%w_]+)") end
  end

  local out, n = M.shorten(path, repos_dir_pairs())
  if n > 0 then return out, out:match("^%$([%w_]+)") end
  return nil, nil
end

return M
