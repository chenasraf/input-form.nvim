--- Input type registry and factory.

local M = {}

M.types = {
  text = require("input-form.inputs.text"),
  multiline = require("input-form.inputs.multiline"),
  select = require("input-form.inputs.select"),
}

--- Build an input component instance from a user-provided spec.
---@param spec table
---@return table
function M.build(spec)
  assert(type(spec) == "table", "input spec must be a table")
  assert(type(spec.name) == "string" and spec.name ~= "", "input spec requires a non-empty 'name'")
  local t = spec.type or "text"
  local impl = M.types[t]
  assert(impl, "unknown input type: " .. tostring(t))
  local input = impl.new(spec)
  input.validator = spec.validator
  input._touched = false
  input._error = nil
  return input
end

return M
