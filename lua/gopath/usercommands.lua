---@module 'gopath.usercommands'
--- Automatic user command registration based on config.

local M = {}

---Setup user commands if not disabled in config
---@param config GopathOptions
function M.setup(config)
	if config.commands == false then
		return -- User disabled all commands
	end

	local cmds = config.commands or {}
	local commands = require("gopath.commands")

	-- :GopathResolve - Show resolution result
	if cmds.resolve ~= false then
		vim.api.nvim_create_user_command("GopathResolve", function()
			commands.debug_under_cursor()
		end, {
			desc = "Gopath: Show resolution result for symbol under cursor",
		})
	end

	-- :GopathOpen [mode] - Open with specified mode
	if cmds.open ~= false then
		vim.api.nvim_create_user_command("GopathOpen", function(opts)
			local mode = opts.args and opts.args ~= "" and opts.args or "edit"

			-- Normalize mode aliases
			if mode == "window_vsplit" or mode == "vsplit" then
				mode = "vsplit"
			elseif mode == "window" or mode == "split" then
				mode = "window"
			end

			commands.resolve_and_open(mode)
		end, {
			nargs = "?",
			complete = function()
				return { "edit", "window", "vsplit", "tab" }
			end,
			desc = "Gopath: Open target (edit|window|vsplit|tab)",
		})
	end

	-- :GopathCopy - Copy location to clipboard
	if cmds.copy ~= false then
		vim.api.nvim_create_user_command("GopathCopy", function()
			commands.resolve_and_copy()
		end, {
			desc = "Gopath: Copy path:line:col to clipboard",
		})
	end

	-- :GopathDebug - Debug resolution under cursor
	if cmds.debug ~= false then
		vim.api.nvim_create_user_command("GopathDebug", function()
			commands.debug_under_cursor()
		end, {
			desc = "Gopath: Debug resolution under cursor",
		})
	end

	if config.truncated and config.truncated.enable then
		-- === :GopathCacheBuild ===
		-- Rebuild filesystem cache from scratch
		vim.api.nvim_create_user_command("GopathCacheBuild", function()
			local cache = require("gopath.truncated.cache")
			vim.notify("[gopath] Building filesystem cache...", vim.log.levels.INFO)

			cache.build_async(function(success)
				if success then
					vim.notify("[gopath] Cache build complete", vim.log.levels.INFO)
				else
					vim.notify("[gopath] Cache build failed", vim.log.levels.ERROR)
				end
			end)
		end, {
			desc = "Gopath: Rebuild filesystem cache",
		})

		-- === :GopathCacheInfo ===
		-- Show cache statistics and status
		vim.api.nvim_create_user_command("GopathCacheInfo", function()
			local cache = require("gopath.truncated.cache")
			cache.load_from_disk()

			local state = cache._get_state()
			local age = state.last_built and (os.time() - state.last_built) or "never"

			print("=== Gopath Cache Info ===")
			print("  Files indexed:", #state.paths)
			print("  Last built:", state.last_built and os.date("%Y-%m-%d %H:%M:%S", state.last_built) or "never")
			print(
				"  Age:",
				type(age) == "number" and string.format("%d seconds (%d minutes)", age, math.floor(age / 60)) or age
			)
			print("  Needs refresh:", cache.needs_refresh() and "yes" or "no")
			print("  Building:", state.building and "yes" or "no")
			print("=========================")
		end, {
			desc = "Gopath: Show cache information",
		})

		vim.api.nvim_create_user_command("GopathCacheAddRoot", function(args)
			local dir = args.args

			if not dir or dir == "" then
				vim.notify("[gopath] Usage: :GopathCacheAddRoot <directory>", vim.log.levels.ERROR)
				return
			end

			dir = vim.fn.expand(dir)

			local cache = require("gopath.truncated.cache")
			cache.add_root(dir, true) -- true = rebuild immediately
		end, {
			nargs = 1,
			complete = "dir",
			desc = "Gopath: Add directory to cache roots",
		})
	end
end

return M
