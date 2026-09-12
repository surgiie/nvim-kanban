-- Minimal config used to record assets/demo.gif with VHS. Not part of the
-- plugin's public API — see assets/demo.tape for how this is invoked.

local demo_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local repo_root = vim.fn.fnamemodify(demo_dir, ":h:h")
vim.opt.rtp:prepend(repo_root)

vim.opt.termguicolors = true
vim.opt.swapfile = false
vim.opt.number = false
vim.opt.laststatus = 0
vim.opt.cmdheight = 1
vim.cmd.colorscheme("habamax")

require("kanban").setup()
