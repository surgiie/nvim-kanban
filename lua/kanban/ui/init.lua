-- Main UI controller: owns the board state cursor and routes all user actions.
local board_view = require("kanban.ui.board_view")
local win_util   = require("kanban.ui.window")
local board_mod  = require("kanban.board")
local util       = require("kanban.util")
local M = {}

-- Cursor into the board: which column/card is currently focused.
M._state = { col_idx = 1, card_idx = 1 }
M._keymaps_attached = {}
M._filepath = nil
M._trap_suspended = false
M._trap_augroup = nil
M._open_gen = 0  -- incremented each open; lets scheduled callbacks detect stale closes

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Return the plugin config table.
local function cfg()
  return require("kanban").config
end

-- Return the currently loaded board table (always non-nil when the board is open).
---@return table
local function board()
  return board_mod.get() --[[@as table]]
end

-- Return the total number of columns in the loaded board.
local function num_cols()
  return board_mod.column_count()
end

-- Return the number of cards in the given column.
local function num_cards(col_idx)
  local col = board_mod.get_column(col_idx)
  return col and #col.cards or 0
end

-- Clamp the UI cursor so col_idx and card_idx stay within valid bounds.
local function clamp_state()
  local num_columns = num_cols()
  if num_columns == 0 then M._state.col_idx = 1; M._state.card_idx = 0; return end

  M._state.col_idx  = math.max(1, math.min(M._state.col_idx, num_columns))
  local cards = num_cards(M._state.col_idx)
  if cards == 0 then
    M._state.card_idx = 0
  else
    M._state.card_idx = math.max(1, math.min(M._state.card_idx, cards))
  end
end

-- Save the board to disk when auto_save is enabled.
local function save_if_auto()
  if cfg().auto_save then board_mod.save() end
end

-- Clamp cursor, re-render all columns, and re-attach keymaps.
local function refresh()
  clamp_state()
  local b = board()
  if not b then return end
  board_view.refresh_all(b, M._state)
  M._attach_keymaps()
end

-- Show a [kanban] prefixed notification.
local function notify(msg, level)
  vim.notify("[kanban] " .. msg, level or vim.log.levels.INFO)
end

-- ── Actions ──────────────────────────────────────────────────────────────────

local actions = {}

-- ── Navigation ───────────────────────────────────────────────────────────────

-- Move focus to the next column.
function actions.next_column()
  if M._state.col_idx >= num_cols() then return end
  M._state.col_idx  = M._state.col_idx + 1
  M._state.card_idx = math.max(1, math.min(M._state.card_idx, num_cards(M._state.col_idx)))
  if num_cards(M._state.col_idx) == 0 then M._state.card_idx = 0 end
  board_view.refresh_all(board(), M._state)
  board_view.focus_column(M._state.col_idx)
  M._attach_keymaps()
end

-- Move focus to the previous column.
function actions.prev_column()
  if M._state.col_idx <= 1 then return end
  M._state.col_idx  = M._state.col_idx - 1
  M._state.card_idx = math.max(1, math.min(M._state.card_idx, num_cards(M._state.col_idx)))
  if num_cards(M._state.col_idx) == 0 then M._state.card_idx = 0 end
  board_view.refresh_all(board(), M._state)
  board_view.focus_column(M._state.col_idx)
  M._attach_keymaps()
end

-- Move the card cursor down by one.
function actions.card_down()
  local cards = num_cards(M._state.col_idx)
  if cards == 0 then return end
  M._state.card_idx = math.min(M._state.card_idx + 1, cards)
  board_view.refresh_column(board(), M._state.col_idx, M._state)
end

-- Move the card cursor up by one.
function actions.card_up()
  if num_cards(M._state.col_idx) == 0 then return end
  M._state.card_idx = math.max(M._state.card_idx - 1, 1)
  board_view.refresh_column(board(), M._state.col_idx, M._state)
end

-- Jump to the first card in the current column.
function actions.first_card()
  if num_cards(M._state.col_idx) == 0 then return end
  M._state.card_idx = 1
  board_view.refresh_column(board(), M._state.col_idx, M._state)
end

-- Jump to the last card in the current column.
function actions.last_card()
  local cards = num_cards(M._state.col_idx)
  if cards == 0 then return end
  M._state.card_idx = cards
  board_view.refresh_column(board(), M._state.col_idx, M._state)
end

-- ── Card actions ─────────────────────────────────────────────────────────────

-- Move the focused card one position up within its column.
function actions.move_card_up()
  if M._state.card_idx <= 1 then return end
  local col_idx  = M._state.col_idx
  local card_idx = M._state.card_idx
  local new_pos  = card_idx - 1
  local ok = board_mod.move_card(col_idx, card_idx, col_idx, new_pos)
  if not ok then return end
  M._state.card_idx = new_pos
  save_if_auto()
  board_view.refresh_column(board(), col_idx, M._state)
end

-- Move the focused card one position down within its column.
function actions.move_card_down()
  local col_idx  = M._state.col_idx
  local card_idx = M._state.card_idx
  if card_idx >= num_cards(col_idx) then return end
  local new_pos = card_idx + 1
  local ok = board_mod.move_card(col_idx, card_idx, col_idx, new_pos)
  if not ok then return end
  M._state.card_idx = new_pos
  save_if_auto()
  board_view.refresh_column(board(), col_idx, M._state)
end

-- Toggle the done state of the focused card.
function actions.toggle_done()
  if M._state.card_idx == 0 then return end
  board_mod.toggle_done(M._state.col_idx, M._state.card_idx)
  save_if_auto()
  board_view.refresh_column(board(), M._state.col_idx, M._state)
end

-- Move the focused card one column to the right.
function actions.move_card_right()
  if M._state.card_idx == 0 then return end
  local to_col = M._state.col_idx + 1
  if to_col > num_cols() then return end

  local from_col  = M._state.col_idx
  local from_card = M._state.card_idx
  local success, new_pos = board_mod.move_card(from_col, from_card, to_col)
  if not success then return end

  -- Move focus with the card
  M._state.col_idx  = to_col
  M._state.card_idx = new_pos
  clamp_state()
  save_if_auto()
  board_view.refresh_all(board(), M._state)
  board_view.focus_column(M._state.col_idx)
  M._attach_keymaps()
end

-- Move the focused card one column to the left.
function actions.move_card_left()
  if M._state.card_idx == 0 then return end
  local to_col = M._state.col_idx - 1
  if to_col < 1 then return end

  local from_col  = M._state.col_idx
  local from_card = M._state.card_idx
  local success, new_pos = board_mod.move_card(from_col, from_card, to_col)
  if not success then return end

  M._state.col_idx  = to_col
  M._state.card_idx = new_pos
  clamp_state()
  save_if_auto()
  board_view.refresh_all(board(), M._state)
  board_view.focus_column(M._state.col_idx)
  M._attach_keymaps()
end

-- Open an input float to add a new card to the focused column.
function actions.add_card()
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  local saved_file = M._filepath --[[@as string]]
  board_view.close()
  win_util.input_float({
    title      = cfg().icons.add .. " New card",
    border     = cfg().popup.border,
    width      = cfg().popup.width,
    height     = cfg().popup.height,
    zindex     = cfg().popup.zindex,
    on_confirm = function(input)
      if input == "" then
        M._state = { col_idx = saved_col, card_idx = saved_card }
        M.open(saved_file)
        return
      end
      local tags = {}
      local text = input:gsub("#([%w_%-]+)", function(tag)
        tags[#tags + 1] = tag
        return ""
      end)
      local card_title = util.trim(text)
      if card_title == "" then
        M._state = { col_idx = saved_col, card_idx = saved_card }
        M.open(saved_file)
        return
      end
      board_mod.load(saved_file)
      local _, pos = board_mod.add_card(saved_col, card_title, { tags = tags })
      M._state = { col_idx = saved_col, card_idx = pos }
      save_if_auto()
      M.open(saved_file)
    end,
    on_cancel = function()
      M._state = { col_idx = saved_col, card_idx = saved_card }
      M.open(saved_file)
    end,
  })
end

-- Open an input float pre-filled with the focused card's title for editing.
function actions.edit_card()
  if M._state.card_idx == 0 then return end
  local card = board_mod.get_card(M._state.col_idx, M._state.card_idx)
  if not card then return end

  local default = card.title
  for _, tag in ipairs(card.tags or {}) do
    default = default .. " #" .. tag
  end
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  local saved_file = M._filepath --[[@as string]]
  board_view.close()
  win_util.input_float({
    title      = cfg().icons.edit .. " Edit card",
    default    = default,
    border     = cfg().popup.border,
    width      = cfg().popup.width,
    height     = cfg().popup.height,
    zindex     = cfg().popup.zindex,
    on_confirm = function(input)
      local tags = {}
      local text = input:gsub("#([%w_%-]+)", function(tag)
        tags[#tags + 1] = tag
        return ""
      end)
      local new_title = util.trim(text)
      if new_title ~= "" then
        board_mod.load(saved_file)
        board_mod.update_card(saved_col, saved_card, { title = new_title, tags = tags })
        save_if_auto()
      end
      M._state = { col_idx = saved_col, card_idx = saved_card }
      M.open(saved_file)
    end,
    on_cancel = function()
      M._state = { col_idx = saved_col, card_idx = saved_card }
      M.open(saved_file)
    end,
  })
end

-- Delete the focused card immediately without asking for confirmation.
local function do_delete_card()
  board_mod.delete_card(M._state.col_idx, M._state.card_idx)
  local cards = num_cards(M._state.col_idx)
  M._state.card_idx = math.min(M._state.card_idx, math.max(cards, 0))
  if cards == 0 then M._state.card_idx = 0 end
  save_if_auto()
  refresh()
end

-- Delete the focused card without confirmation.
function actions.force_delete_card()
  if M._state.card_idx == 0 then return end
  if not board_mod.get_card(M._state.col_idx, M._state.card_idx) then return end
  do_delete_card()
end

-- Prompt for confirmation then delete the focused card.
function actions.delete_card()
  if M._state.card_idx == 0 then return end
  local card = board_mod.get_card(M._state.col_idx, M._state.card_idx)
  if not card then return end

  local answer = vim.fn.confirm(
    "Delete card: \"" .. card.title .. "\"?",
    "&Yes\n&No", 2
  )
  if answer ~= 1 then return end

  do_delete_card()
end

-- Move the focused card to the archive column.
function actions.archive_card()
  if M._state.card_idx == 0 then return end
  local success = board_mod.archive_card(M._state.col_idx, M._state.card_idx)
  if not success then return end
  local cards = num_cards(M._state.col_idx)
  M._state.card_idx = math.min(M._state.card_idx, math.max(cards, 1))
  if num_cards(M._state.col_idx) == 0 then M._state.card_idx = 0 end
  save_if_auto()
  refresh()
end

-- Open the date picker to set a due date on the focused card.
function actions.set_due_date()
  if M._state.card_idx == 0 then return end
  local card = board_mod.get_card(M._state.col_idx, M._state.card_idx)
  if not card then return end

  require("kanban.ui.datepicker").open({
    current_date = card.due_date,
    on_confirm   = function(date_str)
      board_mod.update_card(M._state.col_idx, M._state.card_idx, { due_date = date_str })
      save_if_auto()
      board_view.refresh_column(board(), M._state.col_idx, M._state)
    end,
  })
end

-- Open the note file associated with the focused card (creating it if needed).
-- The note path is only attached to the card after the file is actually written.
function actions.open_note()
  if M._state.card_idx == 0 then return end
  local card = board_mod.get_card(M._state.col_idx, M._state.card_idx)
  if not card then return end

  local path       = board_mod.open_note(card)
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  local saved_file = M._filepath --[[@as string]]

  actions.close()
  vim.cmd("edit " .. vim.fn.fnameescape(path))

  local note_buf = vim.api.nvim_get_current_buf()
  local note_win = vim.api.nvim_get_current_win()
  local reopened = false

  -- Returns true if the note file on disk has non-blank content.
  local function file_has_content()
    local f = io.open(path, "r")
    if not f then return false end
    local data = f:read("*a")
    f:close()
    return data ~= nil and not data:match("^%s*$")
  end

  local function reopen_board()
    if reopened then return end
    reopened = true
    if file_has_content() then
      -- Ensure the card has the note path attached.
      if not card.note_file then
        board_mod.update_card(saved_col, saved_card, { note_file = path })
        save_if_auto()
      end
    else
      -- File is empty or missing — remove it and detach from card.
      os.remove(path)
      if card.note_file then
        card.note_file = nil
        board_mod.mark_modified()
        save_if_auto()
      end
    end
    vim.schedule(function()
      M._state = { col_idx = saved_col, card_idx = saved_card }
      M.open(saved_file)
    end)
  end

  -- WinClosed catches :q (window close without buffer delete).
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(note_win),
    once     = true,
    callback = reopen_board,
  })

  -- BufDelete/BufWipeout catches :bd, :bw, and buffer deletion.
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    buffer   = note_buf,
    once     = true,
    callback = reopen_board,
  })
end

-- Open the focused card's note file, or show a detail popup if no note exists.
function actions.open_card()
  if M._state.card_idx == 0 then return end
  local card = board_mod.get_card(M._state.col_idx, M._state.card_idx)
  if not card then return end

  -- Always show the detail popup first; the note is opened from there via [n].
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  local saved_file = M._filepath --[[@as string]]

  -- Close the board before showing the full-screen detail.
  board_view.close()

  local terminal_width  = vim.o.columns
  local terminal_height = vim.o.lines

  -- win/buf are upvalues shared between show_detail and the keymaps.
  local win, buf

  -- Build and (re)render the detail window contents.
  -- Called once on open and again after note deletion to refresh.
  local function show_detail()
    -- Refresh card data in case note_file was just cleared.
    card = board_mod.get_card(saved_col, saved_card) or card

    local col = board_mod.get_column(saved_col)
    local lines = { "  " .. card.title, "" }
    if col then
      lines[#lines + 1] = "  Column:   " .. col.name
    end
    lines[#lines + 1] = "  Status:   " .. (card.done and "Done" or "In progress")
    if card.due_date and card.due_date ~= "" then
      lines[#lines + 1] = "  Due:      " .. card.due_date
    end
    if #(card.tags or {}) > 0 then
      lines[#lines + 1] = "  Tags:     " .. table.concat(card.tags, ", ")
    end
    if card.note_file then
      lines[#lines + 1] = "  Note:     " .. card.note_file
      lines[#lines + 1] = ""
      lines[#lines + 1] = "  [e] edit  [D] due  [n] open note  [x] delete note  [q/<Esc>] close"
    else
      lines[#lines + 1] = ""
      lines[#lines + 1] = "  [e] edit  [D] due  [n] create note  [q/<Esc>] close"
    end

    if buf and vim.api.nvim_buf_is_valid(buf) then
      -- Reuse existing buffer — just replace the lines.
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
    else
      buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype    = "nofile"
      vim.bo[buf].bufhidden  = "wipe"
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
    end

    local ns = vim.api.nvim_create_namespace("kanban_detail")
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "KanbanColumnHeader", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "KanbanHint", #lines - 1, 0, -1)

    if win and vim.api.nvim_win_is_valid(win) then
      -- Already open — just update the buffer reference.
      vim.api.nvim_win_set_buf(win, buf)
    else
      win = vim.api.nvim_open_win(buf, true, {
        relative   = "editor",
        width      = terminal_width  - 2,
        height     = terminal_height - 4,
        row        = 1,
        col        = 0,
        anchor     = "NW",
        style      = "minimal",
        border     = cfg().popup.border or "rounded",
        title      = " Card detail ",
        title_pos  = "center",
        footer     = "  [e] edit  [D] due  [n] note  [x] delete note  [q/<Esc>] close  ",
        footer_pos = "right",
        zindex     = 200,
      })
      vim.wo[win].winblend    = 100
      vim.wo[win].wrap        = false
      vim.wo[win].number      = false
      vim.wo[win].signcolumn  = "no"
      vim.wo[win].cursorline  = false
      vim.wo[win].winhighlight =
        "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"
    end

    -- Keymaps are set on the buffer so they survive a buf swap.
    local map_opts = { buffer = buf, noremap = true, silent = true, nowait = true }

    -- Close detail and reopen the board.
    local function close()
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      M._state = { col_idx = saved_col, card_idx = saved_card }
      M.open(saved_file)
    end

    vim.keymap.set("n", "q",     close,                                         map_opts)
    vim.keymap.set("n", "<Esc>", close,                                         map_opts)
    vim.keymap.set("n", "e",     function() close(); actions.edit_card()    end, map_opts)
    vim.keymap.set("n", "D",     function() close(); actions.set_due_date() end, map_opts)

    -- [n] open/create note; note path is only attached to the card after first write.
    vim.keymap.set("n", "n", function()
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      M._state   = { col_idx = saved_col, card_idx = saved_card }
      M._filepath = saved_file
      -- Re-fetch card so we get the latest note_file state.
      local fresh_card = board_mod.get_card(saved_col, saved_card) or card
      local path       = board_mod.open_note(fresh_card)
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      local note_buf = vim.api.nvim_get_current_buf()
      local note_win = vim.api.nvim_get_current_win()
      local reopened = false

      local function file_has_content()
        local f = io.open(path, "r")
        if not f then return false end
        local data = f:read("*a")
        f:close()
        return data ~= nil and not data:match("^%s*$")
      end

      local function reopen_board()
        if reopened then return end
        reopened = true
        if file_has_content() then
          if not fresh_card.note_file then
            board_mod.update_card(saved_col, saved_card, { note_file = path })
            save_if_auto()
          end
        else
          os.remove(path)
          if fresh_card.note_file then
            fresh_card.note_file = nil
            board_mod.mark_modified()
            save_if_auto()
          end
        end
        vim.schedule(function()
          M._state = { col_idx = saved_col, card_idx = saved_card }
          M.open(saved_file)
        end)
      end

      -- WinClosed catches :q; BufDelete/BufWipeout catches :bd/:bw.
      vim.api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(note_win),
        once     = true,
        callback = reopen_board,
      })
      vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        buffer   = note_buf,
        once     = true,
        callback = reopen_board,
      })
    end, map_opts)

    -- [x] delete the note file and clear it from the card, then refresh detail.
    vim.keymap.set("n", "x", function()
      local c = board_mod.get_card(saved_col, saved_card)
      if not c or not c.note_file then return end
      local answer = vim.fn.confirm(
        "Delete note file \"" .. c.note_file .. "\"?",
        "&Yes\n&No", 2
      )
      if answer ~= 1 then return end
      -- Delete the file from disk (ignore errors if already gone).
      os.remove(c.note_file)
      -- Clear the note_file field directly (update_card uses pairs, which skips nil).
      c.note_file = nil
      board_mod.mark_modified()
      save_if_auto()
      -- Refresh the detail view in place.
      show_detail()
    end, map_opts)

    -- Block other editing keys.
    local noop = function() end
    for _, key in ipairs({ "i","I","o","O","a","A","s","S","c","C","r","R","v","V",
                           "<C-v>","X","p","P","u","<C-r>",".","~","dd","yy" }) do
      vim.keymap.set("n", key, noop, map_opts)
    end
  end

  show_detail()
end

-- ── Column actions ───────────────────────────────────────────────────────────

-- Open an input float to add a new column after the current one.
function actions.add_column()
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  local saved_file = M._filepath --[[@as string]]
  board_view.close()
  win_util.small_input_float({
    title       = cfg().icons.add .. " New Column Name",
    placeholder = "Column name ...",
    border      = cfg().popup.border,
    on_confirm  = function(name)
      if name == "" then
        M._state = { col_idx = saved_col, card_idx = saved_card }
        M.open(saved_file)
        return
      end
      local new_idx = board_mod.add_column(name)
      M._state = { col_idx = new_idx or 1, card_idx = 0 }
      save_if_auto()
      M.open(saved_file)
    end,
    on_cancel = function()
      M._state = { col_idx = saved_col, card_idx = saved_card }
      M.open(saved_file)
    end,
  })
end

-- Open a small centered input pre-filled with the column name for renaming.
function actions.rename_column()
  local col = board_mod.get_column(M._state.col_idx)
  if not col then return end
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  local saved_file = M._filepath --[[@as string]]
  board_view.close()
  win_util.small_input_float({
    title       = cfg().icons.edit .. " Rename Column",
    default     = col.name,
    placeholder = "Column name ...",
    border      = cfg().popup.border,
    on_confirm  = function(name)
      if name == "" then
        M._state = { col_idx = saved_col, card_idx = saved_card }
        M.open(saved_file)
        return
      end
      board_mod.rename_column(saved_col, name)
      M._state = { col_idx = saved_col, card_idx = saved_card }
      save_if_auto()
      M.open(saved_file)
    end,
    on_cancel = function()
      M._state = { col_idx = saved_col, card_idx = saved_card }
      M.open(saved_file)
    end,
  })
end

-- Prompt for confirmation then delete the focused column and all its cards.
function actions.delete_column()
  local col = board_mod.get_column(M._state.col_idx)
  if not col then return end
  if num_cols() <= 1 then
    notify("Cannot delete the last column.")
    return
  end

  local saved_col  = M._state.col_idx
  local saved_file = M._filepath --[[@as string]]
  board_view.close()

  local answer = vim.fn.confirm(
    "Delete column \"" .. col.name .. "\" and all its cards?",
    "&Yes\n&No", 2
  )

  if answer ~= 1 then
    M._state = { col_idx = saved_col, card_idx = M._state.card_idx }
    M.open(saved_file)
    return
  end

  board_mod.delete_column(saved_col)
  M._state.col_idx  = math.max(1, math.min(saved_col, num_cols()))
  M._state.card_idx = 1
  if num_cards(M._state.col_idx) == 0 then M._state.card_idx = 0 end
  save_if_auto()
  M.open(saved_file)
end

-- Move the focused column one position to the left.
function actions.move_column_left()
  local new_idx = board_mod.move_column(M._state.col_idx, -1)
  M._state.col_idx  = new_idx
  M._state.card_idx = 1
  save_if_auto()
  refresh()
end

-- Move the focused column one position to the right.
function actions.move_column_right()
  local new_idx = board_mod.move_column(M._state.col_idx, 1)
  M._state.col_idx  = new_idx
  M._state.card_idx = 1
  save_if_auto()
  refresh()
end

-- ── Board actions ────────────────────────────────────────────────────────────

-- Open the search popup and jump to the selected result.
function actions.search()
  require("kanban.ui.search").open(function(col_idx, card_idx)
    M._state.col_idx  = col_idx
    M._state.card_idx = card_idx
    board_view.refresh_all(board(), M._state)
    board_view.focus_column(M._state.col_idx)
    M._attach_keymaps()
  end)
end

-- Reload the board from disk and re-render.
function actions.reload()
  if not M._filepath then return end
  board_mod.load(M._filepath)
  clamp_state()
  board_view.refresh_all(board(), M._state)
  M._attach_keymaps()
  notify("Board reloaded.")
end

-- Manually save the board to disk.
function actions.save()
  board_mod.save()
  notify("Board saved.")
end

-- Close all board windows and clean up autocmd groups.
function actions.close()
  board_view.close()
  M._keymaps_attached = {}
  if M._trap_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._trap_augroup)
    M._trap_augroup = nil
  end
end

-- Close the board and open the source file for direct editing.
function actions.open_source()
  local path = M._filepath
  if not path then return end
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  actions.close()
  vim.g.kanban_suspend_autoopen = true
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.g.kanban_suspend_autoopen = nil
  local src_buf = vim.api.nvim_get_current_buf()

  -- Map <leader>kt in the source buffer to return to the board
  local km = cfg().keymaps
  local toggle_key = km.open_source or "<leader>kt"
  vim.keymap.set("n", toggle_key, function()
    vim.api.nvim_buf_delete(src_buf, { force = true })
    M._state = { col_idx = saved_col, card_idx = saved_card }
    M.open(path)
  end, { buffer = src_buf, noremap = true, silent = true, desc = "Return to kanban board" })

  -- Also reopen if the buffer is wiped/deleted any other way
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    buffer = src_buf,
    once   = true,
    callback = function()
      vim.schedule(function()
        M._state = { col_idx = saved_col, card_idx = saved_card }
        M.open(path)
      end)
    end,
  })
end

-- Open the keybinding help popup.
function actions.help()
  local saved_col  = M._state.col_idx
  local saved_card = M._state.card_idx
  local saved_file = M._filepath --[[@as string]]
  board_view.close()
  require("kanban.ui.help").open(function()
    M._state = { col_idx = saved_col, card_idx = saved_card }
    M.open(saved_file)
  end)
end

-- ── Keymap attachment ────────────────────────────────────────────────────────

--- Attach all configured keymaps to every column buffer that does not yet have them.
function M._attach_keymaps()
  -- Attach keymaps to each column buffer so focus always works
  for i = 1, num_cols() do
    local entry = board_view.col_entry(i)
    if not entry then goto continue end
    local buf = entry.buf
    if M._keymaps_attached[buf] then goto continue end
    M._keymaps_attached[buf] = true

    -- Board buffers are read-only — no editing allowed
    vim.bo[buf].modifiable = false

    local km = cfg().keymaps

    local function map(key, fn)
      if key and key ~= false then
        vim.keymap.set("n", key, function()
          -- When a column buffer is focused but our state says different col,
          -- update col_idx first so actions operate on the right column.
          -- (This handles mouse clicks or <Tab> jumping into the win.)
          M._state.col_idx = i
          fn()
        end, { buffer = buf, noremap = true, silent = true, nowait = true })
      end
    end

    map(km.next_column,     actions.next_column)
    map(km.prev_column,     actions.prev_column)
    map(km.card_down,       actions.card_down)
    map(km.card_up,         actions.card_up)
    map(km.first_card,      actions.first_card)
    map(km.last_card,       actions.last_card)
    map(km.open_card,       actions.open_card)
    map(km.add_card,        actions.add_card)
    map(km.edit_card,       actions.edit_card)
    map(km.move_card_up,    actions.move_card_up)
    map(km.move_card_down,  actions.move_card_down)
    map(km.delete_card,     actions.delete_card)
    map("x",                actions.force_delete_card)
    map(km.archive_card,    actions.archive_card)
    map(km.move_card_right, actions.move_card_right)
    map(km.move_card_left,  actions.move_card_left)
    map(km.toggle_done,     actions.toggle_done)
    map(km.open_note,       actions.open_note)
    map(km.set_due_date,    actions.set_due_date)
    map(km.add_column,        actions.add_column)
    map(km.rename_column,     actions.rename_column)
    map(km.delete_column,     actions.delete_column)
    map(km.move_column_left,  actions.move_column_left)
    map(km.move_column_right, actions.move_column_right)
    map(km.search,          actions.search)
    map(km.reload,          actions.reload)
    map(km.save,            actions.save)
    map(km.open_source,     actions.open_source)
    map(km.close,           actions.close)
    map(km.close2,          actions.close)
    map(km.help,            actions.help)

    -- Block insert/replace/visual/editing keys that aren't already bound to an action.
    local noop = function() end
    local action_keys = {}
    for _, v in pairs(km) do
      if v and v ~= false then action_keys[v] = true end
    end
    action_keys["x"] = true  -- force_delete_card
    local block = {
      "i", "I", "o", "O", "s", "S", "c", "C", "cc",
      "r", "R", "v", "V", "<C-v>", "X", "p", "P",
      "u", "<C-r>", ".", "~",
      "dd", "yy", "yw", "dw", "cw",
    }
    for _, key in ipairs(block) do
      if not action_keys[key] then
        vim.keymap.set("n", key, noop, { buffer = buf, noremap = true, silent = true, nowait = true })
      end
    end

    -- WinEnter: sync state.col_idx with which window got focus
    vim.api.nvim_create_autocmd("WinEnter", {
      buffer   = buf,
      callback = function()
        if M._state.col_idx ~= i then
          local prev_col = M._state.col_idx
          M._state.col_idx = i
          board_view.refresh_column(board(), prev_col, M._state)
          board_view.refresh_column(board(), i, M._state)
        end
      end,
    })


    -- Block <leader>+navigation combos that would trigger global window-jump keymaps
    -- and cause the focus trap to close the board.
    local leader = vim.g.mapleader or "\\"
    for _, suffix in ipairs({ "h", "j", "k", "l", "H", "J", "K", "L",
                              "w", "W", "p", "P", "v", "c", "r", "n", "b" }) do
      vim.keymap.set("n", leader .. suffix, noop,
        { buffer = buf, noremap = true, silent = true, nowait = true })
    end

    -- Intercept :q so it closes the whole board instead of one column window
    vim.keymap.set("n", "ZZ", actions.close, { buffer = buf, noremap = true, silent = true, nowait = true })
    vim.keymap.set("n", "ZQ", actions.close, { buffer = buf, noremap = true, silent = true, nowait = true })

    -- When :q closes one column window, close the entire board
    local col_win_entry = board_view.col_entry(i)
    if col_win_entry then
      vim.api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(col_win_entry.win),
        once     = true,
        callback = function()
          if board_view.is_open() then
            vim.schedule(actions.close)
          end
        end,
      })
    end

    ::continue::
  end
end

-- ── Entry points ─────────────────────────────────────────────────────────────

--- Open the kanban board for the given file.
---@param filepath string|nil Path to board file (default: .kanban/board.md in cwd)
---@param opts table|nil { format = "markdown"|"org" }
function M.open(filepath, opts)
  opts = opts or {}
  M._open_gen = M._open_gen + 1

  -- Check if already open
  if board_view.is_open() then
    board_view.focus_column(M._state.col_idx)
    return
  end

  -- Load board
  filepath = vim.fn.expand(filepath or (vim.fn.getcwd() .. "/.kanban/board.md")) --[[@as string]]
  M._filepath = filepath

  -- Ensure parent directory exists
  util.ensure_dir(vim.fn.fnamemodify(filepath, ":h"))

  -- If file doesn't exist, offer to create it
  if not util.file_exists(filepath) then
    local answer = vim.fn.confirm(
      "Board file not found: " .. filepath .. "\nCreate it?",
      "&Yes\n&No", 1
    )
    if answer ~= 1 then return end
  end

  -- Ensure we're in normal mode (input_float uses startinsert)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  board_mod.load(filepath, opts.format)

  -- Reset state
  M._state = { col_idx = 1, card_idx = 1 }
  clamp_state()
  M._keymaps_attached = {}

  board_view.open(board(), M._state)
  M._attach_keymaps()

  -- Close the board if focus moves to any non-board, non-float window
  local my_gen = M._open_gen
  M._trap_augroup = vim.api.nvim_create_augroup("KanbanFocusTrap", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = M._trap_augroup,
    callback = function()
      if M._trap_suspended then return end
      if not board_view.is_open() then return end
      local cur = vim.api.nvim_get_current_win()
      if not vim.api.nvim_win_is_valid(cur) then return end
      -- Allow floats
      local win_cfg = vim.api.nvim_win_get_config(cur)
      if win_cfg.relative and win_cfg.relative ~= "" then return end
      -- Allow board columns
      for j = 1, board_mod.column_count() do
        local col_entry = board_view.col_entry(j)
        if col_entry and col_entry.win == cur then return end
      end
      -- Non-board window entered — close the board cleanly
      -- Use generation to avoid closing a newly reopened board
      local gen = my_gen
      vim.schedule(function()
        if M._open_gen == gen then actions.close() end
      end)
    end,
  })

  -- Auto-save on board close (safety net)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once     = true,
    callback = function()
      if board_mod.is_modified() then board_mod.save() end
    end,
  })
end

--- Close the board.
function M.close()
  actions.close()
end

--- Toggle the board open or closed.
---@param filepath string|nil Path to board file
---@param opts table|nil { format = "markdown"|"org" }
function M.toggle(filepath, opts)
  if board_view.is_open() then
    M.close()
  else
    M.open(filepath, opts)
  end
end

return M
