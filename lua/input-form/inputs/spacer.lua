--- Spacer: a non-interactive faux input that reserves blank rows in the
--- form layout. Has no window, no focus, no validation, no value — it only
--- exists so callers can visually separate groups of real inputs.

local M = {}
M.__index = M

--- Create a new spacer from its spec.
---@param spec table { height? }
---@return table
function M.new(spec)
  return setmetatable({
    type = "spacer",
    name = spec.name, -- optional, not required; never appears in results
    focusable = false,
    _height = math.max(0, tonumber(spec.height) or 1),
    buf = nil,
    win = nil,
  }, M)
end

function M:height()
  return self._height
end

function M:is_bordered()
  return false
end

--- No-op: spacers never mount a window.
function M:mount(_) end

--- No-op: nothing to tear down.
function M:unmount() end

--- No-op: spacers are not focusable.
function M:focus() end

--- Spacers carry no value; `results()` skips them entirely.
function M:value()
  return nil
end

return M
