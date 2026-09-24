---@module 'gopath.integrations.menu'
---@brief Context-aware "Paths" menu entry for a host's global right-click menu.
---@description
--- gopath.nvim does not depend on a menu plugin. It *provides* a list of
--- entries in the shape `ui.contextmenu` (ui.nvim, soft dependency) expects,
--- and a host -- typically the user's own RightMouse dispatcher -- composes
--- them into its own menu for the current buffer:
--- >
---   local items = require("gopath.integrations.menu").items()
---   -- prepend/append `items` to your own menu table, then menu.open(composed)
--- <
--- Same "Pattern-B" shape as `open.integrations.menu` (`items`/`submenu`, no
--- trigger, no hard renderer dependency) and `filetree.integrations.menu`.
---
--- Resolves whatever gopath would resolve right here:
---   - Still in Visual mode when this runs (a right-click while a selection
---     is up, before any <Esc>): the selected text, via
---     `gopath.resolve_selection` -- a `$VAR/rest` reference or a URL, which
---     is what lets a PARTIALLY selected one resolve here too, not just a
---     fully recognized path (tailsearch's filesystem suffix search is
---     deliberately NOT tried here: it is what `:GopathProbe` is for, and a
---     menu entry that silently kicks off a filesystem walk on every
---     right-click would be a bad trade for the common "nothing matched"
---     case).
---   - Otherwise: the normal cursor-based pipeline
---     (`gopath.resolve.resolve_at_cursor`) -- help/url/env/language
---     resolvers, a free-text path, a Markdown link, anything `gF` would
---     find.
---
--- Self-gating: an empty list / nil submenu when ui.nvim is absent, or
--- nothing resolves under the cursor/selection -- so a host can safely
--- `vim.list_extend` `M.items()` unconditionally, or skip the fly-out
--- entirely when `M.submenu()` returns nil.

local M = {}

---@internal
---Lazily load ui.contextmenu. This module is itself opt-in (never required
---by `gopath.setup()`); without ui.nvim there is nothing to build entries
---with, not a hard error.
---@return table|nil
local function contextmenu()
  local ok, mod = pcall(require, "ui.contextmenu")
  return ok and mod or nil
end

---The live visual selection, as plain text -- `vim.fn.getpos("v")` (the
---selection's other end) to `vim.fn.getpos(".")` (the cursor), NOT the `'<`/
---`'>` marks: those persist long after Visual mode ends and cannot tell a
---live selection from a stale one (the exact ambiguity
---`gopath.commands.probe_selection` needs an explicit `opts.selection` flag
---to work around). Checking `vim.fn.mode()` fresh, right here, is what lets
---this module tell the difference on its own -- multi-line selections are
---deliberately not supported: a right-click menu is about "this one thing
---under/around the pointer", not a multi-line span.
---@internal
---@return string|nil
local function live_selection_text()
  local m = vim.fn.mode()
  if m ~= "v" and m ~= "V" and m ~= "\22" then return nil end

  local ok_v, spos = pcall(vim.fn.getpos, "v")
  local ok_c, cpos = pcall(vim.fn.getpos, ".")
  if not (ok_v and ok_c) then return nil end
  if spos[2] ~= cpos[2] then return nil end -- multi-line: not handled here

  local line = vim.api.nvim_get_current_line()
  local scol, ecol = spos[3], cpos[3]
  if ecol < scol then
    scol, ecol = ecol, scol
  end
  local text = line:sub(scol, ecol):gsub("^%s+", ""):gsub("%s+$", "")
  return text ~= "" and text or nil
end

---What a right-click here would act on.
---@internal
---@return GopathResult|nil
local function resolve_here()
  local sel = live_selection_text()
  if sel then
    local direct = require("gopath.resolve_selection").resolve_text(sel)
    if direct then return direct end
  end

  local ok, res = pcall(require("gopath.resolve").resolve_at_cursor, {})
  return ok and res or nil
end

---Build the gopath menu entries for the current cursor/selection context.
---Returns an empty list when ui.nvim is not installed or nothing resolves.
---@param _opts? table  reserved for future use
---@return table[]  ui.contextmenu entry list (possibly empty)
function M.items(_opts)
  local cm = contextmenu()
  if not cm then return {} end

  local res = resolve_here()
  if not res then return {} end

  local commands = require("gopath.commands")
  local can_reveal = res.kind == "file"

  local out = {}
  cm.group(
    out,
    cm.entry(true, "  Open", function()
      commands.open_result(res, "edit")
    end),
    cm.entry(can_reveal, "  Reveal in File Manager", function()
      commands.open_result(res, "explorer")
    end),
    cm.entry(can_reveal, "  Reveal in filetree.nvim", function()
      commands.open_result(res, "filetree")
    end)
  )
  return out
end

---Convenience: the gopath entries wrapped as a single nested submenu entry,
---for hosts that prefer a "Paths ▸" fly-out instead of inline entries.
---Returns nil when there is nothing to show (including when ui.nvim is not
---installed, or nothing resolves).
---@param label? string  submenu label (default "  Paths")
---@return table|nil
function M.submenu(label)
  local cm = contextmenu()
  if not cm then return nil end
  local items = M.items()
  if #items == 0 then return nil end
  return cm.submenu(label or "  Paths", items)
end

return M
