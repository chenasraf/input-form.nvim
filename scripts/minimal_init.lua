-- Add current directory to 'runtimepath' so `lua/input-form/*` is loadable.
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up mini.test and mini.doc only when running headless (make test / documentation).
if #vim.api.nvim_list_uis() == 0 then
  vim.cmd("set rtp+=deps/mini.nvim")

  require("mini.test").setup()
  require("mini.doc").setup()
end
