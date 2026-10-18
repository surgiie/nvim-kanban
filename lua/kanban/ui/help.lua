local win_util = require("kanban.ui.window")
local M = {}

local KEY_COLUMN_WIDTH = 18

local function sections(keymaps)
  return {
    { "Navigation", {
      { keymaps.next_column, "Next column" },
      { keymaps.prev_column, "Previous column" },
      { keymaps.card_down,   "Card down" },
      { keymaps.card_up,     "Card up" },
      { keymaps.first_card,  "First card" },
      { keymaps.last_card,   "Last card" },
    } },
    { "Cards", {
      { keymaps.open_card,         "Open card detail" },
      { keymaps.add_card,          "Add card (#tag syntax supported)" },
      { keymaps.edit_card,         "Edit card title / tags (clear to delete)" },
      { keymaps.delete_card,       "Delete card and note (confirm)" },
      { keymaps.force_delete_card, "Delete card and note (no confirm)" },
      { keymaps.archive_card,      "Archive card" },
      { keymaps.move_card_right,   "Move card to next column" },
      { keymaps.move_card_left,    "Move card to previous column" },
      { keymaps.move_card_up,      "Reorder card up" },
      { keymaps.move_card_down,    "Reorder card down" },
      { keymaps.toggle_done,       "Toggle done" },
      { keymaps.open_note,         "Open / create note" },
      { keymaps.set_due_date,      "Set due date" },
    } },
    { "Columns", {
      { keymaps.add_column,        "Add column" },
      { keymaps.rename_column,     "Rename column" },
      { keymaps.delete_column,     "Delete column (confirm)" },
      { keymaps.move_column_left,  "Reorder column left" },
      { keymaps.move_column_right, "Reorder column right" },
    } },
    { "Board", {
      { keymaps.search,      "Search cards" },
      { keymaps.reload,      "Reload board from file" },
      { keymaps.save,        "Save board" },
      { keymaps.open_source, "Toggle raw source file" },
      { keymaps.close,       "Close board" },
      { keymaps.close2,      "Close board" },
      { keymaps.help,        "This help screen" },
    } },
  }
end

--- Show the keymap reference; `on_close` runs after it is dismissed.
---@param on_close fun()
function M.open(on_close)
  local config = require("kanban").config
  local width  = vim.o.columns - 2
  local lines  = { "  nvim-kanban keybindings", string.rep("─", width - 2) }
  local highlights = { { 0, 0, -1, "KanbanColumnHeader" }, { 1, 0, -1, "KanbanColumnBorder" } }

  for _, section in ipairs(sections(config.keymaps)) do
    lines[#lines + 1] = "  " .. section[1]
    highlights[#highlights + 1] = { #lines - 1, 0, -1, "KanbanTag" }
    for _, entry in ipairs(section[2]) do
      if entry[1] then
        lines[#lines + 1] = string.format("    %-" .. KEY_COLUMN_WIDTH .. "s", entry[1]) .. entry[2]
        highlights[#highlights + 1] = { #lines - 1, 4, 4 + KEY_COLUMN_WIDTH, "KanbanHintKey" }
        highlights[#highlights + 1] = { #lines - 1, 4 + KEY_COLUMN_WIDTH, -1, "KanbanHint" }
      end
    end
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "  Press q or <Esc> to close"
  highlights[#highlights + 1] = { #lines - 1, 0, -1, "KanbanHint" }

  local buf = win_util.scratch_buf()
  win_util.set_lines(buf, lines)
  local ns = vim.api.nvim_create_namespace("kanban_help")
  for _, spec in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, spec[4], spec[1], spec[2], spec[3])
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = vim.o.lines - 4,
    row       = 1,
    col       = 0,
    style     = "minimal",
    border    = config.popup.border,
    title     = " Keybindings ",
    title_pos = "center",
    zindex    = 200,
  })
  vim.wo[win].winblend     = 100
  vim.wo[win].wrap         = false
  vim.wo[win].cursorline   = false
  vim.wo[win].winhighlight = "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    vim.schedule(on_close)
  end
  local map_opts = { buffer = buf, noremap = true, silent = true, nowait = true }
  vim.keymap.set("n", "q", close, map_opts)
  vim.keymap.set("n", "<Esc>", close, map_opts)
  vim.keymap.set("n", "<BS>", function() end, map_opts)
end

return M
