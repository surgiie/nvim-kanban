local M = {}

M.config = require("kanban.config").defaults

local DEFAULT_TOGGLE_KEYMAP = "<leader>kb"

---@param opts table|nil Merged over the defaults in kanban.config
function M.setup(opts)
  M.config = require("kanban.config").merge(opts)
  -- plugin/kanban.lua re-applies these on ColorScheme from the current config
  require("kanban.ui.highlights").define(M.config.highlights)

  -- plugin/kanban.lua maps the default key before setup runs
  if M.config.keymap ~= DEFAULT_TOGGLE_KEYMAP then
    pcall(vim.keymap.del, "n", DEFAULT_TOGGLE_KEYMAP)
    if M.config.keymap then
      vim.keymap.set("n", M.config.keymap, M.toggle, { desc = "Toggle Kanban board" })
    end
  end
end

---@param filepath string|nil Defaults to .kanban/board.md in the cwd
function M.open(filepath)
  require("kanban.ui").open(filepath)
end

function M.close()
  require("kanban.ui").close()
end

---@param filepath string|nil
function M.toggle(filepath)
  require("kanban.ui").toggle(filepath)
end

function M.save()
  require("kanban.board").save()
end

--- The loaded board table, for scripting.
---@return table|nil
function M.get_board()
  return require("kanban.board").get()
end

return M
