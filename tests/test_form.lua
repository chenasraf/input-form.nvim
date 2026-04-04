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
  local ok =
    child.lua_get([[(function() local ok = pcall(function() _G.f:show() end) return ok end)()]])
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

T["form"]["text inputs stop insert on <CR> (no newlines)"] = function()
  child.lua([[
    _G.f = _G.make_form()
    _G.f:show()
    vim.api.nvim_set_current_win(_G.f._inputs[1].win)
    -- Feed `i` to enter insert, then `<CR>` which should now invoke stopinsert
    -- instead of inserting a newline.
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes('i<CR>', true, false, true),
      'x',
      false
    )
  ]])
  -- Exactly one line (no newline inserted) and we're back in normal mode.
  eq(child.lua_get([[#vim.api.nvim_buf_get_lines(_G.f._inputs[1].buf, 0, -1, false)]]), 1)
  eq(child.lua_get([[vim.api.nvim_get_mode().mode]]), "n")
  -- Form still visible.
  eq(child.lua_get([[_G.f._visible]]), true)
end

T["form"]["multiline inputs do not rebind <CR>"] = function()
  child.lua([[_G.f = _G.make_form(); _G.f:show()]])
  local has_cr = child.lua_get([[
    (function()
      local maps = vim.api.nvim_buf_get_keymap(_G.f._inputs[3].buf, 'i')
      for _, m in ipairs(maps) do
        if m.lhs == '<CR>' then return true end
      end
      return false
    end)()
  ]])
  eq(has_cr, false)
end

T["form"]["validation"] = MiniTest.new_set()

local function make_validated_form(child)
  child.lua([[
    local V = require('input-form.validators')
    _G.submit_result = nil
    _G.vf = require('input-form').create_form({
      inputs = {
        { name = 'id', label = 'Enter ID', type = 'text',
          default = '',
          validator = V.chain(V.non_empty(), V.min_length(3)) },
        { name = 'body', label = 'Body', type = 'multiline', default = '' },
      },
      on_submit = function(r) _G.submit_result = r end,
    })
    _G.vf:show()
  ]])
end

T["form"]["validation"]["no error shown before the field is touched"] = function()
  make_validated_form(child)
  eq(child.lua_get([[_G.vf._inputs[1]._touched]]), false)
  eq(child.lua_get([[_G.vf._inputs[1]._error]]), vim.NIL)
end

T["form"]["validation"]["blur marks touched and runs validator"] = function()
  make_validated_form(child)
  -- Move focus from input 1 to input 2 — fires WinLeave on input 1.
  child.lua([[_G.vf:focus_next()]])
  eq(child.lua_get([[_G.vf._inputs[1]._touched]]), true)
  eq(child.lua_get([[_G.vf._inputs[1]._error]]), "This field is required")
end

T["form"]["validation"]["re-validates on change after touched"] = function()
  make_validated_form(child)
  child.lua([[_G.vf:focus_next()]]) -- blur input 1, errors
  child.lua([[_G.vf:focus_prev()]]) -- back to input 1
  child.lua([[vim.api.nvim_buf_set_lines(_G.vf._inputs[1].buf, 0, -1, false, { 'ab' })]])
  eq(child.lua_get([[_G.vf._inputs[1]._error]]), "Must be at least 3 characters")
  child.lua([[vim.api.nvim_buf_set_lines(_G.vf._inputs[1].buf, 0, -1, false, { 'abcd' })]])
  eq(child.lua_get([[_G.vf._inputs[1]._error]]), vim.NIL)
end

T["form"]["validation"]["submit blocked when any input is invalid"] = function()
  make_validated_form(child)
  child.lua([[_G.vf:submit()]])
  -- submit should NOT have run on_submit
  eq(child.lua_get([[_G.submit_result]]), vim.NIL)
  -- form still visible
  eq(child.lua_get([[_G.vf._visible]]), true)
  -- first input is now touched and errored
  eq(child.lua_get([[_G.vf._inputs[1]._touched]]), true)
  eq(child.lua_get([[_G.vf._inputs[1]._error]]), "This field is required")
  -- focus moved to the first invalid input
  eq(child.lua_get([[_G.vf._focus_idx]]), 1)
end

T["form"]["validation"]["submit proceeds once all inputs are valid"] = function()
  make_validated_form(child)
  child.lua([[vim.api.nvim_buf_set_lines(_G.vf._inputs[1].buf, 0, -1, false, { 'valid id' })]])
  child.lua([[_G.vf:submit()]])
  eq(child.lua_get([[type(_G.submit_result)]]), "table")
  eq(child.lua_get([[_G.submit_result.id]]), "valid id")
  eq(child.lua_get([[_G.vf._visible]]), false)
end

T["form"]["validation"]["inputs without a validator are never marked touched"] = function()
  make_validated_form(child)
  -- Second input has no validator.
  child.lua([[_G.vf:focus_next()]])
  child.lua([[_G.vf:focus_prev()]])
  eq(child.lua_get([[_G.vf._inputs[2]._touched]]), false)
  eq(child.lua_get([[_G.vf._inputs[2]._error]]), vim.NIL)
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
