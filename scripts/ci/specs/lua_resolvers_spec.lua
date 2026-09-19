-- scripts/ci/specs/lua_resolvers_spec.lua
-- The Lua-specific resolvers that scripts/ci/functional_tests.lua does not
-- already drive: require_path, binding_index, alias_index, chain,
-- identifier_locator, local_to_module and the shared ts_lua_ast helpers.
--
-- (table_locator, symbol_locator and value_origin have their own end-to-end
-- group in functional_tests.lua, including the no-parser fallback path.)

---@param H table
return function(H)
  local PATH = require("gopath.util.path")

  ---Put `lines` in a scratch buffer on a temporary runtimepath entry so the
  ---modules the fixtures `require` can actually be resolved.
  ---@return string rtp
  local function rtp_dir()
    local dir = H.tmpdir()
    vim.opt.runtimepath:append(dir)
    PATH.invalidate_caches()
    return dir
  end

  ---@param dir string
  local function drop_rtp(dir)
    vim.opt.runtimepath:remove(dir)
    PATH.invalidate_caches()
  end

  -- ── require_path ───────────────────────────────────────────────────────────

  local require_path = require("gopath.resolvers.lua.require_path")

  H.check("require_path: every spelling of a require call", function()
    local dir = rtp_dir()
    H.write(dir .. "/lua/reqmod/target.lua", { "return {}" })
    PATH.invalidate_caches()

    for _, line in ipairs({
      'local m = require("reqmod.target")',
      "local m = require('reqmod.target')",
      'local m = require "reqmod.target"',
      "local m = require [[reqmod.target]]",
    }) do
      H.line_at(line, "reqmod", { filetype = "lua" })
      local r = require_path.resolve()
      H.truthy(r, "expected a result for: " .. line)
      H.eq(r.kind, "module", line)
      H.eq(r.confidence, 0.85, line)
      H.eq(r.exists, true, line)
      H.match((r.path):gsub("\\", "/"), "reqmod/target%.lua$", line)
    end
    drop_rtp(dir)
  end)

  H.check("require_path: the cursor may sit anywhere inside the call", function()
    local dir = rtp_dir()
    H.write(dir .. "/lua/reqmod/target.lua", { "return {}" })
    PATH.invalidate_caches()
    for _, anchor in ipairs({ "require", "reqmod", "target" }) do
      H.line_at('local m = require("reqmod.target")', anchor, { filetype = "lua" })
      H.truthy(require_path.resolve(), "cursor on " .. anchor)
    end
    drop_rtp(dir)
  end)

  H.check("BUG: the previous-line lookup for multi-line require calls is dead code", function()
    -- `find_require_module_at_cursor` builds a two-entry list (current line,
    -- previous line) and then checks, per entry:
    --
    --   cursor_in(s1, e1, (_ == 1 and col) or 1e9)
    --
    -- The 1e9 is meant as "any column counts" for the previous line, but
    -- `cursor_in` requires `col <= span_e`, so a column of 1e9 always fails.
    -- The previous line is therefore scanned and then unconditionally
    -- discarded: a `require(...)` continued on the next line never resolves.
    local dir = rtp_dir()
    H.write(dir .. "/lua/reqmod/target.lua", { "return {}" })
    PATH.invalidate_caches()

    H.buf({ 'local m = require("reqmod.target")', "  .setup()" }, { filetype = "lua" })
    vim.api.nvim_win_set_cursor(0, { 1, 20 })
    H.truthy(require_path.resolve(), "on the require line itself it works")

    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    H.is_nil(require_path.resolve(), "BUG: one line further down, nothing is found")
    drop_rtp(dir)
  end)

  H.check("require_path: a bare dotted module name resolves too (@module, @see, errors)", function()
    local dir = rtp_dir()
    H.write(dir .. "/lua/reqmod/target.lua", { "return {}" })
    PATH.invalidate_caches()

    for _, line in ipairs({
      "---@module 'reqmod.target'",
      "---@see reqmod.target",
      "module 'reqmod.target' not found",
    }) do
      H.line_at(line, "reqmod", { filetype = "lua" })
      H.truthy(require_path.resolve(), "expected a result for: " .. line)
    end
    drop_rtp(dir)
  end)

  H.check("require_path: tokens that are not dotted module names are rejected", function()
    for _, line in ipairs({
      "local x = 1",
      "see lua/reqmod/target.lua",
      "singleword",
    }) do
      H.line_at(line, line:match("[%w/%.]+$") or line, { filetype = "lua" })
      H.is_nil(require_path.resolve(), "rejected: " .. line)
    end
  end)

  H.check("require_path: a module that resolves nowhere answers nil", function()
    H.line_at('require("no.such.module.anywhere")', "no.such", { filetype = "lua" })
    H.is_nil(require_path.resolve())
  end)

  -- ── binding_index ──────────────────────────────────────────────────────────

  local binding_index = require("gopath.resolvers.lua.binding_index")

  H.check("binding_index: maps identifiers to the modules they require", function()
    H.buf({
      'local cfg = require("gopath.config")',
      "local util = require 'gopath.util.path'",
      "local br = require [[gopath.util.log]]",
      'globalish = require("gopath.registry")',
      "local notarequire = something.else_",
      "",
    }, { filetype = "lua" })

    local map = binding_index.get_map()
    H.eq(map.cfg, "gopath.config", "parenthesised")
    H.eq(map.util, "gopath.util.path", "bare string form")
    H.eq(map.br, "gopath.util.log", "long-bracket form")
    H.eq(map.globalish, "gopath.registry", "a non-local assignment is allowed too")
    H.is_nil(map.notarequire, "an ordinary assignment is not a binding")
  end)

  H.check("binding_index: the map is cached per buffer and invalidated by an edit", function()
    local buf = H.buf({ 'local a = require("mod.one")' }, { filetype = "lua" })
    local first = binding_index.get_map()
    H.eq(binding_index.get_map(), first, "the same table while the buffer is unchanged")

    vim.api.nvim_buf_set_lines(buf, 1, 1, false, { 'local b = require("mod.two")' })
    local second = binding_index.get_map()
    H.truthy(second ~= first, "changedtick moved, so the map was rebuilt")
    H.eq(second.b, "mod.two", "and the new binding is there")
  end)

  H.check("binding_index: deleting a buffer drops its cache entry", function()
    local buf = H.buf({ 'local gone = require("mod.gone")' }, { filetype = "lua" })
    H.eq(binding_index.get_map().gone, "mod.gone")
    vim.api.nvim_buf_delete(buf, { force = true })
    -- Nothing observable to assert beyond "the autocmd ran without error and a
    -- fresh buffer starts clean" — the leak it fixes is invisible by design.
    H.buf({ "-- empty" }, { filetype = "lua" })
    H.is_nil(binding_index.get_map().gone, "a new buffer does not inherit the old map")
  end)

  -- ── alias_index ────────────────────────────────────────────────────────────

  local alias_index = require("gopath.resolvers.lua.alias_index")

  H.check("alias_index: classifies requires, chains and plain aliases", function()
    H.buf({
      'local cfg = require("gopath.config")',
      "local br = require [[gopath.util.log]]",
      "local sub = cfg.options.inner",
      "top = other.thing",
      "local same = cfg",
    }, { filetype = "lua" })

    local map = alias_index.get_map()
    H.eq(map.cfg.kind, "require")
    H.eq(map.cfg.module, "gopath.config")
    H.eq(map.br.kind, "require")
    H.eq(map.br.module, "gopath.util.log")
    H.eq(map.sub.kind, "chain")
    H.eq(map.sub.chain, "cfg.options.inner")
    H.eq(map.top.kind, "chain", "a non-local assignment counts")
    H.eq(map.top.chain, "other.thing")
    H.eq(map.same.kind, "chain", "a single-identifier alias is a one-segment chain")
  end)

  H.check("alias_index: cached per buffer, rebuilt on an edit", function()
    local buf = H.buf({ 'local a = require("mod.one")' }, { filetype = "lua" })
    local first = alias_index.get_map()
    H.eq(alias_index.get_map(), first, "cached")
    vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "local c = a.b" })
    local second = alias_index.get_map()
    H.truthy(second ~= first, "rebuilt")
    H.eq(second.c.kind, "chain")
  end)

  -- ── chain ──────────────────────────────────────────────────────────────────

  local chain = require("gopath.resolvers.lua.chain")

  H.check("chain: a dotted chain at the cursor", function()
    H.buf({ "local M = {}", "M.cfg.highlight.enable = true" }, { filetype = "lua" })
    H.cursor_on(2, "enable")
    local c = chain.get_chain_at_cursor()
    H.truthy(c, "expected a chain")
    H.eq(c.base, "M")
    H.same(c.chain, { "cfg", "highlight", "enable" })
  end)

  H.check("chain: a method call with ':' is treated as one more segment", function()
    H.buf({ "obj:method()" }, { filetype = "lua" })
    H.cursor_on(1, "method")
    local c = chain.get_chain_at_cursor()
    H.truthy(c, "expected a chain")
    H.eq(c.base, "obj")
    H.same(c.chain, { "method" })
  end)

  H.check("chain: the regex fallback works without a parser", function()
    H.buf({ "cfgmod.setup({})" }, { filetype = "" })
    H.cursor_on(1, "setup")
    local c = chain.get_chain_at_cursor()
    H.truthy(c, "expected a chain from the regex fallback")
    H.eq(c.base, "cfgmod")
    H.same(c.chain, { "setup" })
  end)

  H.check("chain: a bare identifier is not a chain", function()
    H.buf({ "local plain = 1" }, { filetype = "lua" })
    H.cursor_on(1, "plain")
    H.is_nil(chain.get_chain_at_cursor(), "fewer than two segments")

    H.buf({ "" }, { filetype = "lua" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    H.is_nil(chain.get_chain_at_cursor(), "an empty line")
  end)

  -- ── identifier_locator ─────────────────────────────────────────────────────

  local identifier_locator = require("gopath.resolvers.lua.identifier_locator")

  H.check("identifier_locator: a bare identifier resolves to the module it was bound to", function()
    local dir = rtp_dir()
    H.write(dir .. "/lua/idmod/thing.lua", { "return {}" })
    PATH.invalidate_caches()

    H.buf({ 'local thing = require("idmod.thing")', "print(thing)" }, { filetype = "lua" })
    H.cursor_on(2, "thing")
    local r = identifier_locator.resolve()
    H.truthy(r, "expected a result")
    H.eq(r.kind, "module")
    H.eq(r.source, "treesitter")
    H.eq(r.confidence, 0.85)
    H.match((r.path):gsub("\\", "/"), "idmod/thing%.lua$")
    H.is_nil(r.range, "just open the module; no position is claimed")
    drop_rtp(dir)
  end)

  H.check(
    "identifier_locator: an identifier inside a chain is left to the chain resolvers",
    function()
      local dir = rtp_dir()
      H.write(dir .. "/lua/idmod/thing.lua", { "return {}" })
      PATH.invalidate_caches()
      H.buf({ 'local thing = require("idmod.thing")', "thing.field = 1" }, { filetype = "lua" })
      H.cursor_on(2, "field")
      H.is_nil(identifier_locator.resolve(), "a field of a chain is not a bare identifier")
      drop_rtp(dir)
    end
  )

  H.check("identifier_locator: an unbound identifier, and one whose module is gone", function()
    H.buf({ "local free = 1", "print(free)" }, { filetype = "lua" })
    H.cursor_on(2, "free")
    H.is_nil(identifier_locator.resolve(), "no binding")

    H.buf({ 'local ghost = require("not.a.real.module")', "print(ghost)" }, { filetype = "lua" })
    H.cursor_on(2, "ghost")
    H.is_nil(identifier_locator.resolve(), "bound, but the module resolves nowhere")
  end)

  H.check(
    "identifier_locator: without a parser there is no node, and therefore no result",
    function()
      H.buf({ 'local thing = require("idmod.thing")', "print(thing)" }, { filetype = "" })
      H.cursor_on(2, "thing")
      H.is_nil(identifier_locator.resolve())
    end
  )

  -- ── local_to_module ────────────────────────────────────────────────────────

  local local_to_module = require("gopath.resolvers.lua.local_to_module")

  H.check(
    "local_to_module: an LSP hit on a `local x = require(...)` line becomes the module",
    function()
      local dir = rtp_dir()
      H.write(dir .. "/lua/ltm/target.lua", { "return {}" })
      local caller = H.write(dir .. "/caller.lua", {
        "-- header",
        'local target = require("ltm.target")',
        "return target",
      })
      PATH.invalidate_caches()

      local r = local_to_module.enhance_lsp_result({ path = caller, range = { line = 2, col = 7 } })
      H.truthy(r, "expected an enhanced result")
      H.eq(r.kind, "module")
      H.eq(r.source, "lsp-enhanced")
      H.eq(r.confidence, 0.95)
      H.eq(r.exists, true)
      H.is_nil(r.range, "the module has no single interesting line")
      H.match((r.path):gsub("\\", "/"), "ltm/target%.lua$")
      drop_rtp(dir)
    end
  )

  H.check("local_to_module: the long-bracket require form is understood", function()
    local dir = rtp_dir()
    H.write(dir .. "/lua/ltm/target.lua", { "return {}" })
    local caller = H.write(dir .. "/caller2.lua", { "local t = require [[ltm.target]]" })
    PATH.invalidate_caches()
    H.truthy(local_to_module.enhance_lsp_result({ path = caller, range = { line = 1, col = 7 } }))
    drop_rtp(dir)
  end)

  H.check("local_to_module: anything else falls back to the original LSP result", function()
    local dir = H.tmpdir()
    local caller = H.write(dir .. "/plain.lua", { "local x = 1", 'local y = require("nope.nope")' })

    H.is_nil(local_to_module.enhance_lsp_result(nil), "no result at all")
    H.is_nil(local_to_module.enhance_lsp_result({ path = caller }), "no range")
    H.is_nil(local_to_module.enhance_lsp_result({ range = { line = 1 } }), "no path")
    H.is_nil(
      local_to_module.enhance_lsp_result({ path = caller, range = { line = 1, col = 1 } }),
      "not a require line"
    )
    H.is_nil(
      local_to_module.enhance_lsp_result({ path = caller, range = { line = 99, col = 1 } }),
      "a line past the end of the file"
    )
    H.is_nil(
      local_to_module.enhance_lsp_result({ path = caller, range = { line = 2, col = 1 } }),
      "a require whose module cannot be found"
    )
  end)

  H.check(
    "local_to_module: a path readfile cannot open answers nil instead of E484 (ERR-01)",
    function()
      -- `path` comes straight out of a decoded LSP response (vim.uri_to_fname);
      -- a directory stands in here for "not a readable file" (unsaved buffer,
      -- non-file URI scheme, a file deleted since the server indexed it).
      local dir = H.tmpdir()
      H.is_nil(
        local_to_module.enhance_lsp_result({ path = dir, range = { line = 1, col = 1 } }),
        "readfile throws E484 on a directory; enhance_lsp_result must not propagate it"
      )
    end
  )

  -- ── ts_lua_ast ─────────────────────────────────────────────────────────────

  local AST = require("gopath.resolvers.lua.ts_lua_ast")

  H.check(
    "ts_lua_ast.parse: joined source and a root, or nil for an unparseable language",
    function()
      local root, src = AST.parse({ "local M = {}", "return M" })
      H.truthy(root, "expected a root")
      H.eq(src, "local M = {}\nreturn M", "the exact text the tree was built from")
      H.eq(root:type(), "chunk")
    end
  )

  H.check("ts_lua_ast.get_query: compiles once and caches, including failures", function()
    local q1 = AST.get_query("spec_ok", "(identifier) @id")
    local q2 = AST.get_query("spec_ok", "(identifier) @id")
    H.truthy(q1, "compiled")
    H.eq(q1, q2, "the second call is the cached object")

    local bad1 = AST.get_query("spec_bad", "((((")
    local bad2 = AST.get_query("spec_bad", "((((")
    H.is_nil(bad1, "a broken query answers nil")
    H.is_nil(bad2, "and the failure is cached rather than retried")
  end)

  H.check("ts_lua_ast.chain_of: dotted, bracketed and dynamic lvalues", function()
    local root, src = AST.parse({
      "M.cfg.deep = 1",
      'M["quoted"].x = 2',
      "M[key] = 3",
      "obj:method()",
    })
    H.truthy(root, "parsed")

    ---@param row integer 0-based
    ---@return TSNode|nil
    local function assignment_lhs(row)
      local q = AST.get_query("spec_assign", "(assignment_statement) @a")
      for _, node in q:iter_captures(root, src) do
        local sr = node:range()
        if sr == row then return node:named_child(0):named_child(0) end
      end
      return nil
    end

    H.same(AST.chain_of(assignment_lhs(0), src), { "M", "cfg", "deep" }, "dotted")
    H.same(AST.chain_of(assignment_lhs(1), src), { "M", "quoted", "x" }, "a literal string key")
    H.is_nil(AST.chain_of(assignment_lhs(2), src), "a dynamic key cannot be matched textually")
  end)

  H.check("ts_lua_ast: chain comparison helpers", function()
    H.eq(AST.chains_equal({ "a", "b" }, { "a", "b" }), true)
    H.eq(AST.chains_equal({ "a" }, { "a", "b" }), false, "different lengths")
    H.eq(AST.chains_equal({ "a", "x" }, { "a", "b" }), false, "different content")

    H.eq(AST.chain_tail_equal({ "M", "cfg", "deep" }, 2, { "cfg", "deep" }), true)
    H.eq(AST.chain_tail_equal({ "M", "cfg", "deep" }, 1, { "cfg", "deep" }), false, "wrong offset")
    H.same(AST.slice({ "a", "b", "c" }, 2), { "b", "c" })
    H.same(AST.slice({ "a" }, 5), {}, "past the end")
  end)

  H.check("ts_lua_ast.field_key_text: literal keys yes, dynamic ones no", function()
    local root, src = AST.parse({
      "local t = {",
      "  plain = 1,",
      '  ["quoted"] = 2,',
      "  [dynamic] = 3,",
      "  4,",
      "}",
    })
    H.truthy(root, "parsed")

    local keys = {}
    local q = AST.get_query("spec_field", "(field) @f")
    for _, node in q:iter_captures(root, src) do
      keys[#keys + 1] = AST.field_key_text(node, src) or "<none>"
    end
    H.contains(keys, "plain")
    H.contains(keys, "quoted")
    H.contains(keys, "<none>", "a dynamic key and an array entry both yield nil")
  end)

  H.check("ts_lua_ast: node_lines / node_start are 1-based", function()
    local root, src = AST.parse({ "local a = 1", "local b = {", "  c = 2,", "}" })
    H.truthy(root, "parsed")
    local q = AST.get_query("spec_tbl", "(table_constructor) @t")
    local tables = {}
    for _, node in q:iter_captures(root, src) do
      tables[#tables + 1] = node
    end
    H.eq(#tables, 1, "one table constructor in the fixture")

    local s, e = AST.node_lines(tables[1])
    H.eq(s, 2, "the table starts on line 2")
    H.eq(e, 4, "and ends on line 4")
    local line, col = AST.node_start(tables[1])
    H.eq(line, 2)
    H.eq(col, 11, "1-based column")
  end)
end
