--- Single-line text input component.

local M = {}
M.__index = M

--- Create a new text input from its spec.
---@param spec table { name, label, default? }
---@return table
function M.new(spec)
  return setmetatable({
    type = "text",
    name = spec.name,
    label = spec.label or spec.name,
    _value = spec.default or "",
    buf = nil,
    win = nil,
  }, M)
end

--- Number of content rows (excluding the label line) this input occupies.
function M:height()
  return 1
end

--- Create the backing buffer and floating window.
---@param layout table { row, col, width }
function M:mount(layout)
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.buf].buftype = "nofile"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, { self._value })

  self.win = vim.api.nvim_open_win(self.buf, false, {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = 1,
    style = "minimal",
    border = layout.border,
    title = " " .. self.label .. " ",
    title_pos = "left",
    focusable = true,
    zindex = 50,
  })
  vim.wo[self.win].winhl =
    "NormalFloat:InputFormField,FloatBorder:InputFormFieldBorder,FloatTitle:InputFormFieldTitle"
end

--- Return current value (from the buffer if mounted, otherwise the cached value).
function M:value()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    local lines = vim.api.nvim_buf_get_lines(self.buf, 0, -1, false)
    return lines[1] or ""
  end
  return self._value
end

--- Close the window and buffer, caching the current value.
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

--- Give this input focus and enter insert mode at the end of the line.
function M:focus()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    local line = self:value()
    vim.api.nvim_win_set_cursor(self.win, { 1, #line })
  end
end

return M
