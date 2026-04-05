local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")

local child = helpers.new_child_neovim()
local eq = helpers.expect.equality

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
      child.lua([[V = require('input-form.validators')]])
    end,
    post_once = child.stop,
  },
})

T["validators"] = MiniTest.new_set()

T["validators"]["non_empty"] = function()
  eq(child.lua_get([[V.non_empty()("")]]), "This field is required")
  eq(child.lua_get([[V.non_empty()(nil)]]), "This field is required")
  eq(child.lua_get([[V.non_empty()("ok")]]), vim.NIL)
  eq(child.lua_get([[V.non_empty("nope")("")]]), "nope")
end

T["validators"]["min_length"] = function()
  eq(child.lua_get([[V.min_length(3)("ab")]]), "Must be at least 3 characters")
  eq(child.lua_get([[V.min_length(3)("abc")]]), vim.NIL)
  eq(child.lua_get([[V.min_length(3)("abcd")]]), vim.NIL)
  eq(child.lua_get([[V.min_length(3, "too short")("a")]]), "too short")
end

T["validators"]["max_length"] = function()
  eq(child.lua_get([[V.max_length(3)("abcd")]]), "Must be at most 3 characters")
  eq(child.lua_get([[V.max_length(3)("abc")]]), vim.NIL)
  eq(child.lua_get([[V.max_length(3)("")]]), vim.NIL)
end

T["validators"]["matches"] = function()
  eq(child.lua_get([[V.matches('^%d+$')("abc")]]), "Invalid format")
  eq(child.lua_get([[V.matches('^%d+$')("123")]]), vim.NIL)
  eq(child.lua_get([[V.matches('^%d+$', 'digits only')("x")]]), "digits only")
end

T["validators"]["is_number"] = function()
  eq(child.lua_get([[V.is_number()("abc")]]), "Must be a number")
  eq(child.lua_get([[V.is_number()("")]]), "Must be a number")
  eq(child.lua_get([[V.is_number()("42")]]), vim.NIL)
  eq(child.lua_get([[V.is_number()("3.14")]]), vim.NIL)
end

T["validators"]["checked"] = function()
  -- Defaults to requiring `true`.
  eq(child.lua_get([[V.checked()(true)]]), vim.NIL)
  eq(child.lua_get([[V.checked()(false)]]), "(must be checked)")
  eq(child.lua_get([[V.checked()(nil)]]), "(must be checked)")
  -- Explicit required value.
  eq(child.lua_get([[V.checked(true)(true)]]), vim.NIL)
  eq(child.lua_get([[V.checked(true)(false)]]), "(must be checked)")
  -- Require UNchecked.
  eq(child.lua_get([[V.checked(false)(false)]]), vim.NIL)
  eq(child.lua_get([[V.checked(false)(true)]]), "(must be unchecked)")
  -- Custom message (second arg).
  eq(child.lua_get([[V.checked(true, "please tick the box")(false)]]), "please tick the box")
  eq(child.lua_get([[V.checked(false, "leave it off")(true)]]), "leave it off")
end

T["validators"]["one_of"] = function()
  eq(child.lua_get([[V.one_of({ 'a', 'b' })('c')]]), "Value is not allowed")
  eq(child.lua_get([[V.one_of({ 'a', 'b' })('a')]]), vim.NIL)
end

T["validators"]["custom"] = function()
  eq(child.lua_get([[V.custom(function(v) return v == 'yes' end, 'say yes')('no')]]), "say yes")
  eq(child.lua_get([[V.custom(function(v) return v == 'yes' end, 'say yes')('yes')]]), vim.NIL)
end

T["validators"]["chain returns first error (varargs)"] = function()
  eq(child.lua_get([[V.chain(V.non_empty(), V.min_length(3))("")]]), "This field is required")
  eq(
    child.lua_get([[V.chain(V.non_empty(), V.min_length(3))("ab")]]),
    "Must be at least 3 characters"
  )
  eq(child.lua_get([[V.chain(V.non_empty(), V.min_length(3))("abcd")]]), vim.NIL)
end

T["validators"]["chain accepts a list"] = function()
  eq(
    child.lua_get([[V.chain({ V.non_empty(), V.min_length(3) })("ab")]]),
    "Must be at least 3 characters"
  )
end

T["validators"]["chain treats empty string return as success"] = function()
  -- A validator that returns "" should be treated as "no error".
  eq(
    child.lua_get([[V.chain(
      function(v) return "" end,
      V.non_empty()
    )("")]]),
    "This field is required"
  )
end

return T
