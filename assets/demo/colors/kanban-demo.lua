-- Dark Material Ocean-inspired colorscheme used only for recording
-- assets/demo.gif (see assets/demo.tape). Not part of the plugin.

vim.cmd("hi clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end
vim.o.termguicolors = true
vim.o.background = "dark"
vim.g.colors_name = "kanban-demo"

local c = {
  bg        = "#0F111A",
  bg_float  = "#1A1D2A",
  bg_select = "#223255",
  border    = "#3B3F51",
  fg        = "#B4B7C7",
  comment   = "#546E7A",
  blue      = "#82AAFF",
  purple    = "#C792EA",
  yellow    = "#FFCB6B",
  orange    = "#F78C6C",
  red       = "#FF5370",
}

local hl = vim.api.nvim_set_hl

hl(0, "Normal",      { fg = c.fg,     bg = c.bg })
hl(0, "NormalFloat", { fg = c.fg,     bg = c.bg_float })
hl(0, "FloatBorder", { fg = c.border, bg = c.bg_float })
hl(0, "FloatTitle",  { fg = c.blue,   bg = c.bg_float, bold = true })
hl(0, "Title",       { fg = c.blue,   bold = true })
hl(0, "Function",    { fg = c.blue })
hl(0, "Comment",     { fg = c.comment, italic = true })
hl(0, "Visual",      { bg = c.bg_select })
hl(0, "CursorLine",  { bg = c.bg_float })
hl(0, "Special",     { fg = c.purple })
hl(0, "WarningMsg",  { fg = c.yellow })
hl(0, "ErrorMsg",    { fg = c.red, bold = true })
hl(0, "Search",      { fg = c.bg, bg = c.yellow })
hl(0, "Constant",    { fg = c.orange })
hl(0, "NonText",     { fg = c.border })
hl(0, "EndOfBuffer",  { fg = c.bg })
hl(0, "Cursor",      { fg = c.bg, bg = c.fg })
