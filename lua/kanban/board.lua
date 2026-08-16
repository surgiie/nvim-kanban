-- Board state and operations. Sits between parsers and the UI.
local util = require("kanban.util")
local M = {}

-- Active board instance
M._board    = nil
M._filepath = nil
M._format   = nil
M._modified = false

-- Return the appropriate parser module for the given format string.
local function get_parser(format)
  if format == "org" then
    return require("kanban.parser.org")
  end
  return require("kanban.parser.markdown")
end

--- Load a board from a file and replace the active board state.
---@param filepath string Path to the board file
---@param format string|nil "markdown" or "org" (auto-detected when nil)
---@return table Parsed board table
function M.load(filepath, format)
  local config = require("kanban").config
  format = format or config.format or require("kanban.config").detect_format(filepath)

  local parser = get_parser(format)
  local board  = parser.parse_file(filepath)

  -- Assign stable IDs to cards that don't have one
  for _, col in ipairs(board.columns) do
    for _, card in ipairs(col.cards) do
      if not card.id then card.id = util.uuid() end
    end
  end

  M._board    = board
  M._filepath = filepath
  M._format   = format
  M._modified = false
  return board
end

--- Serialize and write the active board back to its source file.
---@return boolean True on success
function M.save()
  if not M._board or not M._filepath then return false end
  local parser = get_parser(M._format)
  local success = parser.serialize_file(M._board, M._filepath)
  if success then M._modified = false end
  return success
end

--- Return the currently loaded board table.
---@return table|nil Board table, or nil if no board is loaded
function M.get()
  return M._board
end

--- Return true if the board has unsaved changes.
---@return boolean True when modified
function M.is_modified()
  return M._modified
end

--- Mark the board as having unsaved changes.
function M.mark_modified()
  M._modified = true
end

-- ── Column operations ────────────────────────────────────────────────────────

--- Return the column table at the given 1-based index.
---@param col_idx number 1-based column index
---@return table|nil Column table, or nil if out of range
function M.get_column(col_idx)
  if not M._board then return nil end
  return M._board.columns[col_idx]
end

--- Return the total number of columns in the active board.
---@return number Column count (0 if no board is loaded)
function M.column_count()
  if not M._board then return 0 end
  return #M._board.columns
end

--- Insert a new empty column after the given index.
---@param name string Column name
---@param after_idx number|nil Insert after this column index (default: last column)
---@return number|nil New column's 1-based index, or nil if no board is loaded
function M.add_column(name, after_idx)
  if not M._board then return nil end
  local col = { name = name, cards = {} }
  after_idx = after_idx or #M._board.columns
  table.insert(M._board.columns, after_idx + 1, col)
  M._modified = true
  return #M._board.columns  -- new column index
end

--- Rename an existing column.
---@param col_idx number 1-based column index
---@param new_name string Replacement name
---@return boolean True on success
function M.rename_column(col_idx, new_name)
  local col = M.get_column(col_idx)
  if not col then return false end
  col.name   = new_name
  M._modified = true
  return true
end

--- Move a column left or right by one position.
---@param col_idx number 1-based column index to move
---@param direction number -1 to move left, 1 to move right
---@return number New 1-based column index, or same if already at the boundary
function M.move_column(col_idx, direction)
  if not M._board then return col_idx end
  local cols = M._board.columns
  local new_idx = col_idx + direction
  if new_idx < 1 or new_idx > #cols then return col_idx end
  cols[col_idx], cols[new_idx] = cols[new_idx], cols[col_idx]
  M._modified = true
  return new_idx
end

--- Delete a column (refuses if it would leave fewer than one column).
---@param col_idx number 1-based column index
---@return boolean True on success
function M.delete_column(col_idx)
  if not M._board then return false end
  if #M._board.columns <= 1 then return false end
  table.remove(M._board.columns, col_idx)
  M._modified = true
  return true
end

-- ── Card operations ──────────────────────────────────────────────────────────

--- Return the card at the given column/card indices.
---@param col_idx number 1-based column index
---@param card_idx number 1-based card index within the column
---@return table|nil Card table, or nil if out of range
function M.get_card(col_idx, card_idx)
  local col = M.get_column(col_idx)
  if not col then return nil end
  return col.cards[card_idx]
end

--- Add a new card to a column.
---@param col_idx number 1-based column index
---@param title string Card title
---@param opts table|nil { tags, due_date, note_file, pos }
---@return table|nil, number|nil New card table and its 1-based position, or nil on failure
function M.add_card(col_idx, title, opts)
  local col = M.get_column(col_idx)
  if not col then return nil end
  opts = opts or {}
  local card = {
    id        = util.uuid(),
    title     = title,
    done      = false,
    tags      = opts.tags or {},
    due_date  = opts.due_date,
    note_file = opts.note_file,
  }
  -- Insert at position (default: end)
  local pos = opts.pos or (#col.cards + 1)
  table.insert(col.cards, pos, card)
  M._modified = true
  return card, pos
end

--- Update fields on an existing card.
---@param col_idx number 1-based column index
---@param card_idx number 1-based card index
---@param fields table Key/value pairs to merge into the card
---@return boolean True on success
function M.update_card(col_idx, card_idx, fields)
  local card = M.get_card(col_idx, card_idx)
  if not card then return false end
  for k, v in pairs(fields) do
    card[k] = v
  end
  M._modified = true
  return true
end

--- Remove a card from a column and return it.
---@param col_idx number 1-based column index
---@param card_idx number 1-based card index
---@return table|nil Removed card, or nil if not found
function M.delete_card(col_idx, card_idx)
  local col = M.get_column(col_idx)
  if not col or not col.cards[card_idx] then return nil end
  local card = table.remove(col.cards, card_idx)
  M._modified = true
  return card
end

--- Move a card from one column to another, optionally at a specific position.
---@param from_col number Source column index
---@param from_card number Source card index
---@param to_col number Destination column index
---@param to_pos number|nil Destination position (default: end of column)
---@return boolean, number|nil True and the card's new position on success, false on failure
function M.move_card(from_col, from_card, to_col, to_pos)
  local src_col = M.get_column(from_col)
  if not src_col or not src_col.cards[from_card] then return false end

  local dst_col = M.get_column(to_col)
  if not dst_col then return false end

  local card = table.remove(src_col.cards, from_card)
  to_pos = to_pos or (#dst_col.cards + 1)
  to_pos = math.max(1, math.min(to_pos, #dst_col.cards + 1))
  table.insert(dst_col.cards, to_pos, card)
  M._modified = true
  return true, to_pos
end

--- Toggle the done state of a card (and update the org keyword if present).
---@param col_idx number 1-based column index
---@param card_idx number 1-based card index
---@return boolean True on success
function M.toggle_done(col_idx, card_idx)
  local card = M.get_card(col_idx, card_idx)
  if not card then return false end
  card.done   = not card.done
  -- Update org keyword if present
  if card.keyword then
    if card.done then
      card.keyword = "DONE"
    else
      card.keyword = "TODO"
    end
  end
  M._modified = true
  return true
end

--- Move a card to the archive column (creating it if necessary).
---@param col_idx number 1-based column index
---@param card_idx number 1-based card index
---@return boolean, number|nil, number|nil Success flag, archive column index, new card position
function M.archive_card(col_idx, card_idx)
  local config = require("kanban").config
  local archive_name = config.archive_column or "Archive"

  -- Find or create archive column
  local archive_idx = nil
  for i, col in ipairs(M._board.columns) do
    if col.name == archive_name then
      archive_idx = i
      break
    end
  end
  if not archive_idx then
    archive_idx = M.add_column(archive_name)
  end

  local success, new_pos = M.move_card(col_idx, card_idx, archive_idx)
  return success, archive_idx, new_pos
end

-- ── Search ───────────────────────────────────────────────────────────────────

--- Search cards by title and tags across all columns.
---@param query string Search string (case-insensitive, plain text)
---@return table List of { col_idx, card_idx, col_name, card } result tables
function M.search(query)
  if not M._board or not query or query == "" then return {} end
  query = query:lower()
  local results = {}

  for card_list_index, col in ipairs(M._board.columns) do
    for card_index, card in ipairs(col.cards) do
      local haystack = (card.title .. " " .. table.concat(card.tags or {}, " ")):lower()
      if haystack:find(query, 1, true) then
        results[#results + 1] = {
          col_idx  = card_list_index,
          card_idx = card_index,
          col_name = col.name,
          card     = card,
        }
      end
    end
  end

  return results
end

-- ── Note files ───────────────────────────────────────────────────────────────

--- Compute the filesystem path for a card's associated note file.
---@param card table Card table
---@return string Absolute path to the note file (parent directory is created)
function M.note_path(card)
  local path
  if card.note_file then
    path = card.note_file
  else
    local config = require("kanban").config
    local notes_dir

    if config.notes_dir then
      notes_dir = vim.fn.expand(config.notes_dir)
    elseif M._filepath then
      notes_dir = vim.fn.fnamemodify(M._filepath, ":h") .. "/notes"
    else
      notes_dir = vim.fn.expand("~/.kanban/notes")
    end

    local slug = util.slug(card.title):sub(1, 40)
    path = notes_dir .. "/" .. slug .. "-" .. (card.id or "note") .. ".md"
  end

  -- Always ensure the parent directory exists before returning
  util.ensure_dir(vim.fn.fnamemodify(path, ":h"))
  return path
end

--- Return the note file path for a card without modifying the card.
--- The caller is responsible for attaching the path once the file actually exists.
---@param card table Card table
---@return string Path to the note file
function M.open_note(card)
  return M.note_path(card)
end

return M
