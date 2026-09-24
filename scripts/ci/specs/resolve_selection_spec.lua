-- scripts/ci/specs/resolve_selection_spec.lua
-- gopath.resolve_selection: direct (non-cursor, non-tailsearch) resolution
-- of a raw piece of text -- what lets `gopath.commands.probe_selection`
-- resolve a PARTIAL visual selection of a $VAR/rest reference or a URL, not
-- just a partial selection of a plain file path (tailsearch's job).

---@param H table
return function(H)
  local RS = require("gopath.resolve_selection")

  H.check("resolve_text: a strict URL (explicit scheme)", function()
    local r = RS.resolve_text("https://example.com/x")
    H.truthy(r)
    H.eq(r.kind, "url")
    H.eq(r.path, "https://example.com/x")
    H.eq(r.exists, true)
    H.eq(r.confidence, 0.95)
  end)

  H.check("resolve_text: a loose/bare-host URL", function()
    local r = RS.resolve_text("github.com/neovim/neovim")
    H.truthy(r)
    H.eq(r.kind, "url")
    H.eq(r.path, "https://github.com/neovim/neovim")
    H.eq(r.confidence, 0.7, "lower confidence than a strict match")
  end)

  H.check("resolve_text: url.enable = false switches both passes off", function()
    H.config_sandbox(function(c)
      c.setup({ url = { enable = false } })
      H.is_nil(RS.resolve_text("https://example.com/x"))
      H.is_nil(RS.resolve_text("github.com/neovim/neovim"))
    end)
  end)

  H.check("resolve_text: bare_hosts = false keeps the strict pass working", function()
    H.config_sandbox(function(c)
      c.setup({ url = { bare_hosts = false } })
      H.truthy(RS.resolve_text("https://example.com/x"), "strict still resolves")
      H.is_nil(RS.resolve_text("github.com/neovim/neovim"), "loose is switched off")
    end)
  end)

  H.check("resolve_text: a $VAR reference, via env_path.resolve_text", function()
    H.config_sandbox(function()
      local dir = H.tmpdir()
      H.write(dir .. "/x.lua", { "" })
      vim.env.GOPATH_SPEC_RS = dir
      local r = RS.resolve_text("$GOPATH_SPEC_RS/x.lua")
      H.truthy(r)
      H.eq(r.kind, "file")
      H.eq(r.exists, true)
      vim.env.GOPATH_SPEC_RS = nil
    end)
  end)

  H.check("resolve_text: env_variable_resolution.enable = false switches it off", function()
    H.config_sandbox(function(c)
      vim.env.GOPATH_SPEC_RS = H.tmpdir()
      c.setup({ env_variable_resolution = { enable = false } })
      H.is_nil(RS.resolve_text("$GOPATH_SPEC_RS/x.lua"))
      vim.env.GOPATH_SPEC_RS = nil
    end)
  end)

  H.check("resolve_text: neither a URL nor a $VAR reference resolves to nil", function()
    H.is_nil(RS.resolve_text("lua/gopath/init.lua"))
    H.is_nil(RS.resolve_text("just some words"))
  end)

  H.check("resolve_text: a non-string or empty string is nil, never an error", function()
    ---@diagnostic disable-next-line: param-type-mismatch
    H.is_nil(RS.resolve_text(nil))
    H.is_nil(RS.resolve_text(""))
  end)

  H.check("resolve_text: a URL wins over an env-var-shaped prefix when both could apply", function()
    -- "$" isn't a URL scheme character, so this is really just confirming URL
    -- is tried first without a $VAR text accidentally shadowing a real URL.
    local r = RS.resolve_text("https://example.com/$notavar")
    H.truthy(r)
    H.eq(r.kind, "url")
  end)
end
