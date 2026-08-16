-- Public API and setup entry point for nvim-kanban.
local M = {}

M.config = {}

---@param opts table|nil User configuration (merged over defaults)
function M.setup(opts)
  local config = require("kanban.config")
  M.config = config.merge(opts)

  -- Define highlights (re-apply on colorscheme change)
  local function define_hl()
    require("kanban.ui.highlights").define(M.config.highlights)
  end
  define_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = vim.api.nvim_create_augroup("KanbanHighlights", { clear = true }),
    callback = define_hl,
  })

  -- Allow user to remap the default keymaps via setup()
  local km = M.config.keymap
  if km == false then
    pcall(vim.keymap.del, "n", "<leader>kb")
  elseif km and km ~= "<leader>kb" then
    pcall(vim.keymap.del, "n", "<leader>kb")
    vim.keymap.set("n", km, function() M.toggle() end, { desc = "Toggle Kanban board" })
  end

end

---Open a kanban board.
---@param filepath string|nil Path to board file (default: .kanban/board.md in cwd)
---@param opts table|nil { format = "markdown"|"org" }
function M.open(filepath, opts)
  require("kanban.ui").open(filepath, opts)
end

---Close the board if open.
function M.close()
  require("kanban.ui").close()
end

---Toggle the board open/closed.
---@param filepath string|nil
---@param opts table|nil
function M.toggle(filepath, opts)
  require("kanban.ui").toggle(filepath, opts)
end

---Save the board to its file.
function M.save()
  require("kanban.board").save()
end

---Return the raw board data table (for scripting).
function M.get_board()
  return require("kanban.board").get()
end

return M
