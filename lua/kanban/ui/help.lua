-- Floating help window listing all keymaps.
local win_util = require("kanban.ui.window")
local M = {}

--- Open the keybinding help as a full-screen float.
---@param on_close function|nil Called when the help window is closed.
function M.open(on_close)
  local cfg = require("kanban").config
  local km  = cfg.keymaps

  local sections = {
    { "Navigation", {
      { km.next_column,     "Next column" },
      { km.prev_column,     "Prev column" },
      { km.card_down,       "Card down" },
      { km.card_up,         "Card up" },
      { km.first_card,      "First card" },
      { km.last_card,       "Last card" },
    }},
    { "Cards", {
      { km.open_card,       "Open card detail" },
      { km.add_card,        "Add card  (#tag syntax supported)" },
      { km.edit_card,       "Edit card title / tags" },
      { km.delete_card,     "Delete card (confirm)" },
      { "x",                "Delete card (no confirm)" },
      { km.archive_card,    "Archive card" },
      { km.move_card_right, "Move card to next column" },
      { km.move_card_left,  "Move card to prev column" },
      { km.move_card_up,    "Reorder card up" },
      { km.move_card_down,  "Reorder card down" },
      { km.toggle_done,     "Toggle done / undone" },
      { km.open_note,       "Open / create note file" },
      { km.set_due_date,    "Set due date (calendar picker)" },
    }},
    { "Columns", {
      { km.add_column,        "Add column" },
      { km.rename_column,     "Rename column" },
      { km.delete_column,     "Delete column (confirm)" },
      { km.move_column_left,  "Reorder column left" },
      { km.move_column_right, "Reorder column right" },
    }},
    { "Board", {
      { km.search,          "Search cards (live filter)" },
      { km.reload,          "Reload board from file" },
      { km.save,            "Save board to disk" },
      { km.open_source,     "Toggle raw source file" },
      { km.close,           "Close board" },
      { km.close2,          "Close board" },
      { km.help,            "This help screen" },
    }},
  }

  local terminal_width  = vim.o.columns
  local terminal_height = vim.o.lines
  local width  = terminal_width  - 2
  local height = terminal_height - 4

  local lines    = {}
  local hl_specs = {}

  lines[#lines + 1] = "  nvim-kanban keybindings"
  hl_specs[#hl_specs + 1] = { 0, 0, -1, "KanbanColumnHeader" }
  lines[#lines + 1] = string.rep("─", width - 2)
  hl_specs[#hl_specs + 1] = { 1, 0, -1, "KanbanColumnBorder" }

  for _, section in ipairs(sections) do
    local section_row = #lines
    lines[#lines + 1] = "  " .. section[1]
    hl_specs[#hl_specs + 1] = { section_row, 0, -1, "KanbanTag" }

    for _, entry in ipairs(section[2]) do
      local key  = entry[1] or ""
      local desc = entry[2] or ""
      if key and key ~= false then
        local key_row = #lines
        local key_str = string.format("    %-18s", key)
        lines[#lines + 1] = key_str .. desc
        hl_specs[#hl_specs + 1] = { key_row, 4, 4 + 18, "KanbanHintKey" }
        hl_specs[#hl_specs + 1] = { key_row, 4 + 18, -1, "KanbanHint" }
      end
    end
    lines[#lines + 1] = ""
  end

  lines[#lines + 1] = "  Press q or <Esc> to close"
  hl_specs[#hl_specs + 1] = { #lines - 1, 0, -1, "KanbanHint" }

  local buf = win_util.scratch_buf()
  win_util.set_lines(buf, lines)

  local ns = vim.api.nvim_create_namespace("kanban_help")
  for _, spec in ipairs(hl_specs) do
    vim.api.nvim_buf_add_highlight(buf, ns, spec[4], spec[1], spec[2], spec[3])
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = 1,
    col       = 0,
    anchor    = "NW",
    style     = "minimal",
    border    = cfg.popup.border or "rounded",
    title     = " Keybindings ",
    title_pos = "center",
    zindex    = 200,
  })

  vim.wo[win].winblend   = 100
  vim.wo[win].wrap       = false
  vim.wo[win].number     = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].winhighlight = "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"

  local map_opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if on_close then
      vim.schedule(on_close)
    end
  end

  vim.keymap.set("n", "q",     close,          map_opts)
  vim.keymap.set("n", "<Esc>", close,          map_opts)
  vim.keymap.set("n", "<BS>",  function() end, map_opts)
end

return M
