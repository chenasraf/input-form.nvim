--- *input-form.nvim*
---
--- A small Neovim plugin for showing bordered floating-window forms made up
--- of multiple typed inputs (text, multiline, select). Submit results are
--- returned to a user callback.
---
--- ==============================================================================
--- @tag input-form
--- @tag input-form.nvim

local config = require("input-form.config")
local Form = require("input-form.form")

local M = {}

--- Best-effort helptag registration. Runs on first `require('input-form')` so
--- `:h input-form` works even if the user never calls `setup()`. Idempotent.
local function register_helptags()
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(source, ":h:h:h")
  local doc_dir = plugin_root .. "/doc"
  if vim.fn.isdirectory(doc_dir) == 1 then
    pcall(vim.cmd, "silent! helptags " .. vim.fn.fnameescape(doc_dir))
  end
end

--- Configure the plugin. Calling this is OPTIONAL — the defaults work without
--- it, and `create_form` is safe to use on a bare `require('input-form')`.
--- Useful for end users who want to override defaults globally, or for wrapper
--- plugins that want to set a baseline config for their consumers.
---@tag input-form.setup
---@param opts table|nil See |input-form.config|.
---@return table The merged options table.
---@usage `require("input-form").setup({ window = { border = "single" } })`
function M.setup(opts)
  config.setup(opts)
  register_helptags()
  return config.options
end

--- Create a new form. Does NOT display it — call `form:show()` to open it.
---
---@tag input-form.create_form
---@param spec table Form specification:
---  - `inputs` (table): list of input specs, each with `name`, `label`, `type`
---    (`"text"`, `"multiline"`, `"select"`), `default?`, and for selects
---    `options` (list of `{ id, label }`).
---  - `on_submit` (function|nil): called with a `{ [name] = value }` table.
---  - `on_cancel` (function|nil): called when the form is cancelled.
---  - `title` (string|nil): override window title for this form.
---  - `width` (number|nil): override window width for this form.
---@return table Form instance exposing `:show()`, `:hide()`, `:close()`,
---  `:submit()`, `:cancel()`, `:results()`.
---@usage >
---  local f = require("input-form")
---  local form = f.create_form({
---    inputs = {
---      { name = "id", label = "Enter ID", type = "text", default = "sample ID" },
---      { name = "choice", label = "Pick one", type = "select",
---        options = { { id = "a", label = "Alpha" }, { id = "b", label = "Beta" } } },
---      { name = "body", label = "Multiline", type = "multiline" },
---    },
---    on_submit = function(results) vim.print(results) end,
---  })
---  form:show()
--- <
function M.create_form(spec)
  return Form.new(spec)
end

--- Expose the Form class for advanced use.
M.Form = Form

--- Expose the config module.
M.config = config

--- Expose the built-in validator library. See |input-form.validators|.
M.validators = require("input-form.validators")

-- Run once on first require so users/plugin devs don't have to call `setup()`
-- just to get working help tags.
register_helptags()

_G.InputForm = M
return M
