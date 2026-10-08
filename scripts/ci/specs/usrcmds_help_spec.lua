-- scripts/ci/specs/usrcmds_help_spec.lua
-- Every positional argument of `:Gopath` has a line in lib.nvim's option float.
--
-- The text comes from the `desc` / `enum_desc` of each ArgSpec in gopath.bindings.usrcmds (`open
-- [mode]` and `probe [mode]`); `cache add-root <dir>` takes a built-in DIR, which explains itself.
-- `:Gopath` has no flags or key=value pairs. An argument without a text shows up as a bare row in
-- the cheatsheet, so this fails until it is described.

---@param H table
return function(H)
  local composer = require("lib.nvim.bindings.usercmd.composer")

  -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
  -- feature of the dependency, not a defect of this plugin.
  if type(composer.help.undocumented) ~= "function" then return end

  ---@return table[] routes
  local function routes()
    local handle = composer.registry().Gopath
    H.truthy(handle, ":Gopath is registered through the composer")
    return handle:spec().routes
  end

  H.check("no flag, key=value pair or positional argument of :Gopath lacks a text", function()
    -- `truncated.enable` registers the `cache ...` routes too.
    local cfg = vim.deepcopy(require("gopath.config").get())
    cfg.truncated = vim.tbl_extend("force", cfg.truncated or {}, { enable = true })
    require("gopath.bindings.usrcmds").setup(cfg)
    routes()

    local missing = {}
    for _, m in ipairs(composer.help.undocumented("Gopath", { args = true })) do
      missing[#missing + 1] = ("%s %s %s"):format(m.kind, m.route, m.name)
    end
    H.eq(#missing, 0, ":Gopath entries without a help text: " .. table.concat(missing, ", "))
  end)

  H.check("the argument texts are one line, without a trailing period, <= 80 characters", function()
    local seen, malformed, stray = 0, {}, {}
    for _, route in ipairs(routes()) do
      for _, arg in ipairs(route.args or {}) do
        local offered = {}
        for _, value in ipairs(arg.enum or arg.values or {}) do
          offered[value] = true
        end
        local texts = { arg.desc }
        for value, text in pairs(arg.enum_desc or {}) do
          texts[#texts + 1] = text
          if not offered[value] then stray[#stray + 1] = arg.name .. "=" .. value end
        end
        for _, text in ipairs(texts) do
          seen = seen + 1
          if text:find("\n", 1, true) or text:sub(-1) == "." or #text > 80 then
            malformed[#malformed + 1] = text
          end
        end
      end
    end
    H.truthy(seen >= 6, "the texts of open [mode] and probe [mode] were found")
    H.eq(#malformed, 0, "malformed texts: " .. table.concat(malformed, " | "))
    H.eq(#stray, 0, "enum_desc keys that are no value: " .. table.concat(stray, ", "))
  end)
end
