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
---@param path string
---@return boolean is_url
local function is_url(path)
	if not path or path == "" then
		return false
	end

	-- Match common URL schemes
	return path:match("^https?://") or path:match("^ftps?://") or path:match("^file://") or path:match("^www%.")
end

---Check if a file extension indicates an external file.
---@param path string
---@return boolean is_external
local function has_external_extension(path)
	if not path or path == "" then
		return false
	end

	local ext = vim.fn.fnamemodify(path, ":e"):lower()

	for _, external_ext in ipairs(EXTERNAL_EXTENSIONS) do
		if ext == external_ext then
			return true
		end
	end

	return false
end

---Check if a file or URL should be opened externally.
---@param path string File path or URL
---@return boolean is_external
function M.is_external_file(path)
	return is_url(path) or has_external_extension(path)
end

return M
