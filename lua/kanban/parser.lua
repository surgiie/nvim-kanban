-- Reads and writes plain markdown boards:
--
--   ## Column Name
--
--   - [ ] Card title #tag @due(2025-01-15) @note(path/to/note.md)
--     indented lines belong to the card above
--   - [x] Done card
--
-- Content the board does not model survives a save: frontmatter, text before
-- the first column (board.preamble), text between a heading and its first card
-- (col.preamble), indented lines under a card (card._body), and other text
-- after a column's cards (col.trailer). Cards whose fields did not change are
-- written back with their original line. Blank lines between sections are
-- normalized to one.
local util = require("kanban.util")
local M = {}

local function is_blank(line)
  return line:match("^%s*$") ~= nil
end

local function trim_blank_edges(lines)
  while #lines > 0 and is_blank(lines[#lines]) do table.remove(lines) end
  while #lines > 0 and is_blank(lines[1]) do table.remove(lines, 1) end
end

local function new_column(name)
  return { name = name, cards = {}, preamble = {}, trailer = {} }
end

local function split_frontmatter(content)
  if not content:match("^%-%-%-[ \t]*\r?\n") then return nil, content end
  local _, closing_end = content:find("\n%-%-%-[ \t]*\r?\n", 4)
  if not closing_end then return nil, content end
  return content:sub(1, closing_end - 1), content:sub(closing_end + 1)
end

--- Remove `#tag` tokens from text and return the remaining title and the tags.
---@param text string
---@return string, string[]
function M.split_tags(text)
  local tags = {}
  local title = text:gsub("#([%w_%-]+)", function(tag)
    tags[#tags + 1] = tag
    return ""
  end)
  return util.trim(title), tags
end

local function parse_card_line(line)
  local check, text = line:match("^%-%s+%[([%sx])%]%s+(.*)")
  if not check then text = line:match("^%-%s+(.*)") end

  local due_date, note_file
  text = text:gsub("@due%((%d%d%d%d%-%d%d%-%d%d)%)", function(date) due_date = date; return "" end)
  text = text:gsub("@note%(([^%)]+)%)", function(path) note_file = path; return "" end)
  local title, tags = M.split_tags(text)

  return { title = title, done = check == "x", tags = tags, due_date = due_date, note_file = note_file }
end

local function serialize_card(card)
  local parts = { "- [" .. (card.done and "x" or " ") .. "] " .. card.title }
  if card.due_date then parts[#parts + 1] = "@due(" .. card.due_date .. ")" end
  if card.note_file then parts[#parts + 1] = "@note(" .. card.note_file .. ")" end
  for _, tag in ipairs(card.tags or {}) do parts[#parts + 1] = "#" .. tag end
  return table.concat(parts, " ")
end

local function card_line(card)
  local canonical = serialize_card(card)
  if card._raw_line and canonical == card._parsed_line then return card._raw_line end
  return canonical
end

local function parse_body(body)
  local preamble, columns = {}, {}
  local current_col, last_card
  -- Blank lines after a card are only part of its body if more indented lines follow
  local pending_blanks = 0

  for _, line in ipairs(util.split_lines(body)) do
    local col_name = line:match("^##%s+(.*)")
    col_name = col_name and util.trim(col_name)
    local card
    if not col_name and current_col and line:match("^%-%s+") then
      card = parse_card_line(line)
      if card.title == "" then card = nil end
    end

    if col_name and col_name ~= "" then
      current_col = new_column(col_name)
      columns[#columns + 1] = current_col
      last_card, pending_blanks = nil, 0
    elseif not current_col then
      preamble[#preamble + 1] = line
    elseif card then
      card.id           = util.new_id()
      card._raw_line    = line
      card._parsed_line = serialize_card(card)
      current_col.cards[#current_col.cards + 1] = card
      last_card, pending_blanks = card, 0
    elseif last_card and #current_col.trailer == 0 and is_blank(line) then
      pending_blanks = pending_blanks + 1
    elseif last_card and #current_col.trailer == 0 and line:match("^%s") then
      last_card._body = last_card._body or {}
      for _ = 1, pending_blanks do last_card._body[#last_card._body + 1] = "" end
      last_card._body[#last_card._body + 1] = line
      pending_blanks = 0
    elseif #current_col.cards == 0 then
      current_col.preamble[#current_col.preamble + 1] = line
    else
      current_col.trailer[#current_col.trailer + 1] = line
    end
  end

  trim_blank_edges(preamble)
  for _, col in ipairs(columns) do
    trim_blank_edges(col.preamble)
    trim_blank_edges(col.trailer)
  end
  if #columns == 0 then
    columns = { new_column("To Do"), new_column("In Progress"), new_column("Done") }
  end
  return preamble, columns
end

---@param content string
---@return table
function M.parse(content)
  local frontmatter, body = split_frontmatter(content)
  local preamble, columns = parse_body(body)
  return { frontmatter = frontmatter, preamble = preamble, columns = columns }
end

--- A missing file parses as an empty board with default columns.
---@param filepath string
---@return table
function M.parse_file(filepath)
  return M.parse(util.read_file(filepath) or "")
end

local function append_section(lines, section)
  if #section == 0 then return end
  if #lines > 0 then lines[#lines + 1] = "" end
  vim.list_extend(lines, section)
end

---@param board table
---@return string
function M.serialize(board)
  local lines = {}
  if board.frontmatter then append_section(lines, util.split_lines(board.frontmatter)) end
  append_section(lines, board.preamble or {})

  for _, col in ipairs(board.columns) do
    append_section(lines, { "## " .. col.name })
    append_section(lines, col.preamble or {})
    local card_lines = {}
    for _, card in ipairs(col.cards) do
      card_lines[#card_lines + 1] = card_line(card)
      vim.list_extend(card_lines, card._body or {})
    end
    append_section(lines, card_lines)
    append_section(lines, col.trailer or {})
  end

  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

---@param board table
---@param filepath string
---@return boolean
function M.serialize_file(board, filepath)
  return util.write_file(filepath, M.serialize(board))
end

return M
