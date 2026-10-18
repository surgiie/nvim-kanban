if vim.fn.has("nvim-0.9.0") == 0 then
  vim.notify("nvim-kanban requires Neovim >= 0.9.0", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_kanban then return end
vim.g.loaded_kanban = true

local function define_highlights()
  require("kanban.ui.highlights").define(require("kanban").config.highlights)
end
define_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group    = vim.api.nvim_create_augroup("KanbanHighlights", { clear = true }),
  callback = define_highlights,
})

-- Opening a markdown file directly inside .kanban/ shows it as a board
vim.api.nvim_create_autocmd("BufReadPost", {
  group    = vim.api.nvim_create_augroup("KanbanAutoOpen", { clear = true }),
  pattern  = "*/.kanban/*.md",
  callback = function(event)
    -- `*` in the pattern also matches `/`, so this also fires for .kanban/notes/*.md
    if vim.g.kanban_suspend_autoopen or not require("kanban.util").is_board_path(event.match) then return end
    vim.schedule(function()
      require("kanban.ui.window").delete_buf_keep_windows(event.buf)
      require("kanban").open(event.match)
    end)
  end,
})

vim.api.nvim_create_user_command("Kanban", function(command)
  require("kanban").toggle(command.args ~= "" and command.args or nil)
end, { nargs = "?", complete = "file", desc = "Toggle the kanban board (default .kanban/board.md)" })

vim.keymap.set("n", "<leader>kb", function()
  require("kanban").toggle()
end, { desc = "Toggle Kanban board" })
