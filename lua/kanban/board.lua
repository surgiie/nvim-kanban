-- The loaded board and the operations on it. All mutations mark it modified;
-- callers decide when to save.
local util   = require("kanban.util")
local parser = require("kanban.parser")
local M = {}

M._board    = nil
M._filepath = nil
M._modified = false

---@param filepath string
---@return table
function M.load(filepath)
  M._board    = parser.parse_file(filepath)
  M._filepath = filepath
  M._modified = false
  return M._board
end

---@param filepath string
---@return boolean
function M.is_loaded(filepath)
  return M._board ~= nil and M._filepath == filepath
end

---@return boolean
function M.save()
  if not M._board or not M._filepath then return false end
  local saved = parser.serialize_file(M._board, M._filepath)
  if saved then M._modified = false end
  return saved
end

---@return table|nil
function M.get()
  return M._board
end

---@return boolean
function M.is_modified()
  return M._modified
end

function M.mark_modified()
  M._modified = true
end

-- ── Columns ──────────────────────────────────────────────────────────────────

---@param col_idx integer
---@return table|nil
function M.get_column(col_idx)
  return M._board and M._board.columns[col_idx]
end

---@return integer
function M.column_count()
  return M._board and #M._board.columns or 0
end

--- Append a column and return its index.
---@param name string
---@return integer
function M.add_column(name)
  table.insert(M._board.columns, { name = name, cards = {} })
  M._modified = true
  return #M._board.columns
end

---@param col_idx integer
---@param new_name string
function M.rename_column(col_idx, new_name)
  local col = M.get_column(col_idx)
  if not col then return end
  col.name = new_name
  M._modified = true
end

--- Swap a column with its neighbour and return its new index.
---@param col_idx integer
---@param direction integer -1 or 1
---@return integer
function M.move_column(col_idx, direction)
  local columns = M._board.columns
  local new_idx = col_idx + direction
  if new_idx < 1 or new_idx > #columns then return col_idx end
  columns[col_idx], columns[new_idx] = columns[new_idx], columns[col_idx]
  M._modified = true
  return new_idx
end

--- Delete a column and its cards; the last remaining column cannot be deleted.
---@param col_idx integer
---@return boolean
function M.delete_column(col_idx)
  if M.column_count() <= 1 then return false end
  table.remove(M._board.columns, col_idx)
  M._modified = true
  return true
end

-- ── Cards ────────────────────────────────────────────────────────────────────

---@param col_idx integer
---@param card_idx integer
---@return table|nil
function M.get_card(col_idx, card_idx)
  local col = M.get_column(col_idx)
  return col and col.cards[card_idx]
end

--- Append a card to a column and return it with its position.
---@param col_idx integer
---@param title string
---@param tags string[]
---@return table|nil, integer|nil
function M.add_card(col_idx, title, tags)
  local col = M.get_column(col_idx)
  if not col then return nil end
  local card = { id = util.new_id(), title = title, done = false, tags = tags or {} }
  table.insert(col.cards, card)
  M._modified = true
  return card, #col.cards
end

---@param col_idx integer
---@param card_idx integer
---@param fields table Merged into the card; use detach_note to clear note_file
function M.update_card(col_idx, card_idx, fields)
  local card = M.get_card(col_idx, card_idx)
  if not card then return end
  for key, value in pairs(fields) do card[key] = value end
  M._modified = true
end

--- Remove a card and delete its note file.
---@param col_idx integer
---@param card_idx integer
function M.delete_card(col_idx, card_idx)
  local col = M.get_column(col_idx)
  if not col or not col.cards[card_idx] then return end
  M.detach_note(table.remove(col.cards, card_idx))
  M._modified = true
end

--- Move a card and return its new position, or nil if either index is invalid.
---@param from_col integer
---@param from_card integer
---@param to_col integer
---@param to_pos integer|nil Defaults to the end of the destination column
---@return integer|nil
function M.move_card(from_col, from_card, to_col, to_pos)
  local source = M.get_column(from_col)
  local target = M.get_column(to_col)
  if not source or not target or not source.cards[from_card] then return nil end
  local card = table.remove(source.cards, from_card)
  to_pos = math.max(1, math.min(to_pos or (#target.cards + 1), #target.cards + 1))
  table.insert(target.cards, to_pos, card)
  M._modified = true
  return to_pos
end

---@param col_idx integer
---@param card_idx integer
---@param date string|nil YYYY-MM-DD, or nil to clear
function M.set_due_date(col_idx, card_idx, date)
  local card = M.get_card(col_idx, card_idx)
  if not card then return end
  card.due_date = date
  M._modified = true
end

---@param col_idx integer
---@param card_idx integer
function M.toggle_done(col_idx, card_idx)
  local card = M.get_card(col_idx, card_idx)
  if not card then return end
  card.done = not card.done
  M._modified = true
end

--- Move a card to the archive column, creating the column if needed.
---@param col_idx integer
---@param card_idx integer
---@return boolean
function M.archive_card(col_idx, card_idx)
  local archive_name = require("kanban").config.archive_column
  local archive_idx
  for i, col in ipairs(M._board.columns) do
    if col.name == archive_name then archive_idx = i; break end
  end
  return M.move_card(col_idx, card_idx, archive_idx or M.add_column(archive_name)) ~= nil
end

--- Case-insensitive plain-text search over card titles and tags.
---@param query string
---@return { col_idx: integer, card_idx: integer, col_name: string, card: table }[]
function M.search(query)
  if not M._board or query == "" then return {} end
  query = query:lower()
  local results = {}
  for col_idx, col in ipairs(M._board.columns) do
    for card_idx, card in ipairs(col.cards) do
      local haystack = (card.title .. " " .. table.concat(card.tags, " ")):lower()
      if haystack:find(query, 1, true) then
        results[#results + 1] = { col_idx = col_idx, card_idx = card_idx, col_name = col.name, card = card }
      end
    end
  end
  return results
end

-- ── Notes ────────────────────────────────────────────────────────────────────

--- The card's note path, or a new one in the notes directory. Creates the
--- parent directory but not the file.
---@param card table
---@return string
function M.note_path(card)
  local path = card.note_file
  if not path then
    local config    = require("kanban").config
    local notes_dir = config.notes_dir and vim.fn.expand(config.notes_dir)
      or (vim.fn.fnamemodify(M._filepath, ":h") .. "/notes")
    path = notes_dir .. "/" .. util.slug(card.title):sub(1, 40) .. "-" .. card.id .. ".md"
  end
  util.ensure_dir(vim.fn.fnamemodify(path, ":h"))
  return path
end

--- Delete the card's note file, if any, and unlink it from the card.
---@param card table
function M.detach_note(card)
  if not card.note_file then return end
  os.remove(card.note_file)
  card.note_file = nil
  M._modified = true
end

return M
