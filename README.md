# input-form.nvim

A small Neovim plugin for building bordered, keyboard-navigable **forms** in a
floating window. Create a single window containing multiple typed inputs
(single-line text, multiline text, select dropdowns), collect results via an
`on_submit` callback.

![input form example](/input-form.gif)

## Features

- Bordered floating window with optional title
- Keyboard-navigable: `<Tab>` / `<S-Tab>` to move between inputs
- Input types: `text`, `multiline`, `select`, `checkbox`
- Select dropdowns open with `<CR>`; arrows navigate; `<CR>` confirms
- Submit with `<C-s>` — results delivered as a `{ [name] = value }` table
- Cancel with `<Esc>`
- Lazy: `create_form` builds the form; `:show()` renders it when you want
- `:hide()` / `:show()` re-open a form while preserving in-progress values
- Fully configurable keymaps, border, width, title
- Auto-generated help doc (`:h input-form`)
- Tested with `mini.test`

## Installation

### lazy.nvim

```lua
{
  "chenasraf/input-form.nvim",
  config = function()
    require("input-form").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "chenasraf/input-form.nvim",
  config = function()
    require("input-form").setup()
  end,
})
```

### vim-plug

```vim
Plug 'chenasraf/input-form.nvim'
lua require('input-form').setup()
```

## Usage

```lua
local f = require("input-form")

local form = f.create_form({
  inputs = {
    { name = "id", label = "Enter ID", type = "text", default = "sample ID" },
    {
      name = "choice",
      label = "Select an option",
      type = "select",
      options = {
        { id = "opt1", label = "Option 1" },
        { id = "opt2", label = "Option 2" },
      },
    },
    { name = "body", label = "Enter multiline text", type = "multiline" },
  },
  on_submit = function(results)
    vim.print(results) -- { id = "...", choice = "opt1", body = "..." }
  end,
  on_cancel = function()
    vim.notify("cancelled")
  end,
})

-- Create once, show on demand:
form:show()
```

`create_form` returns a form object. Nothing is rendered until you call
`form:show()`. This lets you construct the form in one place and open it from a
keymap, autocommand, or anywhere else:

```lua
vim.keymap.set("n", "<leader>xf", function()
  form:show()
end)
```

### Form methods

| Method         | Description                                                      |
| -------------- | ---------------------------------------------------------------- |
| `form:show()`  | Open the form. No-op if already visible.                         |
| `form:hide()`  | Close windows but keep values so `:show()` resumes where you left off. |
| `form:close()` | Permanently tear down the form.                                  |
| `form:submit()`| Gather values, close, and invoke `on_submit(results)`.           |
| `form:cancel()`| Close and invoke `on_cancel()` if provided.                      |
| `form:results()`| Return `{ [name] = value }` without closing.                    |

### Input spec reference

All inputs share `name` (string, required — the key in the result table) and
`label` (string, shown above the field).

#### `text`

```lua
{ name = "id", label = "Enter ID", type = "text", default = "sample ID" }
```

#### `multiline`

```lua
{ name = "body", label = "Notes", type = "multiline", default = "", height = 5 }
```

- `height` (optional) — number of rows for the input; falls back to
  `config.multiline.height`.

#### `select`

```lua
{
  name = "choice",
  label = "Pick one",
  type = "select",
  default = "opt1", -- optional; defaults to first option's id
  options = {
    { id = "opt1", label = "Option 1" },
    { id = "opt2", label = "Option 2" },
  },
}
```

`value()` returns the selected `id` (not the label).

#### `checkbox`

```lua
{ name = "agree", label = "I agree", type = "checkbox", default = false }
```

Unlike text/multiline/select, checkboxes render **inline** — no border, no
separate label row. The glyph sits immediately next to the label, and any
validation error is appended on the same line:

```
☐ I agree (must be checked)
```

- `default` (optional) — boolean (defaults to `false`).
- `value()` returns a boolean.
- Toggled with the configured `keymaps.toggle` key (default `<Space>`) or
  the `keymaps.open_select` key (default `<CR>`) — both work so users get
  a consistent "interact with this field" key.
- Glyphs come from `style.checkbox.{checked, unchecked}` (defaults
  `"☑"` / `"☐"`).
- Pair with `validators.checked()` to require the box to be ticked (see
  [Validation](#validation)).

## Validation

Each input spec accepts an optional `validator` function:

```lua
validator = fun(value: any): string|nil
```

Return a non-empty error message string to mark the input invalid, or `nil` /
`""` when valid. The error message is shown in the input's bottom border
(red), and the border + label turn red too. Validation runs:

- **On blur** — the first time the user leaves the field it is marked
  "touched" and the validator runs. Nothing is shown before that.
- **On change** — once touched, each buffer change re-runs the validator.
- **On submit** — `form:submit()` force-validates every input (touched or
  not). If any input has an error, submission is blocked, all errors are
  rendered, and focus moves to the first invalid input.

### Built-in validators

```lua
local V = require("input-form").validators

V.non_empty([msg])                  -- require a non-empty value
V.min_length(n, [msg])              -- at least `n` characters
V.max_length(n, [msg])              -- at most `n` characters
V.matches(lua_pattern, [msg])       -- match a Lua pattern
V.is_number([msg])                  -- tonumber() must succeed
V.checked([required], [msg])        -- checkbox must equal `required`
                                    --   (default true; default messages
                                    --   "(must be checked)" /
                                    --   "(must be unchecked)")
V.one_of({ "a", "b", ... }, [msg])  -- value must be in the list
V.custom(predicate, msg)            -- wrap a `fun(v): boolean` predicate
V.chain(v1, v2, ...)                -- run validators in order, first error wins
```

Example:

```lua
local f = require("input-form")
local V = f.validators

f.create_form({
  inputs = {
    {
      name = "id",
      label = "Enter ID",
      type = "text",
      validator = V.chain(
        V.non_empty(),
        V.min_length(3),
        V.matches("^[%w_-]+$", "Only letters, digits, - and _")
      ),
    },
    {
      name = "age",
      label = "Age",
      type = "text",
      validator = V.chain(V.non_empty(), V.is_number()),
    },
  },
  on_submit = function(results)
    vim.print(results) -- only runs if every validator passes
  end,
}):show()
```

Custom validators are just functions — no need to use the builder helpers if
you'd rather write one inline:

```lua
validator = function(value)
  if value == "admin" then
    return "Username 'admin' is reserved"
  end
end
```

### Checkbox glyphs

Override the characters rendered by `checkbox` inputs via `style.checkbox`:

```lua
require("input-form").setup({
  style = {
    checkbox = {
      checked   = "☑", -- default
      unchecked = "☐", -- default
    },
  },
})
```

Alternatives that render well in most fonts: `[x]` / `[ ]`, `✔` / `·`,
`●` / `○`.

### Select chevrons

The glyphs shown on the right side of `select` inputs to indicate the
dropdown state are configurable under `style.chevron`:

```lua
require("input-form").setup({
  style = {
    chevron = {
      closed = "⌄", -- default
      open   = "⌃", -- default
    },
  },
})
```

Use whatever you like — e.g. ASCII fallbacks for terminals without good
Unicode support:

```lua
style = { chevron = { closed = " v", open = " ^" } }
```

A leading space is recommended so the glyph doesn't sit flush against the
label.

### Highlight groups

All highlight groups the plugin uses are listed under `style.highlights` in
the config and can be overridden via `setup()`. Each entry is passed directly
to `vim.api.nvim_set_hl(0, name, spec)`, so anything `nvim_set_hl` accepts
works (`fg`, `bg`, `link`, `bold`, `italic`, `default`, etc.).

```lua
require("input-form").setup({
  style = {
    highlights = {
      -- error state
      InputFormFieldError       = { fg = "#ff5555", italic = true },
      InputFormFieldErrorBorder = { fg = "#ff5555" },
      InputFormFieldErrorTitle  = { fg = "#ff5555", bold = true },
      -- help footer
      InputFormHelp             = { fg = "#88ccff" },
      -- parent frame border via link
      InputFormBorder           = { link = "Comment" },
    },
  },
})
```

Available groups:

| Group                       | Purpose                                      |
| --------------------------- | -------------------------------------------- |
| `InputFormNormal`           | Parent form window background                |
| `InputFormBorder`           | Parent form border                           |
| `InputFormTitle`            | Parent form title                            |
| `InputFormHelp`             | Footer help line (key hints)                 |
| `InputFormField`            | Individual input field background            |
| `InputFormFieldBorder`      | Individual input field border                |
| `InputFormFieldTitle`       | Individual input field label (on top border) |
| `InputFormFieldError`       | Error message footer on an invalid field     |
| `InputFormFieldErrorBorder` | Invalid field border                         |
| `InputFormFieldErrorTitle`  | Invalid field label                          |
| `InputFormDropdown`         | Select dropdown background                   |
| `InputFormDropdownActive`   | Highlighted dropdown row                     |

User overrides fully **replace** the default spec per group (they are not
deep-merged at the field level), so you don't need to re-specify
`default = true`. Highlights are re-applied on every `form:show()`, so a
`setup({ style = { highlights = ... } })` call that happens after the first
form has been rendered still takes effect on the next open.

## Configuration

Defaults:

```lua
require("input-form").setup({
  window = {
    border = "rounded",    -- any nvim_open_win border
    width = 60,            -- number of columns; <= 1 treated as ratio
    title = " Form ",
    title_pos = "center",
    winblend = 0,
    padding = 0,           -- cells between the outer border and inputs (all sides)
    gap = 0,               -- blank rows between adjacent inputs
  },
  keymaps = {
    next = "<Tab>",
    prev = "<S-Tab>",
    submit = "<C-s>",
    cancel = "<Esc>",
    open_select = "<CR>",
    toggle = "<Space>",
  },
  select = {
    max_height = 10,
  },
  multiline = {
    height = 5,
  },
})
```

Per-form overrides: pass `title` and/or `width` in the `create_form` spec.

## Help

Help tags are registered automatically on the first `require('input-form')`,
so `setup()` is not required for them either:

```
:h input-form
```

## For plugin developers — using input-form.nvim as a dependency

You can depend on `input-form.nvim` from another plugin without forcing your
users to call `setup()`. The module is safe to use immediately after require:

```lua
-- In your plugin's code:
local ok, input_form = pcall(require, 'input-form')
if not ok then
  vim.notify('my-plugin: input-form.nvim is required', vim.log.levels.ERROR)
  return
end

input_form.create_form({
  inputs = { ... },
  on_submit = function(results) ... end,
}):show()
```

Key points:

- **No `setup()` required.** Defaults are loaded at module-load time and
  `create_form` / `form:show()` work on a bare `require('input-form')`. End
  users of your plugin don't need to know input-form.nvim exists.
- **Per-form overrides.** Pass `title`, `width`, `on_cancel`, etc. directly in
  the `create_form` spec — no need to mutate global config for one-off tweaks.
- **Baseline config.** If your plugin wants a different baseline (say, a
  non-default border style for all forms it opens), call
  `require('input-form').setup({ ... })` once during your plugin's own
  initialization. This is idempotent and safe to call even if the end user
  has already called setup — later calls deep-merge over earlier ones.
- **Respect the user.** Prefer per-form overrides over global `setup()` when
  possible so you don't stomp on a user who has configured input-form.nvim
  for their own keymaps or other plugins that use it.
- **Declaring the dep.** With lazy.nvim, add it to your `dependencies`:
  ```lua
  {
    'your-name/your-plugin.nvim',
    dependencies = { 'chenasraf/input-form.nvim' },
  }
  ```

## Contributing & development

```
make deps           # install mini.nvim into deps/
make test           # run the test suite (mini.test)
make documentation  # regenerate doc/input-form.txt (mini.doc)
make lint           # stylua check
```

## License

MIT — see [LICENSE](./LICENSE).
