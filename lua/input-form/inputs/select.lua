--- Dropdown / select input component.
---
--- The value returned by `:value()` is the `id` of the selected option, not
--- its label. Opening the dropdown shows all options in a child floating
--- window; j/k/arrows navigate, <CR> confirms, <Esc> cancels.

local config = require("input-form.config")

local M = {}
M.__index = M

--- Create a new select input from its spec.
---@param spec table { name, label, options, default? }
---@return table
function M.new(spec)
  assert(
    type(spec.options) == "table" and #spec.options > 0,
    "select input requires non-empty options"
  )
  local selected_id = spec.default
  if selected_id == nil then
    selected_id = spec.options[1].id
  end
  return setmetatable({
    type = "select",
    name = spec.name,
    label = spec.label or spec.name,
    options = spec.options,
    _selected_id = selected_id,
    buf = nil,
    win = nil,
    dropdown_buf = nil,
    dropdown_win = nil,
  }, M)
end

function M:height()
  return 1
end

local function label_for(options, id)
  for _, opt in ipairs(options) do
    if opt.id == id then
      return opt.label
    end
  end
  return ""
end

local function format_display(options, id)
  return "[ " .. label_for(options, id) .. " ]"
end

function M:_render_display()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.bo[self.buf].modifiable = true
    vim.api.nvim_buf_set_lines(
      self.buf,
      0,
      -1,
      false,
      { format_display(self.options, self._selected_id) }
    )
    vim.bo[self.buf].modifiable = false
  end
end

function M:mount(layout)
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.buf].buftype = "nofile"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  vim.api.nvim_buf_set_lines(
    self.buf,
    0,
    -1,
    false,
    { format_display(self.options, self._selected_id) }
  )
  vim.bo[self.buf].modifiable = false

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
  self._layout = layout
end

function M:value()
  return self._selected_id
end

function M:unmount()
  self:close_dropdown()
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

--- Open the dropdown list as a child floating window anchored below the input.
function M:open_dropdown()
  if self.dropdown_win and vim.api.nvim_win_is_valid(self.dropdown_win) then
    return
  end

  local lines = {}
  local init_idx = 1
  for i, opt in ipairs(self.options) do
    table.insert(lines, "  " .. opt.label)
    if opt.id == self._selected_id then
      init_idx = i
    end
  end

  self.dropdown_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.dropdown_buf].buftype = "nofile"
  vim.bo[self.dropdown_buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(self.dropdown_buf, 0, -1, false, lines)
  vim.bo[self.dropdown_buf].modifiable = false

  local max_h = config.options.select.max_height
  local height = math.min(#lines, max_h)

  -- Position the dropdown's top border immediately beneath the input's bottom
  -- border. Content origin row = (input content row) + (input bottom border = 1)
  -- + (dropdown top border = 1) + 1 = self._layout.row + 3.
  self.dropdown_win = vim.api.nvim_open_win(self.dropdown_buf, true, {
    relative = "editor",
    row = self._layout.row + 3,
    col = self._layout.col,
    width = self._layout.width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    zindex = 100,
  })
  vim.wo[self.dropdown_win].cursorline = true
  vim.wo[self.dropdown_win].winhl =
    "NormalFloat:InputFormDropdown,CursorLine:InputFormDropdownActive"
  vim.api.nvim_win_set_cursor(self.dropdown_win, { init_idx, 0 })

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = self.dropdown_buf, nowait = true, silent = true })
  end
  local function confirm()
    local row = vim.api.nvim_win_get_cursor(self.dropdown_win)[1]
    self._selected_id = self.options[row].id
    self:_render_display()
    self:close_dropdown()
  end
  map("<CR>", confirm)
  map("<Esc>", function()
    self:close_dropdown()
  end)
  map("q", function()
    self:close_dropdown()
  end)
end

function M:close_dropdown()
  if self.dropdown_win and vim.api.nvim_win_is_valid(self.dropdown_win) then
    vim.api.nvim_win_close(self.dropdown_win, true)
  end
  if self.dropdown_buf and vim.api.nvim_buf_is_valid(self.dropdown_buf) then
    pcall(vim.api.nvim_buf_delete, self.dropdown_buf, { force = true })
  end
  self.dropdown_win = nil
  self.dropdown_buf = nil
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
  end
end

--- Programmatically set the selected option by id (used in tests & external callers).
function M:select_id(id)
  for _, opt in ipairs(self.options) do
    if opt.id == id then
      self._selected_id = id
      self:_render_display()
      return true
    end
  end
  return false
end

return M
