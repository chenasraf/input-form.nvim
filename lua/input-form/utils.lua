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
