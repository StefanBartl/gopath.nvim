-- scripts/ci/specs/lang_resolvers_spec.lua
-- The eight language resolvers and the helper they all share.
--
-- Every case builds a real miniature project under vim.fn.tempname(), opens
-- the importing file as a buffer (the resolvers read `expand("%:p:h")` and the
-- cursor line) and asserts which file on disk came back. No LSP, no build
-- tool, no network.

---@param H table
return function(H)
  local helper = require("gopath.resolvers.common.lang_helper")

  ---Open `file` in a buffer, put the cursor on line `row`, and return the
  ---resolver's answer.
  ---@param resolver table
  ---@param file string
  ---@param row integer
  ---@param filetype string|nil
  ---@return table|nil
  local function resolve_in(resolver, file, row, filetype)
    vim.cmd.edit(vim.fn.fnameescape(file))
    if filetype then vim.bo.filetype = filetype end
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    return resolver.resolve()
  end

  ---@param res table|nil
  ---@param suffix string  Lua pattern the resolved path must end with
  ---@param msg string|nil
  local function resolved_to(res, suffix, msg)
    H.truthy(res, (msg or "resolution") .. ": expected a result")
    H.match((res.path):gsub("\\", "/"), suffix .. "$", msg or "resolved path")
    H.eq(res.exists, true, "a language resolver only ever returns files it found")
  end

  -- ── lang_helper ────────────────────────────────────────────────────────────

  H.check("lang_helper.first_existing: normalises before stat'ing", function()
    local dir = H.tmpdir()
    H.write(dir .. "/app/util.ts", { "" })
    local hit = helper.first_existing({ dir .. "/app/./util.ts" })
    H.truthy(hit, "the './' segment must not defeat fs_stat")
    H.match(hit:gsub("\\", "/"), "app/util%.ts$")

    H.truthy(helper.first_existing({ dir .. "/app/sub/../util.ts" }), "'..' resolves too")
    H.is_nil(helper.first_existing({ dir .. "/nope.ts", "" }), "misses and empties")
    H.is_nil(helper.first_existing({}), "no candidates")
  end)

  H.check("lang_helper.resolve_with_extensions: <base><ext> before <base>/index<ext>", function()
    local dir = H.tmpdir()
    H.write(dir .. "/mod.ts", { "" })
    H.write(dir .. "/mod/index.ts", { "" })
    local hit = helper.resolve_with_extensions(dir .. "/mod", { ".ts", ".js" }, { "index" })
    H.match(hit:gsub("\\", "/"), "/mod%.ts$", "the file wins over the directory")

    local only_index = H.tmpdir()
    H.write(only_index .. "/pkg/index.js", { "" })
    H.match(
      helper
        .resolve_with_extensions(only_index .. "/pkg", { ".ts", ".js" }, { "index" })
        :gsub("\\", "/"),
      "/pkg/index%.js$",
      "extension order is honoured inside the index probe too"
    )
    H.is_nil(helper.resolve_with_extensions(dir .. "/absent", { ".ts" }, nil), "no index names")
  end)

  H.check("lang_helper.find_root: walks upward, and answers nil for junk markers", function()
    local root = H.tmpdir()
    H.write(root .. "/marker.toml", { "" })
    H.write(root .. "/a/b/file.py", { "" })
    vim.cmd.edit(vim.fn.fnameescape(root .. "/a/b/file.py"))

    H.eq(
      (vim.fs.normalize(helper.find_root({ "marker.toml" }))),
      (vim.fs.normalize(root)),
      "found two levels up"
    )
    H.is_nil(helper.find_root({ "no_such_marker_file" }), "nothing matches")
    H.is_nil(helper.find_root({}), "an empty marker list")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.is_nil(helper.find_root("not a table"), "a non-table")
  end)

  H.check("lang_helper.make_result: defaults and explicit fields", function()
    local found = helper.make_result({ language = "lua", path = "/a.lua", exists = true })
    H.eq(found.kind, "module", "an existing target is a module")
    H.eq(found.confidence, 0.8)
    H.eq(found.source, "builtin")
    H.is_nil(found.range, "no line given")

    local missing = helper.make_result({ language = "go", path = "/a.go", exists = false })
    H.eq(missing.kind, "file", "a missing target is just a file")
    H.eq(missing.confidence, 0.3)

    local explicit = helper.make_result({
      language = "rust",
      path = "/a.rs",
      exists = true,
      kind = "symbol",
      line = 4,
      col = 2,
      confidence = 0.91,
      source = "custom",
    })
    H.eq(explicit.kind, "symbol")
    H.eq(explicit.confidence, 0.91)
    H.eq(explicit.source, "custom")
    H.same(explicit.range, { line = 4, col = 2 })
  end)

  -- ── Python ─────────────────────────────────────────────────────────────────

  local python = require("gopath.resolvers.python.import_path")

  H.check("python: `import a.b` resolves to a/b.py and to a/b/__init__.py", function()
    local root = H.tmpdir()
    H.write(root .. "/pyproject.toml", { "" })
    H.write(root .. "/pkg/mod.py", { "" })
    H.write(root .. "/pkg/sub/__init__.py", { "" })
    H.write(root .. "/main.py", { "import pkg.mod", "import pkg.sub", "import pkg.mod as m" })

    resolved_to(resolve_in(python, root .. "/main.py", 1, "python"), "pkg/mod%.py", "module file")
    resolved_to(
      resolve_in(python, root .. "/main.py", 2, "python"),
      "pkg/sub/__init__%.py",
      "package"
    )
    resolved_to(
      resolve_in(python, root .. "/main.py", 3, "python"),
      "pkg/mod%.py",
      "aliased import"
    )
  end)

  H.check("python: `from a.b import c` prefers the module, then the submodule", function()
    local root = H.tmpdir()
    H.write(root .. "/setup.py", { "" })
    H.write(root .. "/pkg/mod.py", { "" })
    H.write(root .. "/pkg/deep/sub.py", { "" })
    H.write(root .. "/main.py", { "from pkg.mod import thing", "from pkg.deep import sub" })

    resolved_to(
      resolve_in(python, root .. "/main.py", 1, "python"),
      "pkg/mod%.py",
      "the module itself"
    )
    resolved_to(
      resolve_in(python, root .. "/main.py", 2, "python"),
      "pkg/deep/sub%.py",
      "the imported name is a submodule"
    )
  end)

  H.check("python: relative imports climb one package per extra dot", function()
    local root = H.tmpdir()
    H.write(root .. "/requirements.txt", { "" })
    H.write(root .. "/pkg/__init__.py", { "" })
    H.write(root .. "/pkg/sibling.py", { "" })
    H.write(root .. "/pkg/inner/__init__.py", { "" })
    H.write(root .. "/pkg/inner/me.py", {
      "from . import anything",
      "from .. import anything",
      "from ..sibling import thing",
    })

    resolved_to(
      resolve_in(python, root .. "/pkg/inner/me.py", 1, "python"),
      "pkg/inner/__init__%.py",
      "one dot is the current package"
    )
    resolved_to(
      resolve_in(python, root .. "/pkg/inner/me.py", 2, "python"),
      "pkg/__init__%.py",
      "two dots climb one level"
    )
    resolved_to(
      resolve_in(python, root .. "/pkg/inner/me.py", 3, "python"),
      "pkg/sibling%.py",
      "two dots plus a tail"
    )
  end)

  H.check("python: non-import lines and unresolvable modules answer nil", function()
    local root = H.tmpdir()
    H.write(root .. "/pyproject.toml", { "" })
    H.write(root .. "/main.py", { "x = 1", "import os", "from nowhere.at.all import thing" })
    H.is_nil(resolve_in(python, root .. "/main.py", 1, "python"), "not an import at all")
    H.is_nil(resolve_in(python, root .. "/main.py", 2, "python"), "stdlib is left to the LSP")
    H.is_nil(resolve_in(python, root .. "/main.py", 3, "python"), "nothing on disk")
  end)

  H.check("python: without a project marker it still resolves next to the file", function()
    local root = H.tmpdir()
    H.write(root .. "/pkg/mod.py", { "" })
    H.write(root .. "/main.py", { "import pkg.mod" })
    resolved_to(resolve_in(python, root .. "/main.py", 1, "python"), "pkg/mod%.py")
  end)

  -- ── Go ─────────────────────────────────────────────────────────────────────

  local go = require("gopath.resolvers.go.import_path")

  H.check("go: an in-module import opens a representative file, doc.go first", function()
    local root = H.tmpdir()
    H.write(root .. "/go.mod", { "module example.com/proj", "", "go 1.22" })
    H.write(root .. "/pkg/util/doc.go", { "package util" })
    H.write(root .. "/pkg/util/util.go", { "package util" })
    H.write(root .. "/pkg/plain/a_test.go", { "package plain" })
    H.write(root .. "/pkg/plain/zzz.go", { "package plain" })
    H.write(root .. "/main.go", {
      'import "example.com/proj/pkg/util"',
      'import "example.com/proj/pkg/plain"',
    })

    resolved_to(resolve_in(go, root .. "/main.go", 1, "go"), "pkg/util/doc%.go", "doc.go preferred")
    local plain = resolve_in(go, root .. "/main.go", 2, "go")
    resolved_to(plain, "pkg/plain/zzz%.go", "_test.go files are skipped")
  end)

  H.check("go: vendored and module-cache imports", function()
    local root = H.tmpdir()
    H.write(root .. "/go.mod", { "module example.com/proj" })
    H.write(root .. "/vendor/github.com/x/y/y.go", { "package y" })
    H.write(root .. "/main.go", { 'import "github.com/x/y"', 'import "github.com/cached/z"' })

    resolved_to(
      resolve_in(go, root .. "/main.go", 1, "go"),
      "vendor/github%.com/x/y/y%.go",
      "vendor"
    )

    local modcache = H.tmpdir()
    H.write(modcache .. "/github.com/cached/z/z.go", { "package z" })
    local saved = vim.env.GOMODCACHE
    vim.env.GOMODCACHE = modcache
    resolved_to(
      resolve_in(go, root .. "/main.go", 2, "go"),
      "github%.com/cached/z/z%.go",
      "modcache"
    )
    vim.env.GOMODCACHE = saved
  end)

  H.check("go: $GOPATH/pkg/mod is used when $GOMODCACHE is unset", function()
    local root = H.tmpdir()
    H.write(root .. "/go.mod", { "module example.com/proj" })
    H.write(root .. "/main.go", { 'import "github.com/gp/pkg"' })

    local gopath = H.tmpdir()
    H.write(gopath .. "/pkg/mod/github.com/gp/pkg/pkg.go", { "package pkg" })
    local saved_mc, saved_gp = vim.env.GOMODCACHE, vim.env.GOPATH
    vim.env.GOMODCACHE = nil
    vim.env.GOPATH = gopath
    resolved_to(resolve_in(go, root .. "/main.go", 1, "go"), "github%.com/gp/pkg/pkg%.go")
    vim.env.GOMODCACHE, vim.env.GOPATH = saved_mc, saved_gp
  end)

  H.check("go: a quoted string without a slash, and an empty package dir, answer nil", function()
    local root = H.tmpdir()
    H.write(root .. "/go.mod", { "module example.com/proj" })
    H.mkdir(root .. "/pkg/empty")
    H.write(root .. "/main.go", {
      'var s = "no slash here"',
      "x := 1",
      'import "example.com/proj/pkg/empty"',
    })
    H.is_nil(resolve_in(go, root .. "/main.go", 1, "go"), "a plain string is not an import path")
    H.is_nil(resolve_in(go, root .. "/main.go", 2, "go"), "no string at all")
    H.is_nil(resolve_in(go, root .. "/main.go", 3, "go"), "a package directory with no .go file")
  end)

  -- ── Rust ───────────────────────────────────────────────────────────────────

  local rust = require("gopath.resolvers.rust.use_path")

  H.check("rust: `mod foo;` resolves next to the current file, file before mod.rs", function()
    local root = H.tmpdir()
    H.write(root .. "/Cargo.toml", { "[package]" })
    H.write(root .. "/src/lib.rs", { "mod flat;", "mod nested;" })
    H.write(root .. "/src/flat.rs", { "" })
    H.write(root .. "/src/nested/mod.rs", { "" })

    resolved_to(resolve_in(rust, root .. "/src/lib.rs", 1, "rust"), "src/flat%.rs")
    resolved_to(resolve_in(rust, root .. "/src/lib.rs", 2, "rust"), "src/nested/mod%.rs")
  end)

  H.check("rust: `use crate::…` is rooted at the crate src dir", function()
    local root = H.tmpdir()
    H.write(root .. "/Cargo.toml", { "[package]" })
    H.write(root .. "/src/main.rs", { "use crate::a::b::Thing;", "use crate::a::b;" })
    H.write(root .. "/src/a/b.rs", { "" })

    resolved_to(
      resolve_in(rust, root .. "/src/main.rs", 1, "rust"),
      "src/a/b%.rs",
      "the trailing item is dropped"
    )
    resolved_to(resolve_in(rust, root .. "/src/main.rs", 2, "rust"), "src/a/b%.rs", "module form")
  end)

  H.check("rust: `use self::…` and `use super::…`", function()
    local root = H.tmpdir()
    H.write(root .. "/Cargo.toml", { "[package]" })
    H.write(root .. "/src/lib.rs", { "" })
    H.write(root .. "/src/parent_sibling.rs", { "" })
    H.write(root .. "/src/inner/child.rs", { "" })
    H.write(root .. "/src/inner/mod.rs", { "use self::child;", "use super::parent_sibling;" })

    resolved_to(resolve_in(rust, root .. "/src/inner/mod.rs", 1, "rust"), "src/inner/child%.rs")
    resolved_to(resolve_in(rust, root .. "/src/inner/mod.rs", 2, "rust"), "src/parent_sibling%.rs")
  end)

  H.check("rust: external crates and non-use lines answer nil", function()
    local root = H.tmpdir()
    H.write(root .. "/Cargo.toml", { "[package]" })
    H.write(root .. "/src/lib.rs", { "use serde::Serialize;", "fn main() {}", "mod missing;" })
    H.is_nil(resolve_in(rust, root .. "/src/lib.rs", 1, "rust"), "left to rust-analyzer")
    H.is_nil(resolve_in(rust, root .. "/src/lib.rs", 2, "rust"), "not an import")
    H.is_nil(resolve_in(rust, root .. "/src/lib.rs", 3, "rust"), "nothing on disk")
  end)

  H.check("rust: `use crate::…` without a lib.rs/main.rs under src/ answers nil", function()
    local root = H.tmpdir()
    H.write(root .. "/Cargo.toml", { "[package]" })
    H.write(root .. "/src/a.rs", { "use crate::a;" })
    H.is_nil(resolve_in(rust, root .. "/src/a.rs", 1, "rust"), "no crate root could be identified")
  end)

  -- ── C / C++ ────────────────────────────────────────────────────────────────

  local c = require("gopath.resolvers.c.include_path")

  H.check("c: a quoted include is searched next to the current file first", function()
    local root = H.tmpdir()
    H.write(root .. "/CMakeLists.txt", { "" })
    H.write(root .. "/src/local.h", { "" })
    H.write(root .. "/include/local.h", { "" })
    H.write(root .. "/src/main.c", { '#include "local.h"' })

    resolved_to(
      resolve_in(c, root .. "/src/main.c", 1, "c"),
      "src/local%.h",
      "the preprocessor's own priority"
    )
  end)

  H.check("c: an angled include is searched under the project include roots", function()
    local root = H.tmpdir()
    H.write(root .. "/compile_commands.json", { "[]" })
    H.write(root .. "/include/proj/api.h", { "" })
    H.write(root .. "/src/main.c", { "#include <proj/api.h>", "#include < spaced >" })

    resolved_to(resolve_in(c, root .. "/src/main.c", 1, "c"), "include/proj/api%.h")
    H.is_nil(resolve_in(c, root .. "/src/main.c", 2, "c"), "a nonsense angled include")
  end)

  H.check("c: cpp shares the resolver and reports its own filetype", function()
    local root = H.tmpdir()
    H.write(root .. "/Makefile", { "" })
    H.write(root .. "/inc/thing.hpp", { "" })
    H.write(root .. "/main.cpp", { '#include "thing.hpp"' })
    local res = resolve_in(c, root .. "/main.cpp", 1, "cpp")
    resolved_to(res, "inc/thing%.hpp")
    H.eq(res.language, "cpp", "the buffer's filetype, not a hard-coded 'c'")
  end)

  H.check("c: non-include lines and missing headers answer nil", function()
    local root = H.tmpdir()
    H.write(root .. "/.git/HEAD", { "" })
    H.write(root .. "/main.c", { "int main(void) { return 0; }", '#include "nope.h"' })
    H.is_nil(resolve_in(c, root .. "/main.c", 1, "c"))
    H.is_nil(resolve_in(c, root .. "/main.c", 2, "c"))
  end)

  -- ── JavaScript / TypeScript ────────────────────────────────────────────────

  local js = require("gopath.resolvers.javascript.import_path")

  H.check("js: relative specifiers, extension order, and index files", function()
    local root = H.tmpdir()
    H.write(root .. "/src/util.ts", { "" })
    H.write(root .. "/src/util.js", { "" })
    H.write(root .. "/src/dir/index.tsx", { "" })
    H.write(root .. "/shared.js", { "" })
    H.write(root .. "/src/app.ts", {
      "import { a } from './util'",
      "import b from './dir'",
      "export * from '../shared'",
      "const c = require('./util')",
      "const d = await import('./util')",
      "import './util'",
    })

    resolved_to(resolve_in(js, root .. "/src/app.ts", 1, "typescript"), "src/util%.ts", "TS first")
    resolved_to(
      resolve_in(js, root .. "/src/app.ts", 2, "typescript"),
      "src/dir/index%.tsx",
      "index"
    )
    resolved_to(
      resolve_in(js, root .. "/src/app.ts", 3, "typescript"),
      "shared%.js",
      "parent-relative"
    )
    resolved_to(resolve_in(js, root .. "/src/app.ts", 4, "typescript"), "src/util%.ts", "require()")
    resolved_to(
      resolve_in(js, root .. "/src/app.ts", 5, "typescript"),
      "src/util%.ts",
      "dynamic import"
    )
    resolved_to(
      resolve_in(js, root .. "/src/app.ts", 6, "typescript"),
      "src/util%.ts",
      "side effect"
    )
  end)

  H.check("js: a specifier that already carries its extension is taken as written", function()
    local root = H.tmpdir()
    H.write(root .. "/src/data.json", { "{}" })
    H.write(root .. "/src/app.js", { "import data from './data.json'" })
    resolved_to(resolve_in(js, root .. "/src/app.js", 1, "javascript"), "src/data%.json")
  end)

  H.check("js: a bare specifier resolves through node_modules", function()
    local root = H.tmpdir()
    H.write(root .. "/node_modules/lodash/index.js", { "" })
    H.write(root .. "/src/app.js", { "import _ from 'lodash'" })
    resolved_to(
      resolve_in(js, root .. "/src/app.js", 1, "javascript"),
      "node_modules/lodash/index%.js"
    )
  end)

  H.check(
    "js: package.json types/module/main is consulted, with the manifest as last resort",
    function()
      local root = H.tmpdir()
      H.write(root .. "/node_modules/pkg/package.json", { '{ "main": "lib/entry.js" }' })
      H.write(root .. "/node_modules/pkg/lib/entry.js", { "" })
      H.write(root .. "/node_modules/nofiles/package.json", { '{ "main": "missing.js" }' })
      H.write(root .. "/src/app.js", { "import p from 'pkg'", "import n from 'nofiles'" })

      resolved_to(
        resolve_in(js, root .. "/src/app.js", 1, "javascript"),
        "node_modules/pkg/lib/entry%.js",
        "the declared entry point"
      )
      resolved_to(
        resolve_in(js, root .. "/src/app.js", 2, "javascript"),
        "node_modules/nofiles/package%.json",
        "an unusable entry still lands you in the package"
      )
    end
  )

  H.check("js: nothing resolvable answers nil", function()
    local root = H.tmpdir()
    H.write(
      root .. "/src/app.js",
      { "const x = 1", "import y from './gone'", "import z from 'absent'" }
    )
    H.is_nil(resolve_in(js, root .. "/src/app.js", 1, "javascript"), "not an import")
    H.is_nil(resolve_in(js, root .. "/src/app.js", 2, "javascript"), "relative miss")
    H.is_nil(resolve_in(js, root .. "/src/app.js", 3, "javascript"), "no node_modules anywhere")
  end)

  -- ── C# ─────────────────────────────────────────────────────────────────────

  local cs = require("gopath.resolvers.csharp.using_path")

  H.check("csharp: a using mirrors the namespace onto a path", function()
    local root = H.tmpdir()
    H.write(root .. "/App.csproj", { "<Project/>" })
    H.write(root .. "/My/App/Utils.cs", { "" })
    H.write(root .. "/Program.cs", { "using My.App.Utils;", "using static My.App.Utils;" })

    resolved_to(resolve_in(cs, root .. "/Program.cs", 1, "cs"), "My/App/Utils%.cs")
    resolved_to(resolve_in(cs, root .. "/Program.cs", 2, "cs"), "My/App/Utils%.cs", "static form")
  end)

  H.check("csharp: falling back to any file named after the last segment", function()
    local root = H.tmpdir()
    H.write(root .. "/App.sln", { "" })
    H.write(root .. "/somewhere/else/Helpers.cs", { "" })
    H.write(root .. "/Program.cs", { "using Totally.Different.Helpers;" })
    resolved_to(resolve_in(cs, root .. "/Program.cs", 1, "cs"), "Helpers%.cs")
  end)

  H.check("csharp: alias usings, single-segment usings and misses answer nil", function()
    local root = H.tmpdir()
    H.write(root .. "/App.csproj", { "<Project/>" })
    H.write(
      root .. "/Program.cs",
      { "using Alias = My.App.Utils;", "using System;", "using A.B.C;" }
    )
    H.is_nil(resolve_in(cs, root .. "/Program.cs", 1, "cs"), "the alias form is skipped")
    H.is_nil(resolve_in(cs, root .. "/Program.cs", 2, "cs"), "no dot, nothing to mirror")
    H.is_nil(resolve_in(cs, root .. "/Program.cs", 3, "cs"), "nothing on disk")
  end)

  H.check("csharp: confidence is lower, because the mapping is a heuristic", function()
    local root = H.tmpdir()
    H.write(root .. "/App.csproj", { "<Project/>" })
    H.write(root .. "/My/Thing.cs", { "" })
    H.write(root .. "/Program.cs", { "using My.Thing;" })
    H.eq(resolve_in(cs, root .. "/Program.cs", 1, "cs").confidence, 0.7)
  end)

  -- ── Zig ────────────────────────────────────────────────────────────────────

  local zig = require("gopath.resolvers.zig.import_path")

  H.check("zig: relative @import targets, with and without the extension", function()
    local root = H.tmpdir()
    H.write(root .. "/utils.zig", { "" })
    H.write(root .. "/sub/deep.zig", { "" })
    H.write(root .. "/main.zig", {
      'const u = @import("utils.zig");',
      'const d = @import( "sub/deep.zig" );',
      'const x = @import("utils");',
    })

    resolved_to(resolve_in(zig, root .. "/main.zig", 1, "zig"), "utils%.zig")
    resolved_to(
      resolve_in(zig, root .. "/main.zig", 2, "zig"),
      "sub/deep%.zig",
      "whitespace tolerated"
    )
    resolved_to(
      resolve_in(zig, root .. "/main.zig", 3, "zig"),
      "utils%.zig",
      "the .zig is appended"
    )
  end)

  H.check("zig: builtin modules are left to zls", function()
    local root = H.tmpdir()
    H.write(root .. "/main.zig", {
      'const std = @import("std");',
      'const b = @import("builtin");',
      'const r = @import("root");',
      'const c = @import("c");',
      'const m = @import("missing.zig");',
      "const n = 1;",
    })
    for row = 1, 4 do
      H.is_nil(resolve_in(zig, root .. "/main.zig", row, "zig"), "builtin on line " .. row)
    end
    H.is_nil(resolve_in(zig, root .. "/main.zig", 5, "zig"), "a relative file that is not there")
    H.is_nil(resolve_in(zig, root .. "/main.zig", 6, "zig"), "not an @import at all")
  end)

  -- ── Java ───────────────────────────────────────────────────────────────────

  local java = require("gopath.resolvers.java.import_path")

  H.check("java: a package maps straight onto a directory under a source root", function()
    local root = H.tmpdir()
    H.write(root .. "/pom.xml", { "<project/>" })
    H.write(root .. "/src/main/java/com/example/utils/Helper.java", { "" })
    H.write(root .. "/src/main/java/com/example/App.java", { "import com.example.utils.Helper;" })

    local res = resolve_in(java, root .. "/src/main/java/com/example/App.java", 1, "java")
    resolved_to(res, "com/example/utils/Helper%.java")
    H.eq(res.confidence, 0.85, "package→path is reliable in Java")
  end)

  H.check("java: static imports drop the trailing member", function()
    local root = H.tmpdir()
    H.write(root .. "/build.gradle", { "" })
    H.write(root .. "/src/main/java/com/example/Foo.java", { "" })
    H.write(root .. "/src/main/java/App.java", { "import static com.example.Foo.bar;" })
    resolved_to(
      resolve_in(java, root .. "/src/main/java/App.java", 1, "java"),
      "com/example/Foo%.java"
    )
  end)

  H.check("java: a wildcard import opens the package's first class", function()
    local root = H.tmpdir()
    H.write(root .. "/pom.xml", { "<project/>" })
    H.write(root .. "/src/main/java/com/example/utils/Aaa.java", { "" })
    H.write(root .. "/src/main/java/com/example/utils/Bbb.java", { "" })
    H.write(root .. "/src/main/java/App.java", { "import com.example.utils.*;" })
    resolved_to(
      resolve_in(java, root .. "/src/main/java/App.java", 1, "java"),
      "com/example/utils/Aaa%.java"
    )
  end)

  H.check("java: JDK/dependency imports and non-imports answer nil", function()
    local root = H.tmpdir()
    H.write(root .. "/pom.xml", { "<project/>" })
    H.write(root .. "/src/main/java/App.java", {
      "import java.util.List;",
      "public class App {}",
      "import NoDots;",
    })
    H.is_nil(resolve_in(java, root .. "/src/main/java/App.java", 1, "java"), "left to jdtls")
    H.is_nil(resolve_in(java, root .. "/src/main/java/App.java", 2, "java"), "not an import")
    H.is_nil(resolve_in(java, root .. "/src/main/java/App.java", 3, "java"), "a dotless import")
  end)
end
