-- Renders the kanban board as a set of side-by-side floating windows.
-- Each column gets its own buffer so highlights stay isolated.
local win_util   = require("kanban.ui.window")
local util       = require("kanban.util")
local M = {}

-- State
M._wins    = {}   -- { win, buf } per column, indexed by column number
M._seps    = {}   -- separator windows between columns
M._bg_win  = nil  -- outer border background window
M._bg_buf  = nil
M._state   = nil  -- { col_idx, card_idx }
M._ns      = nil
M._saved_cursorline = {}  -- { win_id -> bool } saved cursorline state per window

-- ── Rendering helpers ────────────────────────────────────────────────────────

-- Return the plugin config table.
local function config()
  return require("kanban").config
end

-- Build the display lines and highlight specs for one column.
local function build_column_lines(col, focused_card_idx, cfg, column_width)
  local icons    = cfg.icons
  local lines    = {}
  local hl_specs = {}   -- { row, col_start, col_end, group }

  -- Column header
  local count_str = " (" .. #col.cards .. ")"
  local header = util.safe_truncate(col.name, column_width - #count_str - 2)
  local header_line = " " .. icons.column .. header
  lines[1] = header_line .. string.rep(" ", column_width - vim.fn.strdisplaywidth(header_line) - #count_str) .. count_str

  hl_specs[#hl_specs + 1] = { 0, 0, -1, "KanbanColumnHeader" }

  -- Separator
  lines[2] = string.rep("─", column_width)
  hl_specs[#hl_specs + 1] = { 1, 0, -1, "KanbanColumnBorder" }

  -- Cards
  for card_index, card in ipairs(col.cards) do
    local row = #lines  -- 0-based

    local icon
    if card.done then
      icon = icons.card_done
    else
      icon = icons.card
    end

    -- Title line
    local prefix    = " " .. icon
    local prefix_w  = vim.fn.strdisplaywidth(prefix)
    local avail     = column_width - prefix_w - 1
    local title_str = util.safe_truncate(card.title, avail)
    local title_line = prefix .. title_str

    lines[#lines + 1] = util.pad_right(title_line, column_width)

    local title_hl = card.done and "KanbanCardDone" or "KanbanCard"
    if card_index == focused_card_idx then title_hl = "KanbanCardSelected" end

    hl_specs[#hl_specs + 1] = { row, 0, -1, title_hl }

    -- Compute a shared indent so all meta icons align to the same column.
    -- Find the widest icon among the ones that will appear, then pad to that.
    local meta_icon_w = 0
    do
      local candidates = {}
      if card.due_date and card.due_date ~= "" then
        candidates[#candidates + 1] = icons.overdue  -- widest due variant
        candidates[#candidates + 1] = icons.due
      end
      if #(card.tags or {}) > 0 then candidates[#candidates + 1] = icons.tag end
      if card.note_file            then candidates[#candidates + 1] = icons.note end
      for _, ic in ipairs(candidates) do
        local w = vim.fn.strdisplaywidth(ic)
        if w > meta_icon_w then meta_icon_w = w end
      end
    end
    -- Meta lines: 1-space indent, then the meta icon
    local meta_indent = " "

    -- Append one metadata line with its own icon and highlight group.
    local function meta_line_hl(buffer_row, meta_icon, text, highlight_group)
      local icon_w   = vim.fn.strdisplaywidth(meta_icon)
      local icon_pad = string.rep(" ", meta_icon_w - icon_w)
      local line     = meta_indent .. meta_icon .. icon_pad .. text
      lines[#lines + 1] = util.pad_right(line, column_width)
      -- Use byte offsets for highlights (icons are multibyte UTF-8)
      local icon_byte_start = #meta_indent
      local icon_byte_end   = icon_byte_start + #meta_icon + #icon_pad
      local text_byte_end   = icon_byte_end + #text
      hl_specs[#hl_specs + 1] = { buffer_row, icon_byte_start, icon_byte_end, highlight_group }
      hl_specs[#hl_specs + 1] = { buffer_row, icon_byte_end, text_byte_end, highlight_group }
      if card_index == focused_card_idx then
        hl_specs[#hl_specs + 1] = { buffer_row, 0, -1, "KanbanCardSelected" }
      end
    end

    -- Due date on its own line
    if card.due_date and card.due_date ~= "" then
      local due_icon, due_hl
      if util.is_overdue(card.due_date) and not card.done then
        due_icon, due_hl = icons.overdue, "KanbanOverdue"
      elseif util.is_today(card.due_date) then
        due_icon, due_hl = icons.due, "KanbanDueToday"
      else
        due_icon, due_hl = icons.due, "KanbanDueDate"
      end
      local due_text = card.due_date
      if util.is_overdue(card.due_date) and not card.done then
        due_text = due_text .. " (past due)"
      end
      meta_line_hl(#lines, due_icon, due_text, due_hl)
    end

    -- Tags on their own line
    if #(card.tags or {}) > 0 then
      local tag_row  = #lines
      local icon_w   = vim.fn.strdisplaywidth(icons.tag)
      local icon_pad = string.rep(" ", meta_icon_w - icon_w)
      local tag_line = meta_indent .. icons.tag .. icon_pad
      -- byte offset where tag text starts
      local tag_text_byte = #meta_indent + #icons.tag + #icon_pad
      local pos      = tag_text_byte
      local specs    = {}
      for _, tag in ipairs(card.tags) do
        local part   = tag .. " "
        local part_w = vim.fn.strdisplaywidth(part)
        if pos + part_w > column_width - 1 then break end
        specs[#specs + 1] = { tag_row, pos, pos + #tag, "KanbanTag" }
        tag_line = tag_line .. part
        pos = pos + #part
      end
      lines[#lines + 1] = util.pad_right(tag_line, column_width)
      hl_specs[#hl_specs + 1] = { tag_row, #meta_indent, tag_text_byte, "KanbanTag" }
      for _, spec in ipairs(specs) do hl_specs[#hl_specs + 1] = spec end
      if card_index == focused_card_idx then
        hl_specs[#hl_specs + 1] = { tag_row, 0, -1, "KanbanCardSelected" }
      end
    end

    -- Note indicator on its own line
    if card.note_file then
      meta_line_hl(#lines, icons.note, "note", "KanbanNote")
    end

    -- Spacer between cards
    lines[#lines + 1] = ""
  end

  -- Empty column hint
  if #col.cards == 0 then
    lines[#lines + 1] = ""
    local empty_str = "  (empty)"
    lines[#lines + 1] = util.pad_right(empty_str, column_width)
    hl_specs[#hl_specs + 1] = { #lines - 1, 0, -1, "KanbanHint" }
    lines[#lines + 1] = ""
  end

  return lines, hl_specs
end

-- ── Highlight helpers ────────────────────────────────────────────────────────

-- Apply highlight specs to a buffer, clearing any previous namespace highlights.
local function apply_highlights(buf, ns, hl_specs)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, spec in ipairs(hl_specs) do
    local row, cs, ce, grp = spec[1], spec[2], spec[3], spec[4]
    vim.api.nvim_buf_add_highlight(buf, ns, grp, row, cs, ce)
  end
end

-- ── Column window layout ─────────────────────────────────────────────────────

-- Compute column window geometry given the number of columns.
local function column_geometry(num_columns, cfg)
  local terminal_width  = vim.o.columns
  local terminal_height = vim.o.lines
  local gap = cfg.column_gap or 1

  -- Board width: fraction of terminal (1.0 = full width)
  local board_w = math.floor(terminal_width * (cfg.width or 0.92))

  -- Inner width available to columns (board_w minus 2 border chars)
  local inner_w   = board_w - 2
  local column_w  = math.floor((inner_w - (num_columns - 1) * gap) / num_columns)
  column_w = math.max(column_w, cfg.column_width or 28)

  -- Clamp: total inner + 2 border chars must not exceed terminal width
  local total_w = num_columns * column_w + (num_columns - 1) * gap
  if total_w + 2 > terminal_width then
    column_w  = math.floor((terminal_width - 2 - (num_columns - 1) * gap) / num_columns)
    total_w   = num_columns * column_w + (num_columns - 1) * gap
  end

  local board_h   = math.floor(terminal_height * (cfg.height or 0.85))
  local start_col = math.floor((terminal_width  - (total_w + 2)) / 2)
  local start_row = math.floor((terminal_height - board_h) / 2)

  return {
    col_w     = column_w,
    board_h   = board_h,
    start_col = start_col,
    start_row = start_row,
    total_w   = total_w,
    gap       = gap,
  }
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- Return the 0-based buffer row index of the given card in a column's buffer.
local function card_row(col, card_idx)
  local row = 2  -- after header + separator
  for i, card in ipairs(col.cards) do
    if i == card_idx then return row end
    -- title + one line each for due/tags/note + spacer
    local lines = 1
    if card.due_date and card.due_date ~= "" then lines = lines + 1 end
    if #(card.tags or {}) > 0 then lines = lines + 1 end
    if card.note_file then lines = lines + 1 end
    row = row + lines + 1  -- +1 for spacer
  end
  return row
end

--- Open the board view, creating one floating window per column.
---@param board table Board table
---@param state table Cursor state { col_idx, card_idx }
---@param opts table|nil Reserved for future use
---@return table Array of { win, buf } entries indexed by column number
function M.open(board, state, opts)
  opts  = opts or {}
  local cfg = config()
  M._ns  = M._ns or vim.api.nvim_create_namespace("kanban_board")
  M._state = state

  local cols       = board.columns
  local num_columns = #cols
  if num_columns == 0 then
    vim.notify("[kanban] Board has no columns.", vim.log.levels.WARN)
    return {}
  end

  local geo = column_geometry(num_columns, cfg)

  -- Close existing board windows first
  M.close()

  -- Disable cursorline on all remaining editor windows, save for restore
  M._saved_cursorline = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      M._saved_cursorline[win] = vim.wo[win].cursorline
      vim.wo[win].cursorline = false
    end
  end

  -- Background window: provides the outer border around all columns
  M._bg_buf = win_util.scratch_buf()
  M._bg_win = vim.api.nvim_open_win(M._bg_buf, false, {
    relative = "editor",
    width    = geo.total_w + 2,
    height   = geo.board_h,
    row      = geo.start_row,
    col      = geo.start_col,
    anchor   = "NW",
    style    = "minimal",
    border   = cfg.ui and cfg.ui.border or "rounded",
    zindex   = 48,
  })
  vim.wo[M._bg_win].winhighlight = "Normal:KanbanNormal,FloatBorder:KanbanBorder"

  M._wins = {}
  M._seps = {}

  for i, col in ipairs(cols) do
    local buf = win_util.scratch_buf()

    -- +1 row/col to sit inside the background border, -2 height for top+bottom border
    local win_col    = geo.start_col + 1 + (i - 1) * (geo.col_w + geo.gap)
    local is_focused = (i == state.col_idx)
    local focused_card = is_focused and state.card_idx or nil

    local lines, hl_specs = build_column_lines(col, focused_card, cfg, geo.col_w)
    win_util.set_lines(buf, lines)

    local win = vim.api.nvim_open_win(buf, i == state.col_idx, {
      relative  = "editor",
      width     = geo.col_w,
      height    = geo.board_h - 2,
      row       = geo.start_row + 1,
      col       = win_col,
      anchor    = "NW",
      style     = "minimal",
      border    = "none",
      zindex    = 50,
    })

    vim.wo[win].winhighlight =
      "Normal:KanbanNormal,CursorLine:KanbanCursorLine"
    vim.wo[win].wrap       = false
    vim.wo[win].number     = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].cursorline = false
    vim.wo[win].scrolloff  = 3

    apply_highlights(buf, M._ns, hl_specs)

    -- Move cursor to focused card and reset scroll position
    local function set_view(lnum, topline)
      pcall(vim.api.nvim_win_set_cursor, win, { lnum, 0 })
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview({ topline = topline, lnum = lnum, col = 0 })
        end)
      end
    end

    if is_focused and state.card_idx and state.card_idx > 0 then
      local target_row = card_row(col, state.card_idx)
      local lnum = target_row + 1
      local win_h = vim.api.nvim_win_get_height(win)
      local topline = math.max(1, lnum - math.floor(win_h / 2))
      set_view(lnum, topline)
    else
      set_view(3, 1)
    end

    -- Draw a vertical separator to the right of every column except the last
    if i < num_columns and geo.gap > 0 then
      local sep_buf   = win_util.scratch_buf()
      local sep_lines = {}
      for _ = 1, geo.board_h - 2 do sep_lines[#sep_lines + 1] = "│" end
      win_util.set_lines(sep_buf, sep_lines)
      local sep_win = vim.api.nvim_open_win(sep_buf, false, {
        relative = "editor",
        width    = 1,
        height   = geo.board_h - 2,
        row      = geo.start_row + 1,
        col      = win_col + geo.col_w,
        anchor   = "NW",
        style    = "minimal",
        border   = "none",
        zindex   = 49,
      })
      vim.wo[sep_win].winhighlight = "Normal:KanbanBorder"
      M._seps[#M._seps + 1] = { win = sep_win, buf = sep_buf }
    end

    M._wins[i] = { win = win, buf = buf }
  end

  return M._wins
end

--- Re-render a single column in place (faster than a full re-open).
---@param board table Board table
---@param col_idx number 1-based column index
---@param state table Cursor state { col_idx, card_idx }
function M.refresh_column(board, col_idx, state)
  local entry = M._wins[col_idx]
  if not entry then return end
  if not vim.api.nvim_buf_is_valid(entry.buf) then return end
  if not vim.api.nvim_win_is_valid(entry.win) then return end
  local cfg = config()

  local col       = board.columns[col_idx]
  local focused   = (col_idx == state.col_idx) and state.card_idx or nil
  local actual_w  = vim.api.nvim_win_get_width(entry.win)
  local lines, hl_specs = build_column_lines(col, focused, cfg, actual_w)

  win_util.set_lines(entry.buf, lines)
  apply_highlights(entry.buf, M._ns, hl_specs)

  vim.wo[entry.win].winhighlight = "Normal:KanbanNormal,CursorLine:KanbanCursorLine"

  pcall(vim.api.nvim_win_call, entry.win, function()
    if col_idx == state.col_idx and state.card_idx and state.card_idx > 0 then
      local target_row = card_row(col, state.card_idx)
      local lnum = target_row + 1
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      local win_h   = vim.api.nvim_win_get_height(0)
      local topline = math.max(1, lnum - math.floor(win_h / 2))
      vim.fn.winrestview({ topline = topline, lnum = lnum, col = 0 })
    else
      -- Always reset non-focused columns (and empty focused columns) to top
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.fn.winrestview({ topline = 1, lnum = 1, col = 0 })
    end
  end)
end

--- Re-render all columns; does a full re-open when the column count changed.
---@param board table Board table
---@param state table Cursor state { col_idx, card_idx }
function M.refresh_all(board, state)
  -- If column count changed, do a full re-open
  if #M._wins ~= #board.columns then
    M.open(board, state)
    return
  end
  for i = 1, #board.columns do
    M.refresh_column(board, i, state)
  end
  -- Focus the right window
  local entry = M._wins[state.col_idx]
  if entry and vim.api.nvim_win_is_valid(entry.win) then
    vim.api.nvim_set_current_win(entry.win)
  end
end

--- Return the window and buffer handles for the currently focused column.
---@return number|nil, number|nil Window handle and buffer handle, or nil, nil
function M.current_win_buf()
  local state = M._state
  if not state then return nil, nil end
  local entry = M._wins[state.col_idx]
  if not entry then return nil, nil end
  return entry.win, entry.buf
end

--- Move Neovim focus to the window for the given column.
---@param col_idx number 1-based column index
function M.focus_column(col_idx)
  local entry = M._wins[col_idx]
  if entry and vim.api.nvim_win_is_valid(entry.win) then
    vim.api.nvim_set_current_win(entry.win)
  end
end

--- Close all board windows and restore any saved window options.
function M.close()
  for _, entry in ipairs(M._wins or {}) do
    if entry.win and vim.api.nvim_win_is_valid(entry.win) then
      pcall(vim.api.nvim_win_close, entry.win, true)
    end
    if entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
      pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
    end
  end
  M._wins = {}
  for _, sep in ipairs(M._seps or {}) do
    if sep.win and vim.api.nvim_win_is_valid(sep.win) then
      pcall(vim.api.nvim_win_close, sep.win, true)
    end
    if sep.buf and vim.api.nvim_buf_is_valid(sep.buf) then
      pcall(vim.api.nvim_buf_delete, sep.buf, { force = true })
    end
  end
  M._seps = {}
  if M._bg_win and vim.api.nvim_win_is_valid(M._bg_win) then
    pcall(vim.api.nvim_win_close, M._bg_win, true)
  end
  M._bg_win = nil
  M._bg_buf = nil

  -- Restore cursorline on remaining windows
  for win, saved in pairs(M._saved_cursorline or {}) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].cursorline = saved
    end
  end
  M._saved_cursorline = {}
end

--- Return true if the board is currently displayed on screen.
---@return boolean
function M.is_open()
  if not M._wins or #M._wins == 0 then return false end
  local first = M._wins[1]
  return first and first.win and vim.api.nvim_win_is_valid(first.win)
end

--- Return the { win, buf } entry for a column (used for keymap attachment).
---@param col_idx number 1-based column index
---@return table|nil Entry table or nil
function M.col_entry(col_idx)
  return M._wins[col_idx]
end

return M
