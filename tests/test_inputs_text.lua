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

T["text input"] = MiniTest.new_set()

T["text input"]["seeds default value"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.text').new({ name = 'x', label = 'X', default = 'hello' })
    _G.t:mount({ row = 5, col = 5, width = 30 })
  ]])
  eq(child.lua_get([[_G.t:value()]]), "hello")
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "hello" })
end

T["text input"]["reflects buffer edits"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.text').new({ name = 'x', label = 'X' })
    _G.t:mount({ row = 5, col = 5, width = 30 })
    vim.api.nvim_buf_set_lines(_G.t.buf, 0, -1, false, { 'typed text' })
  ]])
  eq(child.lua_get([[_G.t:value()]]), "typed text")
end

T["text input"]["unmount caches value and closes window"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.text').new({ name = 'x', label = 'X', default = 'abc' })
    _G.t:mount({ row = 5, col = 5, width = 30 })
    vim.api.nvim_buf_set_lines(_G.t.buf, 0, -1, false, { 'updated' })
    _G.t:unmount()
  ]])
  eq(child.lua_get([[_G.t.win]]), vim.NIL)
  eq(child.lua_get([[_G.t.buf]]), vim.NIL)
  eq(child.lua_get([[_G.t:value()]]), "updated")
end

T["text input"]["height is 1"] = function()
  child.lua([[_G.t = require('input-form.inputs.text').new({ name = 'x', label = 'X' })]])
  eq(child.lua_get([[_G.t:height()]]), 1)
end

return T
