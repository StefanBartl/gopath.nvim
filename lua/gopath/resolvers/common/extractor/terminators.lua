---@module 'gopath.resolvers.common.extractor.terminators'
---@brief Characters that terminate path expansion left/right.

---@type table<string,boolean>
return {
  [" "]  = true,
  ["\t"] = true,
  ["("]  = true,
  [")"]  = true,
  ["<"]  = true,
  [">"]  = true,
  ['"']  = true,
  ["'"]  = true,
  [","]  = true,
  [";"]  = true,
  ["|"]  = true,
  ["`"]  = true,
}
