---@module 'gopath.external.helpers.detector'
---@description Detect files that should be opened with external applications.

local M = {}

---List of file extensions that should be opened externally (images, PDFs, etc.).
---@type string[]
local EXTERNAL_EXTENSIONS = {
  -- Images
  "png",
  "jpg",
  "jpeg",
  "gif",
  "bmp",
  "tiff",
  "tif",
  "webp",
  "ico",
  "svg",
  -- Documents
  "pdf",
  "doc",
  "docx",
  "xls",
  "xlsx",
  "ppt",
  "pptx",
  "odt",
  "ods",
  "odp",
  -- Archives
  "zip",
  "tar",
  "gz",
  "bz2",
  "7z",
  "rar",
  -- Media
  "mp3",
  "mp4",
  "avi",
  "mkv",
  "mov",
  "wmv",
  "flv",
  "wav",
  "ogg",
  -- Executables
  "exe",
  "dmg",
  "app",
}

---Check if a path is a URL.
---Delegates to `gopath.util.url`, the single source of truth shared with the
---URL resolver — the two must agree, or a token resolved as a URL would be
---routed back into the buffer-editing path here.
---Only the strict forms count: a bare host like "github.com/x" is a URL by
---intent, not by spelling, and the resolver decides that (late, after the file
---resolvers) rather than this extension-level check.
---@internal
---@param path string
---@return boolean is_url
local function is_url(path)
  if not path or path == "" then return false end
  return require("gopath.util.url").is_strict_url(path)
end

---Check if a file extension indicates an external file.
---@internal
---@param path string
---@param extra_extensions string[]|nil  user-configured additions (external.extensions)
---@return boolean is_external
local function has_external_extension(path, extra_extensions)
  if not path or path == "" then return false end

  local ext = vim.fn.fnamemodify(path, ":e"):lower()

  for _, external_ext in ipairs(EXTERNAL_EXTENSIONS) do
    if ext == external_ext then return true end
  end

  if extra_extensions then
    for _, external_ext in ipairs(extra_extensions) do
      if ext == external_ext:lower() then return true end
    end
  end

  return false
end

---The externally-openable extensions (without a leading dot), optionally
---extended by the user's `external.extensions`.
---
---Exposed so the line extractor can look for these too: a file gopath is able
---to *open* externally must also be one it can *find* in a line, or a Markdown
---link like `[report](docs/report.pdf)` is invisible to the whole resolver
---pipeline whenever the cursor isn't sitting directly on the path token. Single
---source of truth — the two lists must not drift apart.
---@param extra string[]|nil
---@return string[]
function M.extensions(extra)
  local out = {}
  for i, ext in ipairs(EXTERNAL_EXTENSIONS) do
    out[i] = ext
  end
  for _, ext in ipairs(extra or {}) do
    if type(ext) == "string" and ext ~= "" then out[#out + 1] = ext:lower() end
  end
  return out
end

---Check if a file or URL should be opened externally.
---@param path string File path or URL
---@param extra_extensions string[]|nil  extends the built-in extension list
---  (`config.external.extensions`); does not replace it.
---@return boolean is_external
function M.is_external_file(path, extra_extensions)
  return is_url(path) or has_external_extension(path, extra_extensions)
end

return M
