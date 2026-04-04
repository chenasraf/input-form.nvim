local MiniTest = require("mini.test")
-- Partially adapted from https://github.com/echasnovski/mini.nvim
local Helpers = {}

Helpers.expect = vim.deepcopy(MiniTest.expect)

local function errorMessage(str, pattern)
  return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
end

--- Check equality of a global `field` against `value` in the given `child` process.
Helpers.expect.global_equality = MiniTest.new_expectation(
  "variable in child process matches",
  function(child, field, value)
    return Helpers.expect.equality(child.lua_get(field), value)
  end,
  errorMessage
)

--- Check type equality of a global `field` against `value` in the given `child` process.
Helpers.expect.global_type_equality = MiniTest.new_expectation(
  "variable type in child process matches",
  function(child, field, value)
    return Helpers.expect.global_equality(child, "type(" .. field .. ")", value)
  end,
  errorMessage
)

--- Check equality of a config `field` against `value` in the given `child` process.
Helpers.expect.config_equality = MiniTest.new_expectation(
  "config option matches",
  function(child, field, value)
    return Helpers.expect.global_equality(
      child,
      "require('input-form.config').options." .. field,
      value
    )
  end,
  errorMessage
)

Helpers.expect.config_type_equality = MiniTest.new_expectation(
  "config option type matches",
  function(child, field, value)
    return Helpers.expect.global_equality(
      child,
      "type(require('input-form.config').options." .. field .. ")",
      value
    )
  end,
  errorMessage
)

Helpers.expect.match = MiniTest.new_expectation("string matching", function(str, pattern)
  return str:find(pattern) ~= nil
end, errorMessage)

Helpers.expect.no_match = MiniTest.new_expectation("no string matching", function(str, pattern)
  return str:find(pattern) == nil
end, errorMessage)

--- Wrapper around `MiniTest.new_child_neovim` with a few convenience helpers.
Helpers.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  local prevent_hanging = function(method)
    if not child.is_blocked() then
      return
    end
    error(string.format("Can not use `child.%s` because child process is blocked.", method))
  end

  child.setup = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })
    child.bo.readonly = false
  end

  child.set_lines = function(arr, start, finish)
    prevent_hanging("set_lines")
    if type(arr) == "string" then
      arr = vim.split(arr, "\n")
    end
    child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
  end

  child.get_lines = function(start, finish)
    prevent_hanging("get_lines")
    return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
  end

  return child
end

--- Initialize the plugin inside a child process, optionally with a config table literal.
function Helpers.init_plugin(child, config)
  config = config or ""
  child.lua([[require('input-form').setup(]] .. config .. [[)]])
end

return Helpers
