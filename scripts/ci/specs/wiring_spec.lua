-- scripts/ci/specs/wiring_spec.lua
-- Everything between `require("gopath").setup()` and the resolvers: the
-- bindings layer (keymaps, `:Gopath` and its aliases, autocommands), the help
-- opener, `:checkhealth gopath`, and setup() itself.
--
-- The command and keymap layers are re-registered against a stand-in
-- `gopath.commands`, so pressing a key or running a subcommand can be checked
-- by what it *dispatches to* rather than by what it resolves — the resolvers
-- have their own specs.

---@param H table
return function(H)
  -- ── bindings: keymaps ──────────────────────────────────────────────────────

  ---Re-register the preset with a recording `gopath.commands`.
  ---@param mappings any  the `mappings` config value
  ---@param fn fun(calls: table, registered: any)
  ---@return nil
  local function with_keymaps(mappings, fn)
    local calls = { open = {}, copy = 0, debug = 0, check = 0, probe = {} }
    H.with_modules({
      ["gopath.commands"] = {
        resolve_and_open = function(kind)
          calls.open[#calls.open + 1] = kind
        end,
        resolve_and_copy = function()
          calls.copy = calls.copy + 1
        end,
        debug_under_cursor = function()
          calls.debug = calls.debug + 1
        end,
        check_under_cursor = function()
          calls.check = calls.check + 1
        end,
        probe_selection = function(opts)
          calls.probe[#calls.probe + 1] = opts
        end,
        shorten_to_env = function() end,
      },
    }, function()
      local keymaps = require("gopath.bindings.keymaps")
      local cfg = vim.deepcopy(require("gopath.config").get())
      cfg.mappings = mappings
      fn(calls, keymaps.setup(cfg))
    end, { unload = { "gopath.bindings.keymaps" } })
    H.fresh("gopath.bindings.keymaps")
  end

  ---The rhs callback bound to `lhs` in mode `mode`, or nil. `<Leader>` is
  ---resolved when a mapping is created, so a leader-prefixed lhs is matched by
  ---its tail.
  ---@param mode string
  ---@param lhs string
  ---@return function|nil
  local function mapped(mode, lhs)
    local leader = lhs:match("^<[Ll]eader>(.*)$")
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if m.lhs == lhs or (leader and m.lhs:sub(-#leader) == leader and #m.lhs == #leader + 1) then
        return m.callback
      end
    end
    return nil
  end

  ---Remove every mapping the preset (or a spec) may have left behind, so a
  ---stale binding is never mistaken for a fresh one.
  ---@param extra string[]|nil
  ---@return nil
  local function clear_preset(extra)
    local lhss = { "gP", "g|", "g\\", "g}", "gM", "gY", "g?", "gC", "gQ", "gp", "g<F5>" }
    for _, lhs in ipairs(vim.list_extend(lhss, extra or {})) do
      pcall(vim.keymap.del, "n", lhs, {})
      pcall(vim.keymap.del, "v", lhs, {})
    end
    for _, mode in ipairs({ "n", "v" }) do
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        if m.desc and tostring(m.desc):find("probe") then
          pcall(vim.api.nvim_del_keymap, mode, m.lhs)
        end
      end
    end
  end

  H.check("keymaps: the default preset binds every action to its command", function()
    with_keymaps(require("gopath.config").get().mappings, function(calls)
      local pairs_to_check = {
        { "gP", "edit" },
        { "g|", "window" },
        { "g\\", "vsplit" },
        { "g}", "tab" },
        { "gM", "explorer" },
      }
      for _, pair in ipairs(pairs_to_check) do
        local cb = mapped("n", pair[1])
        H.truthy(cb, "expected " .. pair[1] .. " to be bound")
        cb()
        H.eq(calls.open[#calls.open], pair[2], pair[1] .. " opens with mode " .. pair[2])
      end

      H.truthy(mapped("n", "gY"), "copy")
      mapped("n", "gY")()
      H.eq(calls.copy, 1)

      mapped("n", "g?")()
      H.eq(calls.debug, 1)

      mapped("n", "gC")()
      H.eq(calls.check, 1)
    end)
  end)

  H.check("keymaps: the probe action is bound in both normal and visual mode", function()
    with_keymaps(require("gopath.config").get().mappings, function(calls)
      local n = mapped("n", "<Leader>pp")
      H.truthy(n, "normal-mode probe")
      n()
      H.eq(calls.probe[1].open_cmd, "vsplit")
      H.eq(calls.probe[1].ask, true)
      H.is_nil(calls.probe[1].selection, "no selection is claimed from normal mode")

      H.truthy(mapped("v", "<Leader>pp"), "visual-mode probe")
    end)
  end)

  H.check("keymaps: an individual lhs can be overridden or dropped", function()
    clear_preset()
    local cfg = vim.deepcopy(require("gopath.config").get().mappings)
    cfg.open_here = "gQ"
    cfg.debug = false
    with_keymaps(cfg, function(calls)
      local cb = mapped("n", "gQ")
      H.truthy(cb, "the override is bound")
      cb()
      H.eq(calls.open[1], "edit")
      H.is_nil(mapped("n", "gP"), "the default lhs of the overridden action is not bound")
      H.is_nil(mapped("n", "g?"), "`false` drops just that one")
      H.truthy(mapped("n", "gC"), "while its neighbours stay")
    end)
    clear_preset()
    with_keymaps(require("gopath.config").get().mappings, function() end)
  end)

  H.check("keymaps: one action may carry a list of lhs values", function()
    clear_preset()
    local cfg = vim.deepcopy(require("gopath.config").get().mappings)
    cfg.open_here = { "gP", "g<F5>" }
    with_keymaps(cfg, function(calls)
      H.truthy(mapped("n", "gP"), "the first")
      local second = mapped("n", "g<F5>")
      H.truthy(second, "and the second")
      second()
      H.eq(calls.open[1], "edit")
    end)
    clear_preset()
    with_keymaps(require("gopath.config").get().mappings, function() end)
  end)

  H.check("keymaps: mappings = false binds nothing at all", function()
    clear_preset()
    with_keymaps(false, function()
      H.is_nil(mapped("n", "gP"), "nothing bound")
      H.is_nil(mapped("n", "g?"))
      H.is_nil(mapped("n", "<Leader>pp"), "not even the probe")
    end)
    with_keymaps(require("gopath.config").get().mappings, function()
      H.truthy(mapped("n", "gP"), "and the preset comes back")
    end)
  end)

  H.check("keymaps: a probe lhs that is not <leader>-prefixed is still bound", function()
    clear_preset()
    local cfg = vim.deepcopy(require("gopath.config").get().mappings)
    cfg.probe = "gp"
    with_keymaps(cfg, function(_, registered)
      H.eq(type(registered), "table", "the registry reports what it bound")
      H.truthy(mapped("n", "gp"), "bound, just without a which-key group label")
    end)
    clear_preset()
    with_keymaps(require("gopath.config").get().mappings, function() end)
  end)

  -- ── bindings: user commands ────────────────────────────────────────────────

  ---Re-register the command layer against a recording `gopath.commands`.
  ---@param config_overrides table
  ---@param fn fun(calls: table)
  ---@return nil
  local function with_usrcmds(config_overrides, fn)
    local calls = { open = {}, copy = 0, debug = 0, check = 0, probe = {}, shorten = 0 }
    H.with_modules({
      ["gopath.commands"] = {
        resolve_and_open = function(kind)
          calls.open[#calls.open + 1] = kind
        end,
        resolve_and_copy = function()
          calls.copy = calls.copy + 1
        end,
        debug_under_cursor = function()
          calls.debug = calls.debug + 1
        end,
        check_under_cursor = function()
          calls.check = calls.check + 1
        end,
        probe_selection = function(opts)
          calls.probe[#calls.probe + 1] = opts
        end,
        shorten_to_env = function()
          calls.shorten = calls.shorten + 1
        end,
      },
    }, function()
      local usrcmds = require("gopath.bindings.usrcmds")
      local cfg =
        vim.tbl_deep_extend("force", vim.deepcopy(require("gopath.config").get()), config_overrides)
      usrcmds.setup(cfg)
      fn(calls)
    end, { unload = { "gopath.bindings.usrcmds" } })
    H.fresh("gopath.bindings.usrcmds")
  end

  ---Delete every command gopath registers, so "not registered this time" can
  ---be told apart from "left over from the previous registration".
  ---@return nil
  local function clear_commands()
    for _, name in ipairs({
      "Gopath",
      "GopathOpen",
      "GopathCopy",
      "GopathDebug",
      "GopathResolve",
      "GopathCheck",
      "GopathProbe",
      "GopathToReposDir",
      "GopathCacheBuild",
      "GopathCacheInfo",
      "GopathCacheAddRoot",
    }) do
      pcall(vim.api.nvim_del_user_command, name)
    end
  end

  H.check(":Gopath and its aliases exist after setup", function()
    for _, name in ipairs({
      "Gopath",
      "GopathOpen",
      "GopathCopy",
      "GopathDebug",
      "GopathResolve",
      "GopathCheck",
      "GopathProbe",
      "GopathToReposDir",
    }) do
      H.eq(vim.fn.exists(":" .. name), 2, ":" .. name .. " is registered")
    end
  end)

  H.check(":Gopath open/copy/debug/check/to-repos-dir each dispatch once", function()
    with_usrcmds({}, function(calls)
      vim.cmd("Gopath open")
      H.same(calls.open, { "edit" }, "no argument means edit")
      vim.cmd("Gopath open vsplit")
      vim.cmd("Gopath open split")
      vim.cmd("Gopath open tab")
      vim.cmd("Gopath open explorer")
      H.same(calls.open, { "edit", "vsplit", "window", "tab", "explorer" }, "'split' normalises")

      vim.cmd("Gopath copy")
      H.eq(calls.copy, 1)
      vim.cmd("Gopath debug")
      H.eq(calls.debug, 1)
      vim.cmd("Gopath check")
      H.eq(calls.check, 1)
      vim.cmd("Gopath to-repos-dir")
      H.eq(calls.shorten, 1)
    end)
  end)

  H.check(":Gopath probe knows whether a range was given", function()
    with_usrcmds({}, function(calls)
      H.buf({ "a", "b", "c" }, { filetype = "text" })
      vim.cmd("Gopath probe")
      H.eq(calls.probe[1].selection, false, "no range")
      H.eq(calls.probe[1].open_cmd, "vsplit", "the default mode")

      vim.cmd("1,2Gopath probe")
      H.eq(calls.probe[2].selection, true, "a range means a selection was given")
    end)
  end)

  H.check(":Gopath cache routes exist only when the cache is enabled", function()
    clear_commands()
    with_usrcmds({ truncated = { enable = false } }, function()
      H.eq(vim.fn.exists(":GopathCacheBuild"), 0, "not registered")
      H.eq(vim.fn.exists(":GopathCacheInfo"), 0, "nor the info one")
      H.eq(vim.fn.exists(":Gopath"), 2, "the unified command is there regardless")
    end)
    clear_commands()
    with_usrcmds({ truncated = { enable = true } }, function()
      H.eq(vim.fn.exists(":GopathCacheBuild"), 2, "back again")
      H.eq(vim.fn.exists(":GopathCacheInfo"), 2)
      H.eq(vim.fn.exists(":GopathCacheAddRoot"), 2)
    end)
  end)

  H.check(":GopathCacheAddRoot expands its argument and reports a missing directory", function()
    with_usrcmds({ truncated = { enable = true } }, function()
      local notes = H.capture_notify(function()
        vim.cmd("GopathCacheAddRoot " .. vim.fn.fnameescape("/definitely/not/a/directory"))
      end)
      H.match(H.notify_text(notes), "Directory does not exist")

      local usage = H.capture_notify(function()
        pcall(vim.cmd, "GopathCacheAddRoot")
      end)
      H.truthy(H.notify_text(usage) ~= nil, "an empty argument is handled rather than raised")
    end)
  end)

  H.check("individual aliases can be switched off one at a time", function()
    clear_commands()
    with_usrcmds({ commands = { copy = false, debug = false } }, function()
      H.eq(vim.fn.exists(":GopathCopy"), 0, "dropped")
      H.eq(vim.fn.exists(":GopathDebug"), 0, "dropped")
      H.eq(vim.fn.exists(":GopathOpen"), 2, "the others stay")
      H.eq(vim.fn.exists(":Gopath"), 2, "and the unified command is never affected")
    end)
    with_usrcmds({}, function()
      H.eq(vim.fn.exists(":GopathCopy"), 2, "and they come back")
    end)
  end)

  H.check("commands = false registers nothing at all", function()
    clear_commands()
    local registered = false
    H.with_modules({
      ["gopath.commands"] = setmetatable({}, {
        __index = function()
          registered = true
          return function() end
        end,
      }),
    }, function()
      local usrcmds = require("gopath.bindings.usrcmds")
      local cfg = vim.deepcopy(require("gopath.config").get())
      cfg.commands = false
      usrcmds.setup(cfg)
    end, { unload = { "gopath.bindings.usrcmds" } })
    H.fresh("gopath.bindings.usrcmds")
    H.falsy(registered, "the command module was not even consulted")
    H.eq(vim.fn.exists(":Gopath"), 0, "and nothing was registered")
    -- Restore the real registration for the rest of the run.
    require("gopath.bindings.usrcmds").setup(require("gopath.config").get())
    H.eq(vim.fn.exists(":Gopath"), 2, "restored")
  end)

  H.check(":GopathOpen accepts the legacy 'window_vsplit' mode name", function()
    with_usrcmds({}, function(calls)
      vim.cmd("GopathOpen window_vsplit")
      H.same(calls.open, { "vsplit" })
      vim.cmd("GopathOpen")
      H.same(calls.open, { "vsplit", "edit" }, "no argument means edit")
    end)
  end)

  H.check(":GopathProbe's bang selects a split", function()
    with_usrcmds({}, function(calls)
      vim.cmd("GopathProbe!")
      H.eq(calls.probe[1].open_cmd, "split")
      vim.cmd("GopathProbe edit")
      H.eq(calls.probe[2].open_cmd, "edit")
    end)
  end)

  -- ── bindings: autocommands ─────────────────────────────────────────────────

  H.check("autocmds: BufWritePost drops the path caches so a new file is findable", function()
    local PATH = require("gopath.util.path")
    local autocmds = require("gopath.bindings.autocmds")
    autocmds.setup(require("gopath.config").get())

    local dir = H.tmpdir()
    vim.opt.runtimepath:append(dir)
    PATH.invalidate_caches()
    H.is_nil(PATH.search_in_rtp({ "written.lua" }), "indexes the empty root")

    H.write(dir .. "/written.lua", { "" })
    H.is_nil(PATH.search_in_rtp({ "written.lua" }), "the stale index still hides it")

    vim.api.nvim_exec_autocmds("BufWritePost", {})
    local hit = PATH.search_in_rtp({ "written.lua" })

    vim.opt.runtimepath:remove(dir)
    PATH.invalidate_caches()
    H.truthy(hit, "after the write event it resolves")
  end)

  H.check("autocmds: the rebuild-on-save autocmd is opt-in and pattern-driven", function()
    local autocmds = require("gopath.bindings.autocmds")

    local function rebuild_autocmds()
      local ok, list = pcall(vim.api.nvim_get_autocmds, { group = "GopathCacheAutoRebuild" })
      return ok and list or {}
    end

    local cfg = vim.deepcopy(require("gopath.config").get())
    cfg.truncated.auto_rebuild_on_save = false
    autocmds.setup(cfg)
    H.eq(#rebuild_autocmds(), 0, "off by default")

    cfg.truncated.auto_rebuild_on_save = true
    cfg.truncated.watch_patterns = { "*.md" }
    autocmds.setup(cfg)
    local list = rebuild_autocmds()
    H.truthy(#list >= 1, "registered once opted in")
    H.eq(list[1].pattern, "*.md", "with the configured pattern")

    -- Leave the augroup empty again so later runs are not surprised by it.
    pcall(vim.api.nvim_del_augroup_by_name, "GopathCacheAutoRebuild")
    autocmds.setup(require("gopath.config").get())
  end)

  -- ── open.help ──────────────────────────────────────────────────────────────

  local help_open = require("gopath.open.help")

  ---Record every `vim.cmd` string issued while `fn` runs.
  ---@param fail_pattern string|nil  commands matching this raise, as a missing tag would
  ---@param fn fun()
  ---@return string[]
  local function with_cmd_recorder(fail_pattern, fn)
    local issued = {}
    H.with_field(vim, "cmd", function(cmd)
      issued[#issued + 1] = cmd
      if fail_pattern and type(cmd) == "string" and cmd:find(fail_pattern) then
        error("E149: Sorry, no help for " .. cmd)
      end
    end, fn)
    return issued
  end

  H.check("help.open: the window target decides the Ex command", function()
    H.eq(
      with_cmd_recorder(nil, function()
        help_open.open({ kind = "help", subject = "vim.api" }, { target = "tab" })
      end)[1],
      "tab help vim.api"
    )

    H.eq(
      with_cmd_recorder(nil, function()
        help_open.open({ kind = "help", subject = "vim.api" }, { target = "window" })
      end)[1],
      "belowright help vim.api"
    )

    H.eq(
      with_cmd_recorder(nil, function()
        help_open.open({ kind = "help", subject = "vim.api" }, nil)
      end)[1],
      "help vim.api",
      "no opts at all means the current window"
    )
  end)

  H.check("help.open: subjects are tried in order, first success wins", function()
    local issued = with_cmd_recorder("help nvim_absent%(%)", function()
      help_open.open({ kind = "help", subjects = { "nvim_absent()", "vim.api" } }, {})
    end)
    H.eq(#issued, 2, "the second candidate was needed")
    H.eq(issued[1], "help nvim_absent()")
    H.eq(issued[2], "help vim.api")
  end)

  H.check("help.open: a failing subject is retried with its parens toggled", function()
    local issued = with_cmd_recorder("help expand$", function()
      help_open.open({ kind = "help", subject = "expand" }, {})
    end)
    H.eq(issued[1], "help expand")
    H.eq(issued[2], "help expand()", "the '()' variant is the second attempt")
  end)

  H.check("help.open: everything failing ends in helpgrep, then the quickfix list", function()
    H.with_field(vim.fn, "getqflist", function()
      return { size = 3 }
    end, function()
      local issued = with_cmd_recorder("^[a-z ]*help ", function()
        help_open.open({ kind = "help", subject = "nothing_at_all" }, {})
      end)
      local text = table.concat(issued, "\n")
      H.match(text, "silent! helpgrep nothing_at_all")
      H.match(text, "cfirst", "and it jumps to the first match")
    end)
  end)

  H.check("help.open: an empty quickfix list lands on the generic page", function()
    H.with_field(vim.fn, "getqflist", function()
      return { size = 0 }
    end, function()
      local issued = with_cmd_recorder("^[a-z ]*help nothing", function()
        help_open.open({ kind = "help", subject = "nothing_at_all" }, {})
      end)
      H.eq(issued[#issued], "help vim.api", "the documented last-resort landing page")
    end)
  end)

  H.check("help.open: a non-help result is ignored", function()
    local issued = with_cmd_recorder(nil, function()
      help_open.open({ kind = "file", path = "/a.lua" }, {})
      ---@diagnostic disable-next-line: param-type-mismatch
      help_open.open(nil, {})
    end)
    H.same(issued, {}, "nothing was issued")
  end)

  -- ── health ─────────────────────────────────────────────────────────────────

  H.check("health.check: reports every section without erroring", function()
    local report = {}
    local recorder = {
      start = function(s)
        report[#report + 1] = { "start", s }
      end,
      ok = function(s)
        report[#report + 1] = { "ok", s }
      end,
      warn = function(s)
        report[#report + 1] = { "warn", s }
      end,
      error = function(s)
        report[#report + 1] = { "error", s }
      end,
      info = function(s)
        report[#report + 1] = { "info", s }
      end,
    }
    H.with_field(vim, "health", recorder, function()
      -- health.lua resolves vim.health.* into upvalues at load time.
      local health = require("gopath.health")
      health.check()
    end, { unload = { "gopath.health" } })
    -- (with_field cannot unload; do it explicitly.)
    H.fresh("gopath.health")

    local sections, text = {}, {}
    for _, entry in ipairs(report) do
      if entry[1] == "start" then sections[#sections + 1] = entry[2] end
      text[#text + 1] = tostring(entry[2])
    end
    local joined = table.concat(text, "\n")

    H.contains(sections, "Neovim version")
    H.contains(sections, "External CLI tools")
    H.contains(sections, "LSP")
    H.contains(sections, "which-key")
    H.contains(sections, "open.nvim")
    H.contains(sections, "lib.nvim")
    H.contains(sections, "filetree.nvim")
    H.contains(sections, "pdfport.nvim")
    H.contains(sections, "Tree-sitter")
    H.contains(sections, "Configuration")
    H.match(joined, "Neovim %d+%.%d+%.%d+", "the running version is named")
    H.match(joined, "lib%.nvim detected", "lib.nvim is on the runtimepath in this run")
  end)

  -- ── setup ──────────────────────────────────────────────────────────────────

  H.check("setup: merges the config and wires the bindings exactly once", function()
    H.config_sandbox(function()
      local bound
      H.with_modules({
        ["gopath.bindings"] = {
          setup = function(cfg)
            bound = cfg
          end,
        },
        ["gopath.truncated.cache"] = {
          setup = function() end,
          load_from_disk = function() end,
          start_periodic_refresh = function() end,
          needs_refresh = function()
            return false
          end,
          build_async = function() end,
        },
        ["lib.nvim.deps"] = { show_once = function() end },
      }, function()
        local gopath = require("gopath")
        gopath.setup({ lsp_timeout_ms = 321 })
        H.truthy(bound, "the bindings layer was set up")
        H.eq(bound.lsp_timeout_ms, 321, "with the merged config, not the raw options")
        H.eq(bound.mode, "hybrid", "including the defaults")
      end, { unload = { "gopath" } })
      H.fresh("gopath")
    end)
  end)

  H.check(
    "setup: the cache subsystem is configured from `truncated`, and skipped when off",
    function()
      H.config_sandbox(function()
        local seen = {}
        local cache_double = {
          setup = function(opts)
            seen.setup = opts
          end,
          load_from_disk = function()
            seen.loaded = true
          end,
          start_periodic_refresh = function(interval)
            seen.interval = interval
          end,
          needs_refresh = function()
            return false
          end,
          build_async = function() end,
        }
        H.with_modules({
          ["gopath.bindings"] = { setup = function() end },
          ["gopath.truncated.cache"] = cache_double,
          ["lib.nvim.deps"] = { show_once = function() end },
        }, function()
          local gopath = require("gopath")
          gopath.setup({
            truncated = {
              enable = true,
              use_cache = true,
              cache_refresh_interval = 111,
              max_depth = 4,
              cache_roots = { "/r" },
              excluded_dirs = { "x" },
            },
          })
          H.same(seen.setup.roots, { "/r" })
          H.eq(seen.setup.max_depth, 4)
          H.same(seen.setup.excluded_dirs, { "x" })
          H.eq(seen.loaded, true, "the persisted index is loaded up front")
          H.eq(seen.interval, 111, "and the refresh interval is forwarded")

          seen = {}
          gopath.setup({ truncated = { enable = false } })
          H.is_nil(seen.setup, "nothing is configured when the feature is off")
        end, { unload = { "gopath" } })
        H.fresh("gopath")
      end)
    end
  )

  H.check("setup: use_cache = false skips the periodic refresh even with the feature on", function()
    H.config_sandbox(function()
      local seen = {}
      H.with_modules({
        ["gopath.bindings"] = { setup = function() end },
        ["gopath.truncated.cache"] = {
          setup = function() end,
          load_from_disk = function() end,
          start_periodic_refresh = function(interval)
            seen.interval = interval
          end,
          needs_refresh = function()
            return false
          end,
          build_async = function() end,
        },
        ["lib.nvim.deps"] = { show_once = function() end },
      }, function()
        local gopath = require("gopath")
        gopath.setup({ truncated = { enable = true, use_cache = false } })
        H.is_nil(seen.interval, "use_cache = false means no periodic refresh is scheduled")
      end, { unload = { "gopath" } })
      H.fresh("gopath")
    end)
  end)

  H.check("setup: a stale cache schedules exactly one deferred async rebuild", function()
    H.config_sandbox(function()
      local deferred_ms, built
      H.with_modules({
        ["gopath.bindings"] = { setup = function() end },
        ["gopath.truncated.cache"] = {
          setup = function() end,
          load_from_disk = function() end,
          start_periodic_refresh = function() end,
          needs_refresh = function(max_age)
            H.eq(max_age, 3600, "the default max_cache_age")
            return true
          end,
          build_async = function(cb)
            built = true
            cb(true)
          end,
        },
        ["lib.nvim.deps"] = { show_once = function() end },
      }, function()
        H.with_field(vim, "defer_fn", function(fn, ms)
          deferred_ms = ms
          fn()
        end, function()
          local gopath = require("gopath")
          gopath.setup({ truncated = { enable = true, use_cache = true } })
        end)
      end, { unload = { "gopath" } })
      H.fresh("gopath")
      H.eq(deferred_ms, 2000, "the initial build is scheduled 2s out, not run inline")
      H.truthy(built, "build_async ran once the deferred timer fired")
    end)
  end)

  H.check("setup: the one-time deps popup is skipped when deps_popup = false", function()
    H.config_sandbox(function()
      local shown = 0
      H.with_modules({
        ["gopath.bindings"] = { setup = function() end },
        ["gopath.truncated.cache"] = { setup = function() end },
        ["lib.nvim.deps"] = {
          show_once = function()
            shown = shown + 1
          end,
        },
      }, function()
        local gopath = require("gopath")
        gopath.setup({ deps_popup = false, truncated = { enable = false } })
        H.eq(shown, 0, "opted out right in the spec")
        -- `truncated.enable` repeated: setup() resets to defaults on every
        -- call (LUA-87), so leaving it out here would flip the cache
        -- subsystem back on and pull in cache-double methods this test
        -- never stubbed.
        gopath.setup({ deps_popup = true, truncated = { enable = false } })
        H.eq(shown, 1, "and shown otherwise")
      end, { unload = { "gopath" } })
      H.fresh("gopath")
    end)
  end)

  H.check("setup: an older lib.nvim without the deps module does not break setup()", function()
    H.config_sandbox(function()
      H.with_modules({
        ["gopath.bindings"] = { setup = function() end },
        ["gopath.truncated.cache"] = { setup = function() end },
        ["lib.nvim.deps"] = false,
      }, function()
        local gopath = require("gopath")
        gopath.setup({ truncated = { enable = false } })
        H.truthy(true, "setup() completed")
      end, { unload = { "gopath" } })
      H.fresh("gopath")
    end)
  end)

  H.check("the public API: resolve() delegates, commands is the command table", function()
    local gopath = require("gopath")
    H.eq(gopath.commands, require("gopath.commands"), "exposed for custom keymaps")
    H.eq(type(gopath.commands.resolve_and_open), "function")

    local asked
    H.with_modules({
      ["gopath.resolve"] = {
        resolve_at_cursor = function(opts)
          asked = opts
          return { kind = "file", path = "/x" }, nil
        end,
      },
    }, function()
      local fresh = require("gopath")
      local r = fresh.resolve({ order = { "builtin" } })
      H.eq(r.path, "/x")
      H.same(asked.order, { "builtin" }, "the options are passed straight through")
    end, { unload = { "gopath" } })
    H.fresh("gopath")
  end)

  -- Re-register the real bindings, so the suite ends in the state
  -- `require("gopath").setup({})` left at the start.
  require("gopath.bindings").setup(require("gopath.config").get())
end
