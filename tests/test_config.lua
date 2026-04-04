local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")

local child = helpers.new_child_neovim()
local eq_global, eq_config = helpers.expect.global_equality, helpers.expect.config_equality
local eq_type_global, eq_type_config =
  helpers.expect.global_type_equality, helpers.expect.config_type_equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

T["setup()"] = MiniTest.new_set()

T["setup()"]["exposes defaults"] = function()
  child.lua([[require('input-form').setup()]])

  eq_type_global(child, "_G.InputForm", "table")
  eq_type_config(child, "window", "table")
  eq_config(child, "window.border", "rounded")
  eq_config(child, "window.width", 60)
  eq_config(child, "window.padding", 0)
  eq_config(child, "window.gap", 0)
  eq_config(child, "keymaps.next", "<Tab>")
  eq_config(child, "keymaps.prev", "<S-Tab>")
  eq_config(child, "keymaps.submit", "<C-s>")
  eq_config(child, "keymaps.cancel", "<Esc>")
  eq_config(child, "keymaps.open_select", "<CR>")
  eq_config(child, "select.max_height", 10)
  eq_config(child, "multiline.height", 5)
end

T["setup()"]["deep-merges user options"] = function()
  helpers.init_plugin(
    child,
    [[{
      window = { border = "single", width = 80 },
      keymaps = { submit = "<C-y>" },
    }]]
  )

  eq_config(child, "window.border", "single")
  eq_config(child, "window.width", 80)
  -- untouched default preserved
  eq_config(child, "window.title", " Form ")
  eq_config(child, "keymaps.submit", "<C-y>")
  -- untouched keymap defaults preserved
  eq_config(child, "keymaps.next", "<Tab>")
end

T["setup()"]["setup() without doc dir does not error"] = function()
  -- setup should be safe even if doc/ is missing (uses pcall around helptags)
  child.lua([[require('input-form').setup()]])
  eq_global(child, "type(_G.InputForm.create_form)", "function")
end

return T
