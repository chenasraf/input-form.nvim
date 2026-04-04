local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")

local child = helpers.new_child_neovim()
local eq = helpers.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[require('input-form').setup()]])
    end,
    post_once = child.stop,
  },
})

T["multiline input"] = MiniTest.new_set()

T["multiline input"]["uses config default height"] = function()
  child.lua([[_G.t = require('input-form.inputs.multiline').new({ name = 'm', label = 'M' })]])
  eq(child.lua_get([[_G.t:height()]]), 5)
end

T["multiline input"]["respects spec-level height"] = function()
  child.lua([[_G.t = require('input-form.inputs.multiline').new({ name = 'm', label = 'M', height = 3 })]])
  eq(child.lua_get([[_G.t:height()]]), 3)
end

T["multiline input"]["splits default on newlines"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.multiline').new({ name = 'm', label = 'M', default = 'line1\nline2\nline3' })
    _G.t:mount({ row = 5, col = 5, width = 30 })
  ]])
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "line1", "line2", "line3" })
  eq(child.lua_get([[_G.t:value()]]), "line1\nline2\nline3")
end

T["multiline input"]["joins buffer lines on value"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.multiline').new({ name = 'm', label = 'M', height = 3 })
    _G.t:mount({ row = 5, col = 5, width = 30 })
    vim.api.nvim_buf_set_lines(_G.t.buf, 0, -1, false, { 'a', 'b', 'c' })
  ]])
  eq(child.lua_get([[_G.t:value()]]), "a\nb\nc")
end

return T
