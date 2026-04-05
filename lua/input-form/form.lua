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
  local child_inner_w = child_outer_w - 2 -- minus child border (for bordered inputs)

  -- Extra blank rows rendered above/below a checkbox (borderless input) so
  -- its glyph doesn't butt directly against an adjacent bordered input's
  -- border. Configurable via `style.checkbox.padding`.
  local cb_pad = (opts.style and opts.style.checkbox and opts.style.checkbox.padding) or 0

  local rows = {}
  local inner_h = pad_top
  for i, input in ipairs(self._inputs) do
    local h = input:height()
    -- NB: avoid the `a and b or c` idiom — `is_bordered()` legitimately
    -- returns `false` and that must not get coerced back to the default.
    local bordered = true
    if type(input.is_bordered) == "function" then
      bordered = input:is_bordered()
    end
    local top_pad = (not bordered) and cb_pad or 0
    local bot_pad = (not bordered) and cb_pad or 0
    local outer_h = bordered and (h + 2) or (h + top_pad + bot_pad)
    -- Editor-row offset from `parent_row` to pass as `nvim_open_win`'s `row`
    -- parameter for this child. `row` refers to the window's OUTER top-left
    -- (i.e. the border origin for bordered windows, the content row for
    -- borderless windows). Parent_row is itself a border origin, so every
    -- child needs a `+1` to clear the parent's top border — matching the
    -- `+1` already applied on the column axis in `show()`.
    local content_offset = inner_h + 1 + top_pad
    table.insert(rows, {
      bordered = bordered,
      content_row_offset = content_offset,
      value_height = h,
    })
    inner_h = inner_h + outer_h
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
    child_outer_w = child_outer_w,
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

  -- Lazy: teach known UI plugins (nvim-scrollbar, satellite, ...) to skip
  -- form buffers. Runs once per nvim session.
  utils.register_ui_exclusions()

  -- Apply configured highlight groups (user-configurable via
  -- `setup({ style = { highlights = { ... } } })`).
  self:_apply_highlights()

  local layout = self:_compute_layout()
  self._layout = layout

  -- Parent window: an empty, bordered container that frames the inputs.
  self._parent_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self._parent_buf].buftype = "nofile"
  vim.bo[self._parent_buf].bufhidden = "wipe"
  vim.bo[self._parent_buf].swapfile = false
  utils.mark_form_buffer(self._parent_buf)

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
  if vim.fn.has("nvim-0.10") == 1 then
    local footer = self:_help_line()
    if footer and footer ~= "" then
      win_opts.footer = " " .. footer .. " "
      win_opts.footer_pos = "center"
    end
  end
  self._parent_win = vim.api.nvim_open_win(self._parent_buf, false, win_opts)
  vim.wo[self._parent_win].winblend = config.options.window.winblend
  vim.wo[self._parent_win].winhl = table.concat({
    "NormalFloat:InputFormNormal",
    "FloatBorder:InputFormBorder",
    "FloatTitle:InputFormTitle",
    "FloatFooter:InputFormHelp",
  }, ",")

  -- Mount each input as its own floating window. Bordered inputs get their
  -- own border + label; borderless inputs (e.g. checkbox) render inline but
  -- still align their CONTENT column with the bordered siblings' content
  -- (not their border column) so everything lines up visually.
  local border = config.options.window.border
  for i, input in ipairs(self._inputs) do
    local r = layout.rows[i]
    -- Bordered children get `+1` to clear the parent's left border; their
    -- content then sits at `+2`. Borderless children shift an extra column
    -- so their content column lines up with the bordered siblings' content
    -- column (not their border column).
    local col_offset = r.bordered and 1 or 2
    local mount_opts = {
      row = layout.parent_row + r.content_row_offset,
      col = layout.parent_col + layout.pad_h + col_offset,
      width = layout.child_inner_w,
    }
    if r.bordered then
      mount_opts.border = border
    end
    input:mount(mount_opts)
    self:_install_keymaps(input)
    self:_install_validation(input)
  end

  self:_focus(1)
  return self
end

--- Apply all configured highlight groups. Called from `show()` so live
--- `setup({ style = { highlights = ... } })` edits take effect on the next
--- form open.
function M:_apply_highlights()
  local style = config.options.style or {}
  local hls = style.highlights or {}
  for name, spec in pairs(hls) do
    pcall(vim.api.nvim_set_hl, 0, name, spec)
  end
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

--- Submit the form: gather values, run validators, and invoke
--- `on_submit(results)` only if everything validates. If any input has an
--- error, submission is blocked, all inputs are force-validated (so the user
--- sees every error, including ones on untouched fields), and focus moves to
--- the first invalid input.
function M:submit()
  if self._visible and self:_validate_all() then
    -- Validation failed — do not close, do not invoke on_submit.
    return
  end
  local results = self:results()
  self:hide()
  if self._on_submit then
    self._on_submit(results)
  end
end

--- Run every input's validator (marking each as touched first) and render
--- results. Returns `true` if any input has an error.
function M:_validate_all()
  local any_error = false
  local first_bad = nil
  for i, input in ipairs(self._inputs) do
    if input.validator then
      input._touched = true
      local err = input.validator(input:value())
      -- Only strings count as errors; nil / false / other types = no error.
      if type(err) ~= "string" or err == "" then
        err = nil
      end
      input._error = err
      self:_render_validation(input)
      if err and not first_bad then
        first_bad = i
      end
      if err then
        any_error = true
      end
    end
  end
  if first_bad then
    self:_focus(first_bad)
  end
  return any_error
end

--- Cancel the form: close windows, invoke `on_cancel()` if provided.
function M:cancel()
  self:hide()
  if self._on_cancel then
    self._on_cancel()
  end
end

--- Install validation autocmds for an input. No-op if the input has no
--- validator. Validation runs:
---   - on `WinLeave` (blurring the field marks it touched and validates)
---   - on `TextChanged` / `TextChangedI` IF the input is already touched
---
--- For `select` inputs, the user "touches" the field by picking an option;
--- `_render_display`'s `nvim_buf_set_lines` call also fires `TextChanged`
--- so the same path handles re-validation there.
function M:_install_validation(input)
  if not input.validator then
    return
  end
  local buf = input.buf
  if not buf then
    return
  end
  local form = self
  local group = vim.api.nvim_create_augroup("InputFormValidate_" .. tostring(buf), { clear = true })
  input._val_group = group

  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = buf,
    callback = function()
      input._touched = true
      form:_validate_input(input)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      if input._touched then
        form:_validate_input(input)
      end
    end,
  })

  -- For `select` inputs, changes happen while the dropdown buffer is current,
  -- so `TextChanged` on the display buffer doesn't fire. The input exposes an
  -- `_on_change` hook that we use to mark it touched and re-validate.
  input._on_change = function()
    input._touched = true
    form:_validate_input(input)
  end
end

--- Run the validator for one input and update its visual error state.
function M:_validate_input(input)
  if not input.validator then
    return
  end
  local err = input.validator(input:value())
  -- Only strings count as errors; nil / false / other types = no error.
  if type(err) ~= "string" or err == "" then
    err = nil
  end
  input._error = err
  self:_render_validation(input)
end

--- Apply/clear the red border, title, and footer error message on an input's
--- floating window based on its current `_error` state.
function M:_render_validation(input)
  local win = input.win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  -- Borderless inputs (checkbox) render the error inline — they already read
  -- `self._error` from their own `_render_display()`.
  local bordered = true
  if type(input.is_bordered) == "function" then
    bordered = input:is_bordered()
  end
  if not bordered then
    if type(input._render_display) == "function" then
      input:_render_display()
    end
    return
  end

  local has_error = input._error ~= nil

  if has_error then
    vim.wo[win].winhl = table.concat({
      "NormalFloat:InputFormField",
      "FloatBorder:InputFormFieldErrorBorder",
      "FloatTitle:InputFormFieldErrorTitle",
      "FloatFooter:InputFormFieldError",
    }, ",")
  else
    vim.wo[win].winhl = table.concat({
      "NormalFloat:InputFormField",
      "FloatBorder:InputFormFieldBorder",
      "FloatTitle:InputFormFieldTitle",
    }, ",")
  end

  -- Footer (error message) requires nvim 0.10+.
  if vim.fn.has("nvim-0.10") == 1 then
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if ok and cfg and cfg.relative ~= "" then
      if has_error then
        -- Truncate to window width with an ellipsis.
        local max_w = (cfg.width or 0) - 2
        local msg = input._error
        if max_w > 3 and vim.fn.strdisplaywidth(msg) > max_w then
          msg = vim.fn.strcharpart(msg, 0, max_w - 1) .. "…"
        end
        cfg.footer = " " .. msg .. " "
        cfg.footer_pos = "left"
      else
        cfg.footer = ""
      end
      pcall(vim.api.nvim_win_set_config, win, cfg)
    end
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
  -- Only advertise type-specific keys if the form actually has such an input.
  local has_select, has_checkbox = false, false
  for _, input in ipairs(self._inputs) do
    if input.type == "select" then
      has_select = true
    elseif input.type == "checkbox" then
      has_checkbox = true
    end
  end
  if has_select then
    add(km.open_select, "open")
  end
  if has_checkbox then
    add(km.toggle, "toggle")
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
  elseif input.type == "checkbox" then
    -- Toggle on the configured toggle key AND on open_select so users who
    -- prefer <CR> for all interactions get a single key for every field.
    map("n", km.toggle, function()
      input:toggle()
    end)
    if km.open_select and km.open_select ~= km.toggle then
      map("n", km.open_select, function()
        input:toggle()
      end)
    end
    -- Block insert mode on the checkbox display buffer.
    vim.keymap.set("n", "i", "<Nop>", { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "a", "<Nop>", { buffer = buf, nowait = true, silent = true })
  elseif input.type == "text" then
    -- Single-line text inputs must never contain newlines. <CR> in insert
    -- mode just exits insert mode (accepting the value) rather than inserting
    -- a line break. Multiline inputs intentionally keep <CR> for newline entry.
    map("i", "<CR>", function()
      vim.cmd("stopinsert")
    end)
  end
end

return M
