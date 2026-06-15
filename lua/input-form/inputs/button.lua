--- Button input component.
---
--- A focusable control that invokes `on_activate(form)` when the user presses
--- the configured `keymaps.activate` keys (default `<CR>` / `<Space>`).
--- Carries no value and is skipped in `form:results()`.
---
--- Styling:
---   - `bordered`  : draw a floating-window border around the button (default true)
---   - `prefix`    : string prepended to the label (e.g. `"[ "`)
---   - `suffix`    : string appended to the label  (e.g. `" ]"`)
---   - `align`     : `"left"` | `"center"` | `"right"` (default `"center"`)
---
--- These can be set globally via `setup({ style = { button = { ... } } })` and
--- overridden per-button by setting the same keys on the input spec.
---
--- Focus state swaps NormalFloat/FloatBorder for `InputFormButtonFocus` /
--- `InputFormButtonFocusBorder`, which default to `reverse = true` so the
--- button renders with foreground and background colors swapped.

local config = require("input-form.config")
local utils = require("input-form.utils")

local M = {}
M.__index = M

--- Resolve `spec[key]` falling back to `config.options.style.button[key]`
--- then to `default`. `nil` (not `false`) signals "use the next level".
local function resolve(spec, key, default)
  if spec[key] ~= nil then
    return spec[key]
  end
  local btn = (config.options.style and config.options.style.button) or {}
  if btn[key] ~= nil then
    return btn[key]
  end
  return default
end

--- Create a new button from its spec.
---@param spec table { label, on_activate?, name?, bordered?, prefix?, suffix?, align? }
---@return table
function M.new(spec)
  return setmetatable({
    type = "button",
    -- `name` is optional; buttons carry no value, so `form:results()` skips
    -- them. We still allow it so callers can identify a button if they want.
    name = spec.name,
    label = spec.label or spec.name or "Button",
    _on_activate = spec.on_activate,
    _bordered = resolve(spec, "bordered", true),
    _prefix = resolve(spec, "prefix", ""),
    _suffix = resolve(spec, "suffix", ""),
    _align = resolve(spec, "align", "center"),
    buf = nil,
    win = nil,
  }, M)
end

function M:height()
  return 1
end

function M:is_bordered()
  return self._bordered and true or false
end

function M:_render_display()
  if not (self.buf and vim.api.nvim_buf_is_valid(self.buf)) then
    return
  end
  local text = (self._prefix or "") .. (self.label or "") .. (self._suffix or "")
  local width = self._width or vim.fn.strdisplaywidth(text)
  local text_w = vim.fn.strdisplaywidth(text)
  local pad_left = 0
  if self._align == "center" then
    pad_left = math.max(0, math.floor((width - text_w) / 2))
  elseif self._align == "right" then
    pad_left = math.max(0, width - text_w)
  end
  local line = string.rep(" ", pad_left) .. text
  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, { line })
  vim.bo[self.buf].modifiable = false
end

--- Apply the appropriate `winhl` mapping for the current focus state.
function M:_apply_winhl(focused)
  if not (self.win and vim.api.nvim_win_is_valid(self.win)) then
    return
  end
  local parts
  if focused then
    parts = {
      "NormalFloat:InputFormButtonFocus",
      "FloatBorder:InputFormButtonFocusBorder",
    }
  else
    parts = {
      "NormalFloat:InputFormButton",
      "FloatBorder:InputFormButtonBorder",
    }
  end
  vim.wo[self.win].winhl = table.concat(parts, ",")
end

function M:mount(layout)
  self._width = layout.width
  self.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.buf].buftype = "nofile"
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].swapfile = false
  utils.mark_form_buffer(self.buf)

  local win_cfg = {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = 1,
    style = "minimal",
    focusable = true,
    zindex = 50,
  }
  if layout.border then
    win_cfg.border = layout.border
  end
  self.win = vim.api.nvim_open_win(self.buf, false, win_cfg)

  -- Track focus via WinEnter/WinLeave on the button buffer so the highlight
  -- swap happens whether the user navigated here with the form's <Tab>
  -- keymap or by some other route.
  local id = vim.api.nvim_create_augroup("InputFormButton_" .. tostring(self.buf), { clear = true })
  self._augroup = id
  vim.api.nvim_create_autocmd("WinEnter", {
    group = id,
    buffer = self.buf,
    callback = function()
      self:_apply_winhl(true)
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = id,
    buffer = self.buf,
    callback = function()
      self:_apply_winhl(false)
    end,
  })

  self:_apply_winhl(false)
  self:_render_display()
end

--- Buttons carry no value; `form:results()` skips them entirely.
function M:value()
  return nil
end

function M:unmount()
  if self._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self._augroup)
    self._augroup = nil
  end
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
    pcall(vim.api.nvim_win_set_cursor, self.win, { 1, 0 })
  end
end

--- Invoke the button's `on_activate` callback. The form passes itself as the
--- first argument so handlers can call `form:submit()` / `form:cancel()` /
--- inspect `form:results()` without a closure.
function M:activate(form)
  if self._on_activate then
    self._on_activate(form)
  end
end

return M
