{
  dir = vim.env.REPOS_DIR .. ""/gopath.nvim", -- or "wkdsteve/gopath.nvim"
  opts = {
    -- modes: "builtin" | "treesitter" | "lsp" | "hybrid"
    mode = "hybrid",
    order = { "lsp", "treesitter", "builtin" },
    lsp_timeout_ms = 200,
    languages = {
      lua = {
        enable = true,
        -- resolvers = nil --> use all resolvers for Lua by default
        -- resolvers = { "require_path", "binding_index", "chain", "symbol_locator" },
      },
    },
  },
  keys = {
    { "gP", function() require("gopath").commands.resolve_and_open("edit") end,   desc = "gopath: open here" },
    { "g|", function() require("gopath").commands.resolve_and_open("window") end, desc = "gopath: open in split" },
    { "g\\", function() vim.cmd("GopathOpen window_vsplit") end,                  desc = "gopath: open in vsplit" },
    { "g}", function() require("gopath").commands.resolve_and_open("tab") end,    desc = "gopath: open in tab" },
    { "gY", function() vim.cmd("GopathCopy") end,                                  desc = "gopath: copy path:line:col" },
    { "g?", function() vim.cmd("GopathDebugUnderCursor") end,                      desc = "gopath: debug under cursor" },
  },
  cmd = { "GopathResolve", "GopathOpen", "GopathCopy", "GopathDebugUnderCursor" },
}
