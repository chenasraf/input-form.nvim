local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")

local child = helpers.new_child_neovim()
local eq = helpers.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[require('input-form').setup()]])
      child.lua([[
        _G.mk = function(default)
          return require('input-form.inputs.select').new({
            name = 's', label = 'S',
            default = default,
            options = {
              { id = 'a', label = 'Alpha' },
              { id = 'b', label = 'Beta' },
              { id = 'c', label = 'Gamma' },
            },
          })
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["select input"] = MiniTest.new_set()

T["select input"]["defaults to first option when none given"] = function()
  child.lua([[_G.t = _G.mk(nil); _G.t:mount({ row = 5, col = 5, width = 30 })]])
  eq(child.lua_get([[_G.t:value()]]), "a")
  local line = child.lua_get([==[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)[1]]==])
  helpers.expect.match(line, "^Alpha")
  helpers.expect.match(line, "⌄")
end

T["select input"]["honors explicit default"] = function()
  child.lua([[_G.t = _G.mk('b'); _G.t:mount({ row = 5, col = 5, width = 30 })]])
  eq(child.lua_get([[_G.t:value()]]), "b")
  local line = child.lua_get([==[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)[1]]==])
  helpers.expect.match(line, "^Beta")
  helpers.expect.match(line, "⌄")
end

T["select input"]["display buffer is read-only"] = function()
  child.lua([[_G.t = _G.mk('a'); _G.t:mount({ row = 5, col = 5, width = 30 })]])
  eq(child.lua_get([[vim.bo[_G.t.buf].modifiable]]), false)
end

T["select input"]["select_id updates value and display"] = function()
  child.lua([[
    _G.t = _G.mk('a')
    _G.t:mount({ row = 5, col = 5, width = 30 })
    _G.ok = _G.t:select_id('c')
  ]])
  eq(child.lua_get([[_G.ok]]), true)
  eq(child.lua_get([[_G.t:value()]]), "c")
  local line = child.lua_get([==[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)[1]]==])
  helpers.expect.match(line, "^Gamma")
  helpers.expect.match(line, "⌄")
end

T["select input"]["open_dropdown shows all options and <CR> confirms"] = function()
  child.lua([[
    _G.t = _G.mk('a')
    _G.t:mount({ row = 5, col = 5, width = 30 })
    _G.t:open_dropdown()
  ]])
  eq(
    child.lua_get([[vim.api.nvim_buf_get_lines(_G.t.dropdown_buf, 0, -1, false)]]),
    { "  Alpha", "  Beta", "  Gamma" }
  )
  -- Move to row 2 (Beta) and confirm via the keymap callback.
  child.lua([[
    vim.api.nvim_win_set_cursor(_G.t.dropdown_win, { 2, 0 })
    -- Fire the <CR> mapping we installed.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'x', false)
  ]])
  eq(child.lua_get([[_G.t:value()]]), "b")
  eq(child.lua_get([[_G.t.dropdown_win]]), vim.NIL)
end

T["select input"]["<Esc> closes dropdown without changing value"] = function()
  child.lua([[
    _G.t = _G.mk('a')
    _G.t:mount({ row = 5, col = 5, width = 30 })
    _G.t:open_dropdown()
    vim.api.nvim_win_set_cursor(_G.t.dropdown_win, { 3, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
  ]])
  eq(child.lua_get([[_G.t:value()]]), "a")
  eq(child.lua_get([[_G.t.dropdown_win]]), vim.NIL)
end

T["select input"]["uses custom chevrons from config"] = function()
  child.lua([[
    require('input-form').setup({
      style = { chevron = { closed = " v", open = " ^" } }
    })
    _G.t = _G.mk('a')
    _G.t:mount({ row = 5, col = 5, width = 30 })
  ]])
  local closed_line = child.lua_get([==[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)[1]]==])
  helpers.expect.match(closed_line, " v$")
  helpers.expect.no_match(closed_line, "⌄")
  -- Flip to open state and re-render.
  child.lua([[_G.t._open = true; _G.t:_render_display()]])
  local open_line = child.lua_get([==[vim.api.nvim_buf_get_lines(_G.t.buf, 0, -1, false)[1]]==])
  helpers.expect.match(open_line, " %^$")
  helpers.expect.no_match(open_line, "⌃")
end

T["select input"]["dropdown border merges into select's bottom border"] = function()
  -- `rounded` default → T-junctions are ├ and ┤.
  child.lua([[
    _G.t = _G.mk('a')
    _G.t:mount({ row = 5, col = 5, width = 30 })
    _G.t._layout = { row = 10, col = 5, width = 30 }
    _G.t:open_dropdown()
  ]])
  local cfg = child.lua_get([[vim.api.nvim_win_get_config(_G.t.dropdown_win)]])
  -- Dropdown row must overlap the select's bottom border row (= layout.row + 2
  -- for the content origin, putting the top border at layout.row + 1).
  eq(cfg.row, 12)
  -- Border is an 8-element array with T-junctions in the top corners.
  eq(type(cfg.border), "table")
  -- nvim_win_get_config returns borders as { { char, hl_group }, ... }.
  local tl = type(cfg.border[1]) == "table" and cfg.border[1][1] or cfg.border[1]
  local tr = type(cfg.border[3]) == "table" and cfg.border[3][1] or cfg.border[3]
  eq(tl, "├")
  eq(tr, "┤")
end

T["select input"]["rejects empty options list"] = function()
  local ok = child.lua_get([[
    (function()
      local ok, err = pcall(function()
        require('input-form.inputs.select').new({ name = 's', label = 'S', options = {} })
      end)
      return ok
    end)()
  ]])
  eq(ok, false)
end

return T
