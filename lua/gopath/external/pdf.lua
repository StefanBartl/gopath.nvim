---@module 'gopath.external.pdf'
---@brief Choose how to open a PDF: system app or one of pdfport.nvim's renderers.
---@description
--- Without pdfport.nvim installed, a PDF goes straight to the system viewer —
--- exactly as before, no dialog, no behaviour change.
---
--- With pdfport.nvim present, gopath offers the choice instead. "System app" is
--- deliberately the FIRST entry: reading the PDF inside Neovim is the common
--- case, handing it to the OS viewer is the exception — and an exception should
--- still be one keystroke away.
---
--- "System app" is routed through gopath's own opener (`gopath.external`), not
--- through pdfport's `system` renderer. Same result, but it keeps the exception
--- path on the code that already handles open.nvim delegation and WSL path
--- translation, so it behaves identically whether or not pdfport is installed.
---
--- Config (`external.pdf`):
---   picker  = true      show the chooser; false → always use `default`
---   default = "system"  mode used when the picker is off (or list is empty)

local LOG = require("gopath.util.log")

local M = {}

---Chooser entries, in display order. "system" first — see module docs.
---`GopathPdfMode` is declared in `gopath.@types.config`.
---@type { label: string, mode: GopathPdfMode }[]
local CHOICES = {
  { label = "System app", mode = "system" },
  { label = "Buffer", mode = "buffer" },
  { label = "Float", mode = "float" },
  { label = "Terminal", mode = "terminal" },
}

---@param path string
---@return boolean
function M.is_pdf(path)
  if type(path) ~= "string" or path == "" then return false end
  return vim.fn.fnamemodify(path, ":e"):lower() == "pdf"
end

---Whether pdfport.nvim is installed (soft dependency).
---Not a setup() check: pdfport's own `open()` calls `setup()` on demand.
---@return boolean
function M.available()
  local ok, pdfport = pcall(require, "pdfport")
  return ok and type(pdfport) == "table" and type(pdfport.open) == "function"
end

---@return { picker: boolean, default: GopathPdfMode }
local function pdf_config()
  local ext = require("gopath.config").get().external or {}
  local cfg = ext.pdf or {}
  return {
    picker = cfg.picker ~= false,
    default = cfg.default or "system",
  }
end

---Open `path` in the given mode.
---@param mode GopathPdfMode
---@param path string
---@return nil
local function dispatch(mode, path)
  if mode == "system" then
    require("gopath.external").open(path)
    return
  end

  local ok, pdfport = pcall(require, "pdfport")
  if not ok or type(pdfport.open) ~= "function" then
    LOG.warn("pdfport.nvim unavailable — opening in system app instead")
    require("gopath.external").open(path)
    return
  end

  local ok_open, err = pcall(pdfport.open, { path = path, mode = mode })
  if not ok_open then
    LOG.error("pdfport failed: " .. tostring(err) .. " — falling back to system app")
    require("gopath.external").open(path)
  end
end

---Handle a PDF, offering the mode chooser when pdfport.nvim is available.
---@param path string
---@return boolean handled  false → caller should fall back to the system opener
function M.try_open(path)
  if not M.is_pdf(path) then return false end
  if not M.available() then return false end

  local cfg = pdf_config()
  if not cfg.picker then
    dispatch(cfg.default, path)
    return true
  end

  local ok_kit, kit = pcall(require, "lib.nvim.ui.kit")
  if not ok_kit or type(kit.select) ~= "function" then
    -- lib.nvim missing: don't silently pick a mode for the user, just keep the
    -- pre-pdfport behaviour.
    return false
  end

  kit.select({
    items = CHOICES,
    title = "Open PDF: " .. vim.fn.fnamemodify(path, ":t"),
    format_item = function(item)
      return item.label
    end,
    on_select = function(item)
      dispatch(item.mode, path)
    end,
    -- Cancelling means "never mind" — opening it anyway would defeat the point.
    on_cancel = function() end,
  })

  return true
end

return M
