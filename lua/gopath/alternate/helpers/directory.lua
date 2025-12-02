---@module 'gopath.alternate.helpers.directory'
---@description Directory manipulation utilities for alternate resolution.

local M = {}

local uv = vim.loop

---Check if a path exists as a directory.
---@param path string
---@return boolean exists
function M.is_directory(path)
	if type(path) ~= "string" or path == "" then
		return false
	end

	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "directory"
end

---Extract directory path from a full file path.
---Handles both Unix and Windows path separators.
---@param filepath string
---@return string|nil dir_path
function M.extract_directory(filepath)
	if not filepath or filepath == "" then
		return nil
	end

	-- Normalize to absolute path first
	local abs = vim.fn.fnamemodify(filepath, ":p")

	-- Get directory component
	local dir = vim.fn.fnamemodify(abs, ":h")

	if dir and dir ~= "" and M.is_directory(dir) then
		return dir
	end

	return nil
end

---Extract filename from a full file path.
---@param filepath string
---@return string|nil filename
function M.extract_filename(filepath)
	if not filepath or filepath == "" then
		return nil
	end

	return vim.fn.fnamemodify(filepath, ":t")
end

---Scan directory and return all regular files.
---@param dir_path string
---@return string[]|nil files List of absolute file paths, or nil on error
function M.scan_directory(dir_path)
	---@diagnostic disable-next-line lib.uv
	local handle, err = uv.fs_scandir(dir_path)
	if not handle then
		return nil
	end

	local files = {}
	while true do
		---@diagnostic disable-next-line lib.uv
		local name, type = uv.fs_scandir_next(handle)
		if not name then
			break
		end

		-- Only include regular files
		if type == "file" then
			local full_path = dir_path .. "/" .. name
			table.insert(files, full_path)
		end
	end

	return files
end

return M
