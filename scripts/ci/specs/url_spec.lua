-- scripts/ci/specs/url_spec.lua
-- gopath.util.url (pure detection/extraction/normalisation) and the resolver
-- built on it, gopath.resolvers.common.url.
--
-- scripts/ci/functional_tests.lua drives the *pipeline* cases (a URL must beat
-- the file resolvers, a real file must beat a bare host). This spec is the
-- unit level underneath: which spellings count as strict vs. loose, the
-- drive-letter guard that keeps "C:/tmp" from looking like a scheme, and what
-- the cursor-based extractor does with two URLs on one line.

---@param H table
return function(H)
  local URL = require("gopath.util.url")
  local RES = require("gopath.resolvers.common.url")

  -- ── is_strict_url ──────────────────────────────────────────────────────────

  H.check("is_strict_url: explicit schemes", function()
    for _, u in ipairs({
      "http://x.com",
      "https://x.com/a/b?c=1#d",
      "ftp://files.example.org/pub",
      "ssh://git@host/repo",
      "file:///etc/hosts",
      "magnet:?xt=urn:btih:abc",
      "HTTPS://UPPER.CASE",
    }) do
      H.eq(URL.is_strict_url(u), true, u)
    end
  end)

  H.check("is_strict_url: www. and mailto: count, unknown schemes do not", function()
    H.eq(URL.is_strict_url("www.google.com"), true, "www. prefix")
    H.eq(URL.is_strict_url("mailto:someone@example.com"), true, "mailto")
    H.eq(URL.is_strict_url("wat://x.com"), false, "a scheme nobody registered")
    H.eq(URL.is_strict_url("github.com/neovim"), false, "a bare host is loose, not strict")
  end)

  H.check("is_strict_url: a Windows drive letter is not a scheme", function()
    -- One-character "schemes" are rejected precisely so that these stay files.
    H.eq(URL.is_strict_url("C:/tmp/file.lua"), false, "forward-slash drive")
    H.eq(URL.is_strict_url("C:\\tmp\\file.lua"), false, "backslash drive")
    H.eq(URL.is_strict_url("e:/repos"), false, "lowercase drive")
  end)

  H.check("is_strict_url: junk input", function()
    H.eq(URL.is_strict_url(""), false)
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(URL.is_strict_url(nil), false)
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(URL.is_strict_url({}), false)
    H.eq(URL.is_strict_url("plain words"), false)
  end)

  H.check("is_strict_url: extra schemes from config extend the built-in list", function()
    H.eq(URL.is_strict_url("obsidian://open?x=1"), false, "not built in")
    H.eq(URL.is_strict_url("obsidian://open?x=1", { schemes = { "obsidian" } }), true, "opted in")
  end)

  -- ── is_loose_url ───────────────────────────────────────────────────────────

  H.check("is_loose_url: bare hosts with a known TLD", function()
    H.eq(URL.is_loose_url("github.com"), true, "host alone")
    H.eq(URL.is_loose_url("github.com/neovim/neovim"), true, "with a path")
    H.eq(URL.is_loose_url("sub.domain.co.uk/x"), true, "multi-label host")
    H.eq(URL.is_loose_url("example.com:8080/x"), true, "explicit port")
  end)

  H.check("is_loose_url: source filenames are never mistaken for hosts", function()
    -- The TLD list deliberately omits extensions that double as TLDs.
    for _, name in ipairs({ "build.sh", "main.rs", "setup.py", "index.ts", "notes.md", "lib.so" }) do
      H.eq(URL.is_loose_url(name), false, name .. " is a file, not a host")
    end
    H.eq(URL.is_loose_url("README"), false, "single label")
    H.eq(URL.is_loose_url("x..com"), false, "empty label")
    H.eq(URL.is_loose_url("-bad.com"), false, "a label may not start with a dash")
  end)

  H.check("is_loose_url: a strict URL is not also a loose one", function()
    H.eq(URL.is_loose_url("https://github.com/x"), false, "strict forms are handled elsewhere")
    H.eq(URL.is_loose_url("www.github.com"), false)
  end)

  H.check("is_loose_url: scp-style git remotes", function()
    H.eq(URL.is_loose_url("git@github.com:foo/bar.git"), true)
    H.eq(URL.is_loose_url("user.name@gitlab.com:g/p"), true, "dotted user part")
    H.eq(URL.is_loose_url("host.com:22"), true, "host:port with no path is still a host")
    H.eq(URL.is_loose_url("host.com:abc"), false, "but a non-numeric ':tail' is not a port")
    H.eq(URL.is_loose_url("git@nosuchtld:foo/bar"), false, "the host still needs a known TLD")
    H.eq(
      URL.is_loose_url("git@github.com:22"),
      false,
      "a pure port after '@host' is ssh, not a page"
    )
  end)

  H.check("is_loose_url: extra TLDs from config extend the built-in list", function()
    H.eq(URL.is_loose_url("thing.internal/x"), false, "not built in")
    H.eq(URL.is_loose_url("thing.internal/x", { tlds = { "internal" } }), true, "opted in")
  end)

  -- ── normalize ──────────────────────────────────────────────────────────────

  H.check("normalize: adds the implicit scheme only where one is missing", function()
    H.eq(URL.normalize("https://x.com/a"), "https://x.com/a", "already complete")
    H.eq(URL.normalize("www.google.com"), "https://www.google.com", "www. gets https")
    H.eq(URL.normalize("github.com/a/b"), "https://github.com/a/b", "bare host gets https")
    H.eq(URL.normalize("mailto:a@b.com"), "mailto:a@b.com", "mailto is left alone")
  end)

  H.check("normalize: scp-style remotes become their web equivalent", function()
    H.eq(URL.normalize("git@github.com:foo/bar.git"), "https://github.com/foo/bar")
    H.eq(URL.normalize("git@gitlab.com:group/sub/proj"), "https://gitlab.com/group/sub/proj")
  end)

  H.check("normalize: junk in, junk out — never an error", function()
    H.eq(URL.normalize(""), "")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(URL.normalize(nil), nil)
  end)

  -- ── extract_at_cursor ──────────────────────────────────────────────────────

  ---Put the cursor on `anchor` in a one-line buffer and extract.
  ---@param line string
  ---@param anchor string
  ---@param mode "strict"|"loose"
  ---@return string|nil
  local function extract(line, anchor, mode)
    H.line_at(line, anchor, { filetype = "markdown" })
    return URL.extract_at_cursor(mode)
  end

  H.check("extract strict: query strings and fragments survive", function()
    H.eq(
      extract("docs at https://example.com/a?b=1&c=2#frag ok", "https", "strict"),
      "https://example.com/a?b=1&c=2#frag",
      "<cfile> would have stopped at the '?'"
    )
  end)

  H.check("extract strict: the cursor may sit anywhere inside the URL", function()
    local line = "see https://example.com/deep/path here"
    H.eq(extract(line, "deep", "strict"), "https://example.com/deep/path", "mid-URL")
    H.eq(extract(line, "https", "strict"), "https://example.com/deep/path", "at the scheme")
  end)

  H.check("extract strict: two URLs on one line do not merge", function()
    local line = "a.com,https://b.com/x and https://c.com/y"
    H.eq(extract(line, "https://b", "strict"), "https://b.com/x", "the one under the cursor")
    H.eq(extract(line, "https://c", "strict"), "https://c.com/y", "and the other one")
  end)

  H.check("extract strict: trailing punctuation and unbalanced brackets are trimmed", function()
    H.eq(extract("See (https://example.com/x).", "https", "strict"), "https://example.com/x")
    H.eq(extract("[docs](https://neovim.io/d#top)", "https", "strict"), "https://neovim.io/d#top")
    H.eq(
      extract("balanced https://en.wikipedia.org/wiki/Foo_(bar) end", "wiki", "strict"),
      "https://en.wikipedia.org/wiki/Foo_(bar)",
      "a matched pair belongs to the URL"
    )
  end)

  H.check("extract strict: nothing under the cursor, nothing returned", function()
    H.is_nil(extract("no urls here at all", "urls", "strict"))
    H.is_nil(extract("github.com/x is only loose", "github", "strict"), "loose form")
    H.line_at("", "", { filetype = "markdown" })
    H.is_nil(URL.extract_at_cursor("strict"), "an empty line")
  end)

  H.check("extract loose: bare hosts and scp remotes", function()
    H.eq(
      extract("clone github.com/neovim/neovim first", "github", "loose"),
      "github.com/neovim/neovim"
    )
    H.eq(extract("git@github.com:foo/bar.git", "git@", "loose"), "git@github.com:foo/bar.git")
    H.is_nil(extract("see README.md now", "README", "loose"), "a filename is not a host")
  end)

  H.check("BUG: a parenthesised loose URL keeps its closing bracket", function()
    -- `trim_trailing` runs on the raw span, which still carries the leading
    -- "(" the cursor-widening pulled in, so the ")" counts as *balanced* and
    -- survives; only afterwards is the "(" stripped. The strict pass is
    -- immune because its candidate starts at the scheme, which leaves the
    -- ")" unbalanced and therefore trimmed.
    --
    -- Result: "(github.com/x)" in prose, or a Markdown link whose target is a
    -- bare host, hands the browser "https://github.com/x)".
    H.eq(extract("(github.com/x)", "github", "loose"), "github.com/x)", "BUG: stray ')'")
    -- Related limitation, pinned as behaviour rather than a second bug: a
    -- Markdown link whose target is a bare host is not recognised at all,
    -- because the span widens across "[" and "]" too and the candidate then
    -- starts at the label instead of the host.
    H.is_nil(
      extract("[docs](github.com/neovim/neovim)", "github", "loose"),
      "a scheme-less Markdown target is out of reach of the loose pass"
    )
    -- What it should look like, and does, once the opener is not in the span:
    H.eq(extract("see github.com/x now", "github", "loose"), "github.com/x", "unwrapped is fine")
    H.eq(
      extract("[docs](https://github.com/x)", "https", "strict"),
      "https://github.com/x",
      "and the strict pass gets it right"
    )
  end)

  -- ── the resolver ───────────────────────────────────────────────────────────

  H.check("resolve_strict: builds a url result that skips create-on-missing", function()
    H.line_at("see https://example.com/a?q=1 here", "https", { filetype = "markdown" })
    local r = RES.resolve_strict()
    H.truthy(r, "expected a result")
    H.eq(r.kind, "url")
    H.eq(r.path, "https://example.com/a?q=1", "normalised target")
    H.eq(r.exists, true, "marked existing so nothing offers to create it")
    H.eq(r.source, "url")
    H.eq(r.confidence, 0.95, "strict forms are unambiguous")
    H.is_nil(r.range, "a URL has no line/col")
    H.eq(r.language, "markdown", "carries the buffer's filetype")
  end)

  H.check("resolve(): the resolver interface entry point is the strict pass", function()
    H.line_at("www.google.com", "www", { filetype = "text" })
    local via_iface = RES.resolve()
    H.truthy(via_iface, "expected a result")
    H.eq(via_iface.path, "https://www.google.com")
    H.eq(via_iface.confidence, 0.95, "same confidence as resolve_strict")
  end)

  H.check("resolve_loose: lower confidence, and gated on bare_hosts", function()
    H.config_sandbox(function(c)
      H.line_at("clone github.com/neovim/neovim", "github", { filetype = "text" })
      local on = RES.resolve_loose()
      H.truthy(on, "expected a result")
      H.eq(on.confidence, 0.7, "a bare host is a guess, and is scored as one")
      H.eq(on.path, "https://github.com/neovim/neovim")

      c.setup({ url = { bare_hosts = false } })
      H.is_nil(RES.resolve_loose(), "bare_hosts = false switches the loose pass off")
      H.truthy(RES.resolve_strict() == nil, "and the strict pass never matched this anyway")
    end)
  end)

  H.check("url.enable = false switches both passes off", function()
    H.config_sandbox(function(c)
      c.setup({ url = { enable = false } })
      H.line_at("https://example.com/a", "https", { filetype = "text" })
      H.is_nil(RES.resolve_strict(), "strict off")
      H.line_at("github.com/a/b", "github", { filetype = "text" })
      H.is_nil(RES.resolve_loose(), "loose off")
    end)
  end)

  H.check("configured extra schemes/TLDs reach the resolver", function()
    H.config_sandbox(function(c)
      c.setup({ url = { schemes = { "obsidian" }, tlds = { "internal" } } })
      H.line_at("open obsidian://vault/note here", "obsidian", { filetype = "text" })
      local strict = RES.resolve_strict()
      H.truthy(strict, "custom scheme accepted")
      H.eq(strict.path, "obsidian://vault/note")

      H.line_at("wiki.internal/page", "wiki", { filetype = "text" })
      local loose = RES.resolve_loose()
      H.truthy(loose, "custom TLD accepted")
      H.eq(loose.path, "https://wiki.internal/page")
    end)
  end)
end
