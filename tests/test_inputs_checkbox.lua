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

T["checkbox input"] = MiniTest.new_set()

T["checkbox input"]["defaults to false"] = function()
  child.lua([[_G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C' })]])
  eq(child.lua_get([[_G.t:value()]]), false)
end

T["checkbox input"]["honors explicit default = true"] = function()
  child.lua(
    [[_G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C', default = true })]]
  )
  eq(child.lua_get([[_G.t:value()]]), true)
end

T["checkbox input"]["height is 1"] = function()
  child.lua([[_G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C' })]])
  eq(child.lua_get([[_G.t:height()]]), 1)
end

T["checkbox input"]["mount renders inline glyph + label"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C' })
    _G.t:mount({ row = 5, col = 5, width = 20 })
  ]])
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "☐ C" })
  child.lua([[
    _G.t2 = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C', default = true })
    _G.t2:mount({ row = 8, col = 5, width = 20 })
  ]])
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t2.buf, 0, -1, false)]]), { "☑ C" })
end

T["checkbox input"]["is borderless"] = function()
  child.lua([[_G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C' })]])
  eq(child.lua_get([[_G.t:is_bordered()]]), false)
end

T["checkbox input"]["toggle flips the value and re-renders"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'Agree' })
    _G.t:mount({ row = 5, col = 5, width = 20 })
    _G.t:toggle()
  ]])
  eq(child.lua_get([[_G.t:value()]]), true)
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "☑ Agree" })
  child.lua([[_G.t:toggle()]])
  eq(child.lua_get([[_G.t:value()]]), false)
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "☐ Agree" })
end

T["checkbox input"]["renders error inline after label"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'Agree' })
    _G.t:mount({ row = 5, col = 5, width = 30 })
    _G.t._error = "(must be checked)"
    _G.t:_render_display()
  ]])
  eq(
    child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]),
    { "☐ Agree (must be checked)" }
  )
  -- Clearing the error removes the suffix.
  child.lua([[_G.t._error = nil; _G.t:_render_display()]])
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "☐ Agree" })
end

T["checkbox input"]["set updates the value idempotently"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C' })
    _G.t:mount({ row = 5, col = 5, width = 20 })
    _G.changes = 0
    _G.t._on_change = function() _G.changes = _G.changes + 1 end
    _G.t:set(true)
    _G.t:set(true) -- no-op
    _G.t:set(false)
  ]])
  eq(child.lua_get([[_G.t:value()]]), false)
  eq(child.lua_get([[_G.changes]]), 2)
end

T["checkbox input"]["display buffer is read-only"] = function()
  child.lua([[
    _G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C' })
    _G.t:mount({ row = 5, col = 5, width = 20 })
  ]])
  eq(child.lua_get([[vim.bo[_G.t.buf].modifiable]]), false)
end

T["checkbox input"]["custom glyphs from style config"] = function()
  child.lua([[
    require('input-form').setup({
      style = { checkbox = { checked = '✔', unchecked = '·' } }
    })
    _G.t = require('input-form.inputs.checkbox').new({ name = 'c', label = 'C' })
    _G.t:mount({ row = 5, col = 5, width = 20 })
  ]])
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "· C" })
  child.lua([[_G.t:toggle()]])
  eq(child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)]]), { "✔ C" })
end

return T
