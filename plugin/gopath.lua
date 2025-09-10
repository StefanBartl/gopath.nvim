if vim.g.loaded_gopath then return end
vim.g.loaded_gopath = true

local GP = require("gopath")
local CMD = require("gopath.commands")

vim.api.nvim_create_user_command("GopathResolve", function()
  local res, err = GP.resolve({})
  if not res then
    vim.notify("[gopath] no match: " .. (err or "unknown"), vim.log.levels.WARN)
  else
    print(vim.inspect(res))
  end
end, {})

vim.api.nvim_create_user_command("GopathOpen", function(args)
  local kind = args.args ~= "" and args.args or "edit"
  if kind == "window_vsplit" then
    -- Special case: call window opener with vsplit=true
    local res = select(1, GP.resolve({}))
    if not res then
      vim.notify("[gopath] no match", vim.log.levels.WARN)
      return
    end
    require("gopath.open.window").open(res, { vsplit = true })
  else
    CMD.resolve_and_open(kind)
  end
end, { nargs = "?" })

vim.api.nvim_create_user_command("GopathCopy", function()
  CMD.resolve_and_copy()
end, {})

vim.api.nvim_create_user_command("GopathDebugUnderCursor", function()
  CMD.debug_under_cursor()
end, {})
