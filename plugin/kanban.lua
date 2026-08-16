if vim.fn.has("nvim-0.9.0") == 0 then
  vim.notify("nvim-kanban requires Neovim >= 0.9.0", vim.log.levels.ERROR)
  return
end

if vim.g.loaded_kanban then return end
vim.g.loaded_kanban = true

-- Auto-open board when a kanban markdown/org file is opened directly
vim.api.nvim_create_autocmd("BufReadPost", {
  group    = vim.api.nvim_create_augroup("KanbanAutoOpen", { clear = true }),
  pattern  = { "*.md", "*.org" },
  callback = function(ev)
    local path = ev.match
    -- Peek at the first few lines to detect kanban frontmatter
    local f = io.open(path, "r")
    if not f then return end
    local head = f:read(256)
    f:close()
    if not head then return end

    local is_kanban = head:match("kanban%-plugin:") or head:match("#%+KANBAN:")
    if not is_kanban then return end
    if vim.g.kanban_suspend_autoopen then return end

    -- Wipe the markdown buffer before opening the board so it never shows
    local buf = ev.buf
    vim.schedule(function()
      -- Delete the buffer first so Neovim doesn't land on it after board opens
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
      require("kanban").open(path)
    end)
  end,
})

vim.keymap.set("n", "<leader>kb", function()
  require("kanban").toggle()
end, { desc = "Toggle Kanban board" })


