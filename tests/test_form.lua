local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")

local child = helpers.new_child_neovim()
local eq = helpers.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.o.lines = 40
      child.o.columns = 120
      child.lua([[require('input-form').setup()]])
      child.lua([[
        _G.make_form = function()
          return require('input-form').create_form({
            inputs = {
              { name = 'id',    label = 'Enter ID',     type = 'text',      default = 'sample ID' },
              { name = 'pick',  label = 'Pick one',     type = 'select',
                options = { { id = 'a', label = 'Alpha' }, { id = 'b', label = 'Beta' } },
                default = 'a',
              },
              { name = 'body',  label = 'Multiline',    type = 'multiline', default = 'x\ny' },
            },
            on_submit = function(r) _G.submit_result = r end,
            on_cancel = function() _G.cancel_called = true end,
          })
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["form"] = MiniTest.new_set()

T["form"]["create_form does not open any windows"] = function()
  child.lua([[_G.f = _G.make_form()]])
  eq(child.lua_get([[_G.f._visible]]), false)
  eq(child.lua_get([[#_G.f._inputs]]), 3)
end

T["form"]["show() opens parent + one window per input"] = function()
  child.lua([[_G.f = _G.make_form(); _G.f:show()]])
  eq(child.lua_get([[_G.f._visible]]), true)
  eq(child.lua_get([[vim.api.nvim_win_is_valid(_G.f._parent_win)]]), true)
  eq(child.lua_get([[vim.api.nvim_win_is_valid(_G.f._inputs[1].win)]]), true)
  eq(child.lua_get([[vim.api.nvim_win_is_valid(_G.f._inputs[2].win)]]), true)
  eq(child.lua_get([[vim.api.nvim_win_is_valid(_G.f._inputs[3].win)]]), true)
  -- First input is focused.
  eq(child.lua_get([[vim.api.nvim_get_current_win() == _G.f._inputs[1].win]]), true)
end

T["form"]["show() is idempotent"] = function()
  child.lua([[
    _G.f = _G.make_form()
    _G.f:show()
    _G.w1 = _G.f._parent_win
    _G.f:show()
    _G.w2 = _G.f._parent_win
  ]])
  eq(child.lua_get([[_G.w1 == _G.w2]]), true)
end

T["form"]["focus_next / focus_prev cycle and wrap"] = function()
  child.lua([[_G.f = _G.make_form(); _G.f:show()]])
  eq(child.lua_get([[_G.f._focus_idx]]), 1)
  child.lua([[_G.f:focus_next()]])
  eq(child.lua_get([[_G.f._focus_idx]]), 2)
  child.lua([[_G.f:focus_next()]])
  eq(child.lua_get([[_G.f._focus_idx]]), 3)
  child.lua([[_G.f:focus_next()]]) -- wraps
  eq(child.lua_get([[_G.f._focus_idx]]), 1)
  child.lua([[_G.f:focus_prev()]]) -- wraps backwards
  eq(child.lua_get([[_G.f._focus_idx]]), 3)
end

T["form"]["submit collects values and closes windows"] = function()
  child.lua([[
    _G.f = _G.make_form()
    _G.f:show()
    -- Modify the text input buffer.
    vim.api.nvim_buf_set_lines(_G.f._inputs[1].buf, 0, -1, false, { 'new id' })
    -- Change the select.
    _G.f._inputs[2]:select_id('b')
    -- Modify the multiline.
    vim.api.nvim_buf_set_lines(_G.f._inputs[3].buf, 0, -1, false, { 'one', 'two' })
    _G.f:submit()
  ]])
  eq(child.lua_get([[_G.submit_result]]), { id = "new id", pick = "b", body = "one\ntwo" })
  eq(child.lua_get([[_G.f._visible]]), false)
end

T["form"]["cancel invokes on_cancel and closes windows"] = function()
  child.lua([[
    _G.f = _G.make_form()
    _G.f:show()
    _G.f:cancel()
  ]])
  eq(child.lua_get([[_G.cancel_called]]), true)
  eq(child.lua_get([[_G.f._visible]]), false)
  eq(child.lua_get([[_G.submit_result]]), vim.NIL)
end

T["form"]["hide preserves values across show() cycles"] = function()
  child.lua([[
    _G.f = _G.make_form()
    _G.f:show()
    vim.api.nvim_buf_set_lines(_G.f._inputs[1].buf, 0, -1, false, { 'persisted' })
    _G.f:hide()
  ]])
  eq(child.lua_get([[_G.f._visible]]), false)
  child.lua([[_G.f:show()]])
  eq(child.lua_get([[_G.f._inputs[1]:value()]]), "persisted")
end

T["form"]["close() marks form as unusable"] = function()
  child.lua([[_G.f = _G.make_form(); _G.f:show(); _G.f:close()]])
  local ok = child.lua_get([[(function() local ok = pcall(function() _G.f:show() end) return ok end)()]])
  eq(ok, false)
end

T["form"]["invalid spec raises"] = function()
  local ok_no_name = child.lua_get([[
    (function()
      local ok = pcall(function()
        require('input-form').create_form({ inputs = { { type = 'text' } } })
      end)
      return ok
    end)()
  ]])
  eq(ok_no_name, false)

  local ok_bad_type = child.lua_get([[
    (function()
      local ok = pcall(function()
        require('input-form').create_form({ inputs = { { name = 'x', type = 'unknown' } } })
      end)
      return ok
    end)()
  ]])
  eq(ok_bad_type, false)

  local ok_empty = child.lua_get([[
    (function()
      local ok = pcall(function()
        require('input-form').create_form({ inputs = {} })
      end)
      return ok
    end)()
  ]])
  eq(ok_empty, false)
end

T["form"]["keymaps are installed on each input buffer"] = function()
  child.lua([[_G.f = _G.make_form(); _G.f:show()]])
  -- <Tab> should be mapped in normal mode on the first input's buffer.
  local has_tab = child.lua_get([[
    (function()
      local maps = vim.api.nvim_buf_get_keymap(_G.f._inputs[1].buf, 'n')
      for _, m in ipairs(maps) do
        if m.lhs == '<Tab>' then return true end
      end
      return false
    end)()
  ]])
  eq(has_tab, true)
end

return T
