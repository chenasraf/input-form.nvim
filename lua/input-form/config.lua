local utils = require("input-form.utils")

local M = {}

--- Default configuration for |input-form|.
---
---@tag input-form.config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
M.defaults = {
  --- Floating window appearance.
  window = {
    --- Border style passed to `nvim_open_win`. One of `none`, `single`,
    --- `double`, `rounded`, `solid`, `shadow`, or a custom 8-element list.
    border = "rounded",
    --- Window width in columns. Numbers <= 1 are treated as a ratio of
    --- `vim.o.columns` (e.g. `0.6` = 60% of editor width).
    width = 60,
    --- Window title string. Set to `nil` to omit.
    title = " Form ",
    --- Title alignment: `"left"`, `"center"`, or `"right"`.
    title_pos = "center",
    --- Pseudo-transparency (0-100).
    winblend = 0,
    --- Padding (in cells) between the parent border and the inputs. Applied to
    --- all four sides.
    padding = 0,
    --- Blank rows rendered between adjacent inputs.
    gap = 0,
  },
  --- Keymaps used inside the form. Set any value to `false` to disable.
  keymaps = {
    --- Focus the next input (wraps).
    next = "<Tab>",
    --- Focus the previous input (wraps).
    prev = "<S-Tab>",
    --- Submit the form and invoke `on_submit(results)`.
    submit = "<C-s>",
    --- Cancel the form and invoke `on_cancel()` if provided.
    cancel = "<Esc>",
    --- Open the dropdown when focused on a `select` input.
    open_select = "<CR>",
  },
  --- Options for `select` inputs.
  select = {
    --- Maximum number of visible rows in the dropdown before scrolling.
    max_height = 10,
  },
  --- Default height (in rows) for `multiline` inputs that do not specify one.
  multiline = {
    height = 5,
  },
}

M.options = vim.deepcopy(M.defaults)

--- Merge user options over defaults and store them on the module.
---@tag input-form.config.setup
---@param user_opts table|nil
---@return table
function M.setup(user_opts)
  M.options = utils.merge(vim.deepcopy(M.defaults), user_opts or {})
  return M.options
end

return M
