---@module 'gopath.alternate.helpers.matcher'
---@description Fuzzy string matching utilities using Levenshtein distance.

local M = {}

---Calculate Levenshtein distance between two strings (character-level edit distance).
---@param s1 string
---@param s2 string
---@return integer distance
local function levenshtein_distance(s1, s2)
	local len1, len2 = #s1, #s2

	if len1 == 0 then
		return len2
	end
	if len2 == 0 then
		return len1
	end

	-- Create distance matrix
	local matrix = {}
	for i = 0, len1 do
		matrix[i] = { [0] = i }
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end

	-- Fill matrix with edit distances
	for i = 1, len1 do
		for j = 1, len2 do
			local cost = (s1:sub(i, i) == s2:sub(j, j)) and 0 or 1
			matrix[i][j] = math.min(
				matrix[i - 1][j] + 1, -- deletion
				matrix[i][j - 1] + 1, -- insertion
				matrix[i - 1][j - 1] + cost -- substitution
			)
		end
	end

	return matrix[len1][len2]
end

---Calculate similarity percentage between two strings (0-100).
---Uses Levenshtein distance normalized by the longer string length.
---@param s1 string
---@param s2 string
---@return number similarity Percentage (0-100)
function M.calculate_similarity(s1, s2)
	if s1 == s2 then
		return 100
	end

	local distance = levenshtein_distance(s1:lower(), s2:lower())
	local max_len = math.max(#s1, #s2)

	if max_len == 0 then
		return 100
	end

	local similarity = (1 - (distance / max_len)) * 100
	return math.max(0, similarity)
end

---Find files in directory that match the target filename with similarity >= threshold.
---@param dir_path string
---@param target_filename string
---@param threshold number Similarity threshold (0-100)
---@return table[] matches List of {path: string, similarity: number, filename: string}, sorted by similarity desc
function M.find_similar_files(dir_path, target_filename, threshold)
	local dir_helper = require("gopath.alternate.helpers.directory")
	local all_files = dir_helper.scan_directory(dir_path)

	if not all_files or #all_files == 0 then
		return {}
	end

	local matches = {}
	for _, filepath in ipairs(all_files) do
		local filename = dir_helper.extract_filename(filepath)
		if filename then
			local similarity = M.calculate_similarity(target_filename, filename)
			if similarity >= threshold then
				table.insert(matches, {
					path = filepath,
					similarity = similarity,
					filename = filename,
				})
			end
		end
	end

	-- Sort by similarity descending
	table.sort(matches, function(a, b)
		return a.similarity > b.similarity
	end)

	return matches
end

return M
