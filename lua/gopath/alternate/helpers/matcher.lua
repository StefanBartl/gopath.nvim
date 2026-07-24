---@module 'gopath.alternate.helpers.matcher'
---@description Fuzzy string matching utilities using Levenshtein distance.

local M = {}

---Calculate similarity percentage between two strings (0-100), case-
---insensitive. Delegates to lib.lua.strings.distance.similarity (which
---returns a [0,1] scale, case-sensitive) for the underlying Levenshtein
---distance + normalization.
---@param s1 string
---@param s2 string
---@return number similarity Percentage (0-100)
function M.calculate_similarity(s1, s2)
  if s1 == s2 then return 100 end

  return require("lib.lua.strings.distance").similarity(s1:lower(), s2:lower()) * 100
end

---Find files in directory that match the target filename with similarity >= threshold.
---@param dir_path string
---@param target_filename string
---@param threshold number Similarity threshold (0-100)
---@return table[] matches List of {path: string, similarity: number, filename: string}, sorted by similarity desc
function M.find_similar_files(dir_path, target_filename, threshold)
  local dir_helper = require("gopath.alternate.helpers.directory")
  local all_files = dir_helper.scan_directory(dir_path)

  if not all_files or #all_files == 0 then return {} end

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
