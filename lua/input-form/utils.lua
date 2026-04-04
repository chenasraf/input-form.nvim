local M = {}

--- Deep-merge two tables, with `t2` taking precedence over `t1`.
---@param t1 table
---@param t2 table
---@return table
function M.merge(t1, t2)
  return vim.tbl_deep_extend("force", t1 or {}, t2 or {})
end

--- Resolve a width value: if a float 0<v<=1, treat as a ratio of `vim.o.columns`.
---@param value number
---@return integer
function M.resolve_width(value)
  if value > 0 and value <= 1 then
    return math.floor(vim.o.columns * value)
  end
  return math.floor(value)
end

--- Resolve a height value similarly against `vim.o.lines`.
---@param value number
---@return integer
function M.resolve_height(value)
  if value > 0 and value <= 1 then
    return math.floor(vim.o.lines * value)
  end
  return math.floor(value)
end

--- Clamp an integer into [lo, hi].
function M.clamp(v, lo, hi)
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

return M
