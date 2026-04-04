--- Form object: manages a bordered floating window containing multiple inputs.

local config = require("input-form.config")
local inputs_factory = require("input-form.inputs")
local utils = require("input-form.utils")

local M = {}
M.__index = M

--- Create a new form from its spec. Does NOT open any windows — call `:show()`.
---@param spec table { inputs, on_submit, on_cancel?, title?, width? }
---@return table
function M.new(spec)
  assert(type(spec) == "table", "create_form: spec must be a table")
  assert(
    type(spec.inputs) == "table" and #spec.inputs > 0,
    "create_form: spec.inputs must be a non-empty list"
  )

  local self = setmetatable({
    _spec = spec,
    _inputs = {},
    _on_submit = spec.on_submit,
    _on_cancel = spec.on_cancel,
    _title = spec.title,
    _width = spec.width,
    _visible = false,
    _closed = false,
    _parent_win = nil,
    _parent_buf = nil,
    _focus_idx = 1,
  }, M)

  for _, input_spec in ipairs(spec.inputs) do
    table.insert(self._inputs, inputs_factory.build(input_spec))
  end

  return self
end

--- Compute geometry for the parent window and each child input window.
---
--- Each input is a separately-bordered floating window whose label is drawn on
--- its own top border. The parent window contains them all with padding.
---
--- Coordinate reminder: `row`/`col` passed to `nvim_open_win` with a border
--- describe the CONTENT origin; the border is drawn one cell outside that.
function M:_compute_layout()
  local opts = config.options
  -- `width` is the parent's OUTER width (i.e. visible width including border).
  local outer_width = utils.resolve_width(self._width or opts.window.width)

  -- Grow the window to fit the footer help line if the user's configured
  -- width is too narrow. The footer string is " <help> " so we need at least
  -- #help + 2 (leading/trailing space) + 2 (corners) cells of outer width.
  local help = self:_help_line()
  if help and help ~= "" then
    local needed = vim.fn.strdisplaywidth(help) + 4
    if outer_width < needed then
      outer_width = needed
    end
  end

  outer_width = utils.clamp(outer_width, 20, vim.o.columns - 4)

  local padding = opts.window.padding or 0
  local gap = opts.window.gap or 0
  local pad_h = padding -- horizontal padding inside parent, each side
  local pad_top = padding
  local pad_bottom = padding
  local sep = gap -- blank rows between inputs

  local parent_inner_w = outer_width - 2 -- minus parent border
  local child_outer_w = parent_inner_w - pad_h * 2
  local child_inner_w = child_outer_w - 2 -- minus child border

  local rows = {}
  local inner_h = pad_top
  for i, input in ipairs(self._inputs) do
    local h = input:height()
    table.insert(rows, {
      top_border_offset = inner_h, -- row inside parent content where child's top border sits
      value_height = h,
    })
    inner_h = inner_h + h + 2 -- child's full outer height (content + 2 border rows)
    if i < #self._inputs then
      inner_h = inner_h + sep
    end
  end
  inner_h = inner_h + pad_bottom

  local outer_h = inner_h + 2 -- plus parent border
  local top = math.floor((vim.o.lines - outer_h) / 2)
  local left = math.floor((vim.o.columns - outer_width) / 2)

  -- Parent content origin (pass to nvim_open_win as row/col).
  local parent_row = top + 1
  local parent_col = left + 1

  return {
    outer_width = outer_width,
    outer_height = outer_h,
    parent_row = parent_row,
    parent_col = parent_col,
    parent_inner_w = parent_inner_w,
    parent_inner_h = inner_h,
    child_inner_w = child_inner_w,
    pad_h = pad_h,
    rows = rows,
  }
end

--- Open the form on screen. No-op if already visible.
function M:show()
  assert(not self._closed, "form has been closed")
  if self._visible then
    return self
  end
  self._visible = true

  local layout = self:_compute_layout()
  self._layout = layout

  -- Parent window: an empty, bordered container that frames the inputs.
  self._parent_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self._parent_buf].buftype = "nofile"
  vim.bo[self._parent_buf].bufhidden = "wipe"
  vim.bo[self._parent_buf].swapfile = false

  local parent_lines = {}
  for _ = 1, layout.parent_inner_h do
    table.insert(parent_lines, string.rep(" ", layout.parent_inner_w))
  end
  vim.api.nvim_buf_set_lines(self._parent_buf, 0, -1, false, parent_lines)
  vim.bo[self._parent_buf].modifiable = false

  local win_opts = {
    relative = "editor",
    row = layout.parent_row,
    col = layout.parent_col,
    width = layout.parent_inner_w,
    height = layout.parent_inner_h,
    style = "minimal",
    border = config.options.window.border,
    focusable = false,
    zindex = 40,
  }
  if config.options.window.title and vim.fn.has("nvim-0.9") == 1 then
    win_opts.title = self._title or config.options.window.title
    win_opts.title_pos = config.options.window.title_pos
  end
  if vim.fn.has("nvim-0.9") == 1 then
    local footer = self:_help_line()
    if footer and footer ~= "" then
      win_opts.footer = " " .. footer .. " "
      win_opts.footer_pos = "center"
    end
  end
  -- Default highlight for the footer (help text): cyan, overridable by the user.
  pcall(vim.api.nvim_set_hl, 0, "InputFormHelp", { fg = "Cyan", default = true })

  self._parent_win = vim.api.nvim_open_win(self._parent_buf, false, win_opts)
  vim.wo[self._parent_win].winblend = config.options.window.winblend
  vim.wo[self._parent_win].winhl = table.concat({
    "NormalFloat:InputFormNormal",
    "FloatBorder:InputFormBorder",
    "FloatTitle:InputFormTitle",
    "FloatFooter:InputFormHelp",
  }, ",")

  -- Mount each input as its own bordered child floating window.
  local border = config.options.window.border
  for i, input in ipairs(self._inputs) do
    local r = layout.rows[i]
    -- Child's content origin: inside the parent content area, offset by the
    -- row's top_border_offset plus one row for the child's own top border;
    -- and one col inside the parent plus horizontal padding plus one for the
    -- child's own left border.
    input:mount({
      row = layout.parent_row + r.top_border_offset + 1,
      col = layout.parent_col + layout.pad_h + 1,
      width = layout.child_inner_w,
      border = border,
    })
    self:_install_keymaps(input)
  end

  self:_focus(1)
  return self
end

--- Hide the form (close windows) but keep state so `:show()` can reopen it.
function M:hide()
  if not self._visible then
    return
  end
  for _, input in ipairs(self._inputs) do
    input:unmount()
  end
  if self._parent_win and vim.api.nvim_win_is_valid(self._parent_win) then
    vim.api.nvim_win_close(self._parent_win, true)
  end
  if self._parent_buf and vim.api.nvim_buf_is_valid(self._parent_buf) then
    pcall(vim.api.nvim_buf_delete, self._parent_buf, { force = true })
  end
  self._parent_win = nil
  self._parent_buf = nil
  self._visible = false
end

--- Permanently tear down the form.
function M:close()
  self:hide()
  self._closed = true
end

--- Collect current values from all inputs into a { [name] = value } table.
function M:results()
  local out = {}
  for _, input in ipairs(self._inputs) do
    out[input.name] = input:value()
  end
  return out
end

--- Submit the form: gather values, close windows, invoke `on_submit(results)`.
function M:submit()
  local results = self:results()
  self:hide()
  if self._on_submit then
    self._on_submit(results)
  end
end

--- Cancel the form: close windows, invoke `on_cancel()` if provided.
function M:cancel()
  self:hide()
  if self._on_cancel then
    self._on_cancel()
  end
end

--- Build a help-line string describing the active keymaps.
function M:_help_line()
  local km = config.options.keymaps
  local parts = {}
  local function add(keys, desc)
    if keys and keys ~= false and keys ~= "" then
      table.insert(parts, keys .. " " .. desc)
    end
  end
  local nav
  if km.next and km.prev then
    nav = km.next .. "/" .. km.prev
  else
    nav = km.next or km.prev
  end
  if nav then
    table.insert(parts, nav .. " navigate")
  end
  -- Only advertise open_select if the form actually has a select input.
  local has_select = false
  for _, input in ipairs(self._inputs) do
    if input.type == "select" then
      has_select = true
      break
    end
  end
  if has_select then
    add(km.open_select, "open")
  end
  add(km.submit, "submit")
  add(km.cancel, "cancel")
  return table.concat(parts, "  ")
end

function M:_focus(idx)
  local n = #self._inputs
  idx = ((idx - 1) % n + n) % n + 1
  self._focus_idx = idx
  self._inputs[idx]:focus()
end

function M:focus_next()
  self:_focus(self._focus_idx + 1)
end

function M:focus_prev()
  self:_focus(self._focus_idx - 1)
end

function M:_install_keymaps(input)
  local km = config.options.keymaps
  local buf = input.buf
  if not buf then
    return
  end
  local function map(mode, lhs, fn)
    if lhs and lhs ~= false then
      vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
  end

  local modes = { "n", "i" }
  for _, mode in ipairs(modes) do
    map(mode, km.next, function()
      self:focus_next()
    end)
    -- Don't rebind <S-Tab> in insert for multiline to allow natural editing — still useful here.
    map(mode, km.prev, function()
      self:focus_prev()
    end)
    map(mode, km.submit, function()
      self:submit()
    end)
  end

  -- Cancel only in normal mode to avoid clobbering <Esc> used to leave insert mode.
  map("n", km.cancel, function()
    self:cancel()
  end)

  if input.type == "select" then
    map("n", km.open_select, function()
      input:open_dropdown()
    end)
    -- Block insert mode on the select display buffer.
    vim.keymap.set("n", "i", "<Nop>", { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "a", "<Nop>", { buffer = buf, nowait = true, silent = true })
  end
end

return M
