-- scripts/ci/specs/task_id_spec.lua
-- The task-id resolver: `gF` on `<area>/<slug>` opens the task file, through
-- tasks.nvim's `tasks_nvim.resolve` -- and without tasks.nvim, nothing.
--
-- tasks.nvim is not checked out in CI, and what an id is and where its task
-- lives is its question, not this plugin's (its own spec, tasks_resolve_spec,
-- pins that). So `tasks_nvim.resolve` is a stand-in here that answers with the
-- targets a real vault would; what is pinned is what gopath makes of them.

---@param H table
return function(H)
  local TASK = require("gopath.resolvers.common.task_id")

  ---A `tasks_nvim.resolve` stand-in answering `targets` and recording calls.
  ---@param targets table[]
  ---@param calls table
  ---@return table
  local function fake_tasks(targets, calls)
    return {
      resolve_at = function(buf, row, col, opts)
        calls[#calls + 1] = { buf = buf, row = row, col = col, opts = opts }
        return targets
      end,
    }
  end

  local function target(path, kind, root)
    return {
      kind = kind or "task",
      id = "lib.nvim/alpha",
      path = path,
      line = 1,
      title = "Alpha",
      root = root or "/vault",
    }
  end

  H.check("task id: the open task file, as an existing file result", function()
    local file = H.tmpdir() .. "/alpha.md"
    H.write(file, { "---", "title: Alpha", "---" })
    local calls = {}
    H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({ target(file) }, calls) }, function()
      TASK._reset()
      H.line_at("todo: lib.nvim/alpha next", "lib.nvim", { filetype = "markdown" })
      local r = TASK.resolve()
      H.truthy(r, "a result")
      H.eq(r.path, (file:gsub("\\", "/")))
      H.eq(r.kind, "file")
      H.eq(r.source, "tasks")
      H.eq(r.exists, true)
      H.same(r.range, { line = 1, col = 1 })
      H.eq(r.task.id, "lib.nvim/alpha")
      H.is_nil(r.alternatives, "one target, no choice")
      H.eq(calls[1].row, 1, "asked at the cursor row")
      H.is_nil(calls[1].opts.roots, "no vaults configured: tasks.nvim's own")
    end)
    TASK._reset()
  end)

  H.check("task id: tasks.vaults is handed over as the roots to look in", function()
    H.config_sandbox(function(config)
      config.setup({ tasks = { vaults = { "/a", "/b" } } })
      local calls = {}
      H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({}, calls) }, function()
        TASK._reset()
        H.line_at("lib.nvim/alpha", "lib", {})
        H.is_nil(TASK.resolve(), "no target: no result")
        H.same(calls[1].opts.roots, { "/a", "/b" })
      end)
    end)
    TASK._reset()
  end)

  H.check("task id: without tasks.nvim nothing happens, and nothing is said", function()
    H.with_modules({ ["tasks_nvim.resolve"] = false }, function()
      TASK._reset()
      H.line_at("todo: lib.nvim/alpha next", "lib.nvim", {})
      local notes = H.capture_notify(function()
        H.is_nil(TASK.resolve())
      end)
      H.eq(#notes, 0, "no warning, no error")
    end)
    TASK._reset()
  end)

  H.check("task id: tasks.enable = false does not even ask", function()
    H.config_sandbox(function(config)
      config.setup({ tasks = { enable = false } })
      local calls = {}
      H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({ target("/x.md") }, calls) }, function()
        TASK._reset()
        H.line_at("lib.nvim/alpha", "lib", {})
        H.is_nil(TASK.resolve())
        H.eq(#calls, 0)
      end)
    end)
    TASK._reset()
  end)

  H.check("task id: several targets come back as alternatives", function()
    local calls = {}
    local targets = { target("/v/open.md", "task"), target("/v/done.md", "done") }
    H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks(targets, calls) }, function()
      TASK._reset()
      H.line_at("lib.nvim/alpha", "lib", {})
      local r = TASK.resolve()
      H.eq(#r.alternatives, 2)
      H.eq(r.alternatives[1].path, "/v/open.md")
      H.eq(r.alternatives[2].task.kind, "done")
    end)
    TASK._reset()
  end)

  H.check("pipeline: a task id wins before filetoken reads it as a path", function()
    local file = H.tmpdir() .. "/alpha.md"
    H.write(file, { "" })
    H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({ target(file) }, {}) }, function()
      TASK._reset()
      H.line_at("see lib.nvim/alpha here", "lib.nvim", { filetype = "markdown" })
      local r = require("gopath.resolve").resolve_at_cursor({})
      H.eq(r.source, "tasks", "not a filetoken guess at a relative path")
    end, { unload = { "gopath.resolve" } })
    TASK._reset()
    H.fresh("gopath.resolve")
  end)

  H.check("goto: several targets are offered, and the pick is opened", function()
    local opened = {}
    local alternatives = {
      {
        kind = "file",
        path = "/v/open.md",
        exists = true,
        task = { id = "a/b", kind = "task", title = "T", root = "/v" },
      },
      {
        kind = "file",
        path = "/v/done.md",
        exists = true,
        task = { id = "a/b", kind = "done", title = "T", root = "/v" },
      },
    }
    local res = vim.tbl_extend("force", alternatives[1], { alternatives = alternatives })
    H.with_modules({
      ["gopath.resolve"] = {
        resolve_at_cursor = function()
          return res, nil
        end,
      },
      ["gopath.open"] = {
        open = function(r, mode)
          opened[#opened + 1] = { path = r.path, mode = mode }
        end,
      },
      ["ui.kit"] = false,
    }, function()
      local commands = require("gopath.commands")
      local seen = H.with_ui_select(function(items)
        return items[2]
      end, function()
        commands.goto_at_cursor("vsplit")
      end)
      H.eq(#seen, 1, "asked once")
      H.eq(#seen[1].items, 2)
      H.match(seen[1].opts.format_item(seen[1].items[2]), "finished")
      H.same(opened, { { path = "/v/done.md", mode = "vsplit" } })

      opened = {}
      H.with_ui_select(nil, function()
        commands.goto_at_cursor("edit")
      end)
      H.same(opened, {}, "a dismissed picker opens nothing")
    end, { unload = { "gopath.commands" } })
    H.fresh("gopath.commands")
  end)

  -- ── found in review ───────────────────────────────────────────────────────

  H.check("task id: tasks = false turns it off, like enable = false", function()
    H.config_sandbox(function(config)
      config.setup({ tasks = false })
      local calls = {}
      H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({ target("/x.md") }, calls) }, function()
        TASK._reset()
        H.line_at("lib.nvim/alpha", "lib", {})
        H.is_nil(TASK.resolve())
        H.eq(#calls, 0, "not asked")
        H.eq(TASK.status(), false)
      end)
    end)
    TASK._reset()
  end)

  H.check("task id: tasks.nvim loaded after a miss is found without a restart", function()
    H.with_modules({ ["tasks_nvim.resolve"] = false }, function()
      TASK._reset()
      H.line_at("lib.nvim/alpha", "lib", {})
      H.is_nil(TASK.resolve(), "not there yet")
    end)
    -- what a `packadd` does: the module becomes loadable, 'runtimepath' moves
    local saved_rtp = vim.o.runtimepath
    vim.opt.runtimepath:append(H.tmpdir())
    H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({ target("/later.md") }, {}) }, function()
      local r = TASK.resolve()
      H.truthy(r, "found on the next lookup")
      H.eq(r.path, "/later.md")
    end)
    vim.o.runtimepath = saved_rtp
    TASK._reset()
  end)

  H.check("task id: ~ and $VAR in tasks.vaults are expanded", function()
    H.config_sandbox(function(config)
      vim.env.GOPATH_SPEC_VAULT = "/expanded/vault"
      config.setup({ tasks = { vaults = { "$GOPATH_SPEC_VAULT", "~/v" } } })
      local calls = {}
      H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({}, calls) }, function()
        TASK._reset()
        H.line_at("lib.nvim/alpha", "lib", {})
        TASK.resolve()
        H.eq(calls[1].opts.roots[1], "/expanded/vault")
        H.falsy(calls[1].opts.roots[2]:find("~", 1, true), "the home directory, not a literal ~")
      end)
      vim.env.GOPATH_SPEC_VAULT = nil
    end)
    TASK._reset()
  end)

  H.check("task id: status says when tasks.nvim has nothing to resolve against", function()
    H.with_modules({
      ["tasks_nvim.resolve"] = fake_tasks({}, {}),
      ["tasks_nvim.vault"] = {
        root = function()
          return nil, "vault not found"
        end,
      },
    }, function()
      TASK._reset()
      local ok, message = TASK.status()
      H.eq(ok, false)
      H.match(message, "no vault")
    end)
    H.config_sandbox(function(config)
      local dir = H.tmpdir()
      config.setup({ tasks = { vaults = { dir } } })
      H.with_modules({ ["tasks_nvim.resolve"] = fake_tasks({}, {}) }, function()
        TASK._reset()
        local ok, message = TASK.status()
        H.eq(ok, true)
        H.match(message, "1 vault")
      end)
    end)
    TASK._reset()
  end)
end
