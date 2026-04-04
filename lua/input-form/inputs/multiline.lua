--- Multi-line text input component.

local config = require("input-form.config")

local M = {}
M.__index = M

--- Create a new multiline input from its spec.
---@param spec table { name, label, default?, height? }
---@return table
function M.new(spec)
  local h = spec.height or config.options.multiline.height
  local default = spec.default or ""
  return setmetatable({
    type = "multiline",
    name = spec.name,
    label = spec.label or spec.name,
    _value = default,
    _height = h,
    buf = nil,
    win = nil,
  }, M)
end

function M:height()
  return self._height
end

function M:mount(layout)
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.buf].buftype = "nofile"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  local lines = vim.split(self._value, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

  self.win = vim.api.nvim_open_win(self.buf, false, {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = self._height,
    style = "minimal",
    border = layout.border,
    title = " " .. self.label .. " ",
    title_pos = "left",
    focusable = true,
    zindex = 50,
  })
  vim.wo[self.win].winhl =
    "NormalFloat:InputFormField,FloatBorder:InputFormFieldBorder,FloatTitle:InputFormFieldTitle"
  vim.wo[self.win].wrap = true
end

function M:value()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
    return table.concat(lines, "\n")
  end
  return self._value
end

function M:unmount()
  self._value = self:value()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
  self.win = nil
  self.buf = nil
end

function M:focus()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
  end
end

return M
