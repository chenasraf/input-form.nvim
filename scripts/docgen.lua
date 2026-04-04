-- Custom mini.doc entrypoint that only processes the public-facing files so
-- internal `M.new`, `M.merge`, etc. helpers don't collide on duplicate tags.
require("mini.doc").setup()

MiniDoc.generate({
  "lua/input-form/init.lua",
  "lua/input-form/config.lua",
}, "doc/input-form.txt")
