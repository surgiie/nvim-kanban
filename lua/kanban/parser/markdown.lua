-- Parses and serializes Obsidian-style markdown kanban files.
--
-- File format:
--   ---
--   kanban-plugin: basic
--   ---
--
--   ## Column Name
--
--   - [ ] Card title #tag @due(2025-01-15)
--   - [x] Done card
--
local util = require("kanban.util")
local M = {}

-- ── Parse helpers ─────────────────────────────────────────────────────────────

-- Extract frontmatter block and body from raw file content.
local function split_frontmatter(content)
  if content:sub(1, 3) ~= "---" then
    return nil, content
  end
  local frontmatter_end = content:find("\n---", 4)
  if not frontmatter_end then
    return nil, content
  end
  local frontmatter = content:sub(1, frontmatter_end + 3)
  local body        = content:sub(frontmatter_end + 4)
  return frontmatter, body
end

-- Parse inline metadata from a card line.
-- Returns: { title, tags, due_date, done, checkboxes }
local function parse_card_line(line)
  local done   = false
  local text   = line

  -- Strip leading list marker: "- [ ] " or "- [x] " or "- "
  local check, rest = text:match("^%-%s+%[([%sx])%]%s+(.*)")
  if check then
    done = (check == "x")
    text = rest
  else
    local plain = text:match("^%-%s+(.*)")
    if plain then text = plain end
  end

  -- Extract tags (#word)
  local tags = {}
  text = text:gsub("#([%w_%-]+)", function(tag)
    tags[#tags + 1] = tag
    return ""
  end)

  -- Extract due date: @due(YYYY-MM-DD)
  local due_date = nil
  text = text:gsub("@due%((%d%d%d%d%-%d%d%-%d%d)%)", function(d)
    due_date = d
    return ""
  end)

  -- Extract note reference: @note(path)
  local note_file = nil
  text = text:gsub("@note%(([^%)]+)%)", function(p)
    note_file = p
    return ""
  end)

  -- Extract inline checkboxes (sub-tasks written as "- [ ] task" in body — here we treat them as metadata)
  -- Cards in markdown are single-line; multi-line cards need a note file
  local title = util.trim(text)

  return {
    title     = title,
    done      = done,
    tags      = tags,
    due_date  = due_date,
    note_file = note_file,
  }
end

-- ── Serialize helpers ────────────────────────────────────────────────────────

-- Serialize a card back to a markdown list item line.
local function serialize_card(card)
  local check = card.done and "x" or " "
  local text  = card.title

  if card.due_date and card.due_date ~= "" then
    text = text .. " @due(" .. card.due_date .. ")"
  end
  if card.note_file and card.note_file ~= "" then
    text = text .. " @note(" .. card.note_file .. ")"
  end
  for _, tag in ipairs(card.tags or {}) do
    text = text .. " #" .. tag
  end

  return "- [" .. check .. "] " .. text
end

-- Parse the body section into columns + cards.
local function parse_body(body)
  local columns = {}
  local current_col = nil

  local lines = util.split_lines(body)
  for _, line in ipairs(lines) do
    -- H2 heading = new column
    local col_name = line:match("^##%s+(.*)")
    if col_name then
      col_name = util.trim(col_name)
      -- Skip settings block markers
      if col_name ~= "" and not col_name:match("^%%") then
        current_col = { name = col_name, cards = {} }
        columns[#columns + 1] = current_col
      end
    elseif current_col and line:match("^%-%s+") then
      -- Card item
      local card = parse_card_line(line)
      if card.title ~= "" then
        card.id = util.uuid()
        current_col.cards[#current_col.cards + 1] = card
      end
    end
    -- Blank lines and other content are skipped
  end

  -- If no columns found, create defaults
  if #columns == 0 then
    columns = {
      { name = "To Do",      cards = {} },
      { name = "In Progress", cards = {} },
      { name = "Done",       cards = {} },
    }
  end

  return columns
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Parse markdown kanban content from a string.
---@param content string Raw file content
---@return table Board table with `frontmatter` and `columns` fields
function M.parse(content)
  local frontmatter, body = split_frontmatter(content)
  local columns = parse_body(body or content)

  return {
    frontmatter = frontmatter,
    columns     = columns,
  }
end

--- Read and parse a markdown kanban file from disk.
---@param filepath string Path to the file
---@return table Board table (default columns created when file is missing)
function M.parse_file(filepath)
  local content = util.read_file(filepath)
  if not content then
    -- Return a blank board
    return {
      frontmatter = nil,
      columns = {
        { name = "To Do",       cards = {} },
        { name = "In Progress", cards = {} },
        { name = "Done",        cards = {} },
      },
    }
  end
  return M.parse(content)
end

--- Serialize a board table to a markdown string.
---@param board table Board table
---@return string Markdown content
function M.serialize(board)
  local lines = {}

  -- Always write a canonical frontmatter block
  lines[#lines + 1] = "---"
  lines[#lines + 1] = "kanban-plugin: basic"
  lines[#lines + 1] = "---"
  lines[#lines + 1] = ""

  for _, col in ipairs(board.columns) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## " .. col.name
    lines[#lines + 1] = ""
    for _, card in ipairs(col.cards) do
      lines[#lines + 1] = serialize_card(card)
    end
  end

  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

--- Serialize a board and write it to disk.
---@param board table Board table
---@param filepath string Destination file path
---@return boolean True on success
function M.serialize_file(board, filepath)
  return util.write_file(filepath, M.serialize(board))
end

return M
