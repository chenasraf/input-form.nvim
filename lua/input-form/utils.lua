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

--- The filetype set on every buffer the plugin owns. Users can add this to
--- their UI plugins' exclusion lists as a fallback.
M.FORM_FILETYPE = "input-form"

--- Character sets for the built-in border styles accepted by `nvim_open_win`.
--- Order is clockwise from top-left: TL, T, TR, R, BR, B, BL, L.
local BORDER_CHARS = {
  rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│" },
  single = { "┌", "─", "┐", "│", "┘", "─", "└", "│" },
  double = { "╔", "═", "╗", "║", "╝", "═", "╚", "║" },
  solid = { " ", " ", " ", " ", " ", " ", " ", " " },
}

-- T-junction connectors used to replace the top corners when stitching two
-- boxes together (the bottom of box A and the top of box B share a row).
local MERGE_CONNECTORS = {
  rounded = { left = "├", right = "┤" },
  single = { left = "├", right = "┤" },
  double = { left = "╠", right = "╣" },
  solid = { left = " ", right = " " },
}

--- Build an 8-element border array whose top row is a T-junction stitching
--- into the bottom of a parent box above it. Accepts either one of the
--- built-in border style names or an existing 8-element border array.
---
--- Returns `nil` for unrecognised / non-mergeable borders (e.g. `"none"`,
--- `"shadow"`) so the caller can fall back to an unmerged layout.
---@param border string|table
---@return table|nil
function M.merged_top_border(border)
  local chars, connectors
  if type(border) == "string" then
    chars = BORDER_CHARS[border]
    connectors = MERGE_CONNECTORS[border]
  elseif type(border) == "table" and #border == 8 then
    chars = vim.deepcopy(border)
    -- Best-effort fallback for custom arrays: use the straight T's.
    connectors = { left = "├", right = "┤" }
  end
  if not chars or not connectors then
    return nil
  end
  return {
    connectors.left,
    chars[2],
    connectors.right,
    chars[4],
    chars[5],
    chars[6],
    chars[7],
    chars[8],
  }
end

local _excluded_registered = false

-- Append `ft` to a list-shaped config field if missing.
local function ensure_excluded(cfg, key, ft)
  if type(cfg) ~= "table" then
    return
  end
  cfg[key] = cfg[key] or {}
  if not vim.tbl_contains(cfg[key], ft) then
    table.insert(cfg[key], ft)
  end
end

--- Tell known UI plugins (scrollbars, indent guides, etc.) to skip buffers
--- with filetype `input-form`. Idempotent. Called lazily on the first
--- `form:show()` so it works whether or not the user called `setup()`.
function M.register_ui_exclusions()
  if _excluded_registered then
    return
  end
  _excluded_registered = true

  -- nvim-scrollbar (petertriho/nvim-scrollbar).
  -- Its real config lives at `require("scrollbar.config")` — the module stores
  -- the active table under `.config` and exposes it via `.get()`. We patch
  -- both paths defensively in case the module layout differs across versions.
  local ok, sbar_cfg = pcall(require, "scrollbar.config")
  if ok and sbar_cfg then
    if type(sbar_cfg.get) == "function" then
      local cfg = sbar_cfg.get()
      ensure_excluded(cfg, "excluded_filetypes", M.FORM_FILETYPE)
      ensure_excluded(cfg, "excluded_buftypes", "nofile")
    end
    if type(sbar_cfg.config) == "table" then
      ensure_excluded(sbar_cfg.config, "excluded_filetypes", M.FORM_FILETYPE)
    end
  end
  -- Some older layouts exposed the config directly on the main module.
  local ok_top, sbar = pcall(require, "scrollbar")
  if ok_top and type(sbar) == "table" and type(sbar.config) == "table" then
    ensure_excluded(sbar.config, "excluded_filetypes", M.FORM_FILETYPE)
  end

  -- satellite.nvim (lewis6991/satellite.nvim).
  local ok2, sat_cfg = pcall(require, "satellite.config")
  if ok2 and sat_cfg then
    if type(sat_cfg.user_config) == "table" then
      ensure_excluded(sat_cfg.user_config, "excluded_filetypes", M.FORM_FILETYPE)
    end
    if type(sat_cfg.config) == "table" then
      ensure_excluded(sat_cfg.config, "excluded_filetypes", M.FORM_FILETYPE)
    end
  end
end

--- Mark a buffer as an internal form buffer so third-party UI plugins
--- (scrollbars, indent guides, git signs, etc.) skip it.
---
--- Sets `filetype = "input-form"` plus the opt-out buffer variables
--- recognized by common plugins. Users whose plugins don't honour these can
--- add `input-form` to their plugin's exclusion list.
function M.mark_form_buffer(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  vim.bo[buf].filetype = M.FORM_FILETYPE
  -- nvim-scrollbar (petertriho/nvim-scrollbar)
  vim.b[buf].scrollbar_disabled = true
  -- satellite.nvim (lewis6991/satellite.nvim)
  vim.b[buf].satellite_disable = true
  -- mini.indentscope / mini.map
  vim.b[buf].miniindentscope_disable = true
  vim.b[buf].minimap_disable = true
  -- gitsigns (defensive; unlikely on a nofile buf but cheap)
  vim.b[buf].gitsigns_disable = true
end

return M
