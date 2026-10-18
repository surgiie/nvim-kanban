-- Renders the board as floating windows: a bordered background, one window
-- per column, and a one-column separator window between columns.
local win_util = require("kanban.ui.window")
local util     = require("kanban.util")
local M = {}

M._wins = {}  -- { win, buf } per column
M._seps = {}  -- { win, buf } per separator
M._bg_win = nil
M._saved_cursorline = {}

local ns = vim.api.nvim_create_namespace("kanban_board")

local function config()
  return require("kanban").config
end

-- Return the column's lines, highlight specs ({ row, start_col, end_col, group },
-- 0-based) and the 1-based line each card starts on.
local function build_column_lines(col, focused_card_idx, column_width)
  local icons = config().icons
  local lines, highlights, card_lines = {}, {}, {}

  local count = " (" .. #col.cards .. ")"
  local header = " " .. icons.column .. util.truncate(col.name, column_width - #count - 2)
  lines[1] = header .. string.rep(" ", column_width - vim.fn.strdisplaywidth(header) - #count) .. count
  lines[2] = string.rep("─", column_width)
  highlights[#highlights + 1] = { 0, 0, -1, "KanbanColumnHeader" }
  highlights[#highlights + 1] = { 1, 0, -1, "KanbanColumnBorder" }

  for card_idx, card in ipairs(col.cards) do
    local focused = card_idx == focused_card_idx
    card_lines[card_idx] = #lines + 1

    local prefix = " " .. (card.done and icons.card_done or icons.card)
    local title_width = column_width - vim.fn.strdisplaywidth(prefix) - 1
    lines[#lines + 1] = util.pad_right(prefix .. util.truncate(card.title, title_width), column_width)
    local title_group = focused and "KanbanCardSelected" or (card.done and "KanbanCardDone" or "KanbanCard")
    highlights[#highlights + 1] = { #lines - 1, 0, -1, title_group }

    -- Pad every metadata icon to the widest one shown so the text lines up
    local icon_width = 0
    local shown_icons = {}
    if card.due_date then vim.list_extend(shown_icons, { icons.due, icons.overdue }) end
    if #card.tags > 0 then shown_icons[#shown_icons + 1] = icons.tag end
    if card.note_file then shown_icons[#shown_icons + 1] = icons.note end
    for _, icon in ipairs(shown_icons) do
      icon_width = math.max(icon_width, vim.fn.strdisplaywidth(icon))
    end
    local function icon_prefix(icon)
      return " " .. icon .. string.rep(" ", icon_width - vim.fn.strdisplaywidth(icon))
    end
    local function add_meta_line(text, segments)
      lines[#lines + 1] = util.pad_right(text, column_width)
      for _, segment in ipairs(segments) do
        highlights[#highlights + 1] = { #lines - 1, segment[1], segment[2], segment[3] }
      end
      if focused then highlights[#highlights + 1] = { #lines - 1, 0, -1, "KanbanCardSelected" } end
    end

    if card.due_date then
      local overdue = util.is_overdue(card.due_date) and not card.done
      local icon  = overdue and icons.overdue or icons.due
      local group = overdue and "KanbanOverdue"
        or (util.is_today(card.due_date) and "KanbanDueToday" or "KanbanDueDate")
      local prefix_text = icon_prefix(icon)
      local text = prefix_text .. card.due_date .. (overdue and " (past due)" or "")
      add_meta_line(text, { { 1, #text, group } })
    end

    if #card.tags > 0 then
      local text = icon_prefix(icons.tag)
      local segments = { { 1, #text, "KanbanTag" } }
      for _, tag in ipairs(card.tags) do
        if vim.fn.strdisplaywidth(text .. tag) > column_width - 1 then break end
        segments[#segments + 1] = { #text, #text + #tag, "KanbanTag" }
        text = text .. tag .. " "
      end
      add_meta_line(text, segments)
    end

    if card.note_file then
      local text = icon_prefix(icons.note) .. "note"
      add_meta_line(text, { { 1, #text, "KanbanNote" } })
    end

    lines[#lines + 1] = ""
  end

  if #col.cards == 0 then
    vim.list_extend(lines, { "", util.pad_right("  (empty)", column_width), "" })
    highlights[#highlights + 1] = { #lines - 2, 0, -1, "KanbanHint" }
  end

  return lines, highlights, card_lines
end

local function apply_highlights(buf, highlights)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, spec in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, spec[4], spec[1], spec[2], spec[3])
  end
end

-- Put the cursor on `lnum` and center it, or reset to the top when nil.
local function scroll_to(win, lnum)
  vim.api.nvim_win_call(win, function()
    if lnum then
      local topline = math.max(1, lnum - math.floor(vim.api.nvim_win_get_height(0) / 2))
      vim.fn.winrestview({ topline = topline, lnum = lnum, col = 0 })
    else
      vim.fn.winrestview({ topline = 1, lnum = 1, col = 0 })
    end
  end)
end

local function render_column(entry, col, col_idx, state)
  local focused_card = col_idx == state.col_idx and state.card_idx or nil
  local lines, highlights, card_lines =
    build_column_lines(col, focused_card, vim.api.nvim_win_get_width(entry.win))
  win_util.set_lines(entry.buf, lines)
  apply_highlights(entry.buf, highlights)
  scroll_to(entry.win, focused_card and card_lines[focused_card])
end

local function geometry(num_columns)
  local cfg = config()
  local gap = cfg.column_gap
  local column_width = math.floor((math.floor(vim.o.columns * cfg.width) - 2 - (num_columns - 1) * gap) / num_columns)
  column_width = math.max(column_width, cfg.column_width)

  -- Never exceed the editor width, even if that means going below column_width
  local total_width = num_columns * column_width + (num_columns - 1) * gap
  if total_width + 2 > vim.o.columns then
    column_width = math.floor((vim.o.columns - 2 - (num_columns - 1) * gap) / num_columns)
    total_width  = num_columns * column_width + (num_columns - 1) * gap
  end

  local height = math.floor(vim.o.lines * cfg.height)
  return {
    column_width = column_width,
    total_width  = total_width,
    height       = height,
    gap          = gap,
    row          = math.floor((vim.o.lines - height) / 2),
    col          = math.floor((vim.o.columns - total_width - 2) / 2),
  }
end

--- Open the board, focusing the column in `state.col_idx`.
---@param board table
---@param state { col_idx: integer, card_idx: integer }
function M.open(board, state)
  M.close()
  local layout = geometry(#board.columns)

  M._saved_cursorline = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    M._saved_cursorline[win] = vim.wo[win].cursorline
    vim.wo[win].cursorline = false
  end

  M._bg_win = vim.api.nvim_open_win(win_util.scratch_buf(), false, {
    relative = "editor",
    width    = layout.total_width + 2,
    height   = layout.height,
    row      = layout.row,
    col      = layout.col,
    style    = "minimal",
    border   = "rounded",
    zindex   = 48,
  })
  vim.wo[M._bg_win].winhighlight = "Normal:KanbanNormal,FloatBorder:KanbanBorder"

  for col_idx, col in ipairs(board.columns) do
    local buf = win_util.scratch_buf()
    local win_col = layout.col + 1 + (col_idx - 1) * (layout.column_width + layout.gap)
    local win = vim.api.nvim_open_win(buf, col_idx == state.col_idx, {
      relative = "editor",
      width    = layout.column_width,
      height   = layout.height - 2,
      row      = layout.row + 1,
      col      = win_col,
      style    = "minimal",
      zindex   = 50,
    })
    vim.wo[win].winhighlight = "Normal:KanbanNormal,CursorLine:KanbanCursorLine"
    vim.wo[win].wrap         = false
    vim.wo[win].cursorline   = false
    vim.wo[win].scrolloff    = 3
    M._wins[col_idx] = { win = win, buf = buf }
    render_column(M._wins[col_idx], col, col_idx, state)

    if col_idx < #board.columns and layout.gap > 0 then
      local sep_buf = win_util.scratch_buf()
      local sep_lines = {}
      for i = 1, layout.height - 2 do sep_lines[i] = "│" end
      win_util.set_lines(sep_buf, sep_lines)
      local sep_win = vim.api.nvim_open_win(sep_buf, false, {
        relative = "editor",
        width    = 1,
        height   = layout.height - 2,
        row      = layout.row + 1,
        col      = win_col + layout.column_width,
        style    = "minimal",
        zindex   = 49,
      })
      vim.wo[sep_win].winhighlight = "Normal:KanbanBorder"
      M._seps[#M._seps + 1] = { win = sep_win, buf = sep_buf }
    end
  end
end

---@param board table
---@param col_idx integer
---@param state { col_idx: integer, card_idx: integer }
function M.refresh_column(board, col_idx, state)
  local entry = M._wins[col_idx]
  if not entry or not vim.api.nvim_win_is_valid(entry.win) then return end
  render_column(entry, board.columns[col_idx], col_idx, state)
end

--- Re-render every column and focus `state.col_idx`; reopens when the column
--- count changed.
---@param board table
---@param state { col_idx: integer, card_idx: integer }
function M.refresh_all(board, state)
  if #M._wins ~= #board.columns then
    M.open(board, state)
    return
  end
  for col_idx = 1, #board.columns do M.refresh_column(board, col_idx, state) end
  M.focus_column(state.col_idx)
end

---@param col_idx integer
function M.focus_column(col_idx)
  local entry = M._wins[col_idx]
  if entry and vim.api.nvim_win_is_valid(entry.win) then
    vim.api.nvim_set_current_win(entry.win)
  end
end

function M.close()
  -- Clear the window lists first so is_open() is already false while the
  -- windows' WinClosed autocmds run
  local windows = vim.list_extend(vim.list_extend({}, M._wins), M._seps)
  M._wins, M._seps = {}, {}
  if M._bg_win then windows[#windows + 1] = { win = M._bg_win } end
  M._bg_win = nil

  for _, entry in ipairs(windows) do
    if vim.api.nvim_win_is_valid(entry.win) then pcall(vim.api.nvim_win_close, entry.win, true) end
  end
  for win, cursorline in pairs(M._saved_cursorline) do
    if vim.api.nvim_win_is_valid(win) then vim.wo[win].cursorline = cursorline end
  end
  M._saved_cursorline = {}
end

---@return boolean
function M.is_open()
  local first = M._wins[1]
  return first ~= nil and vim.api.nvim_win_is_valid(first.win)
end

---@param col_idx integer
---@return { win: integer, buf: integer }|nil
function M.col_entry(col_idx)
  return M._wins[col_idx]
end

return M
