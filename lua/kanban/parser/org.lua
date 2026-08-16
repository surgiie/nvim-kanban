-- Parses and serializes org-mode kanban files.
--
-- Convention:
--   * Level-1 headings = columns  (the TODO keyword is ignored here)
--   * Level-2 headings = cards    (TODO keyword determines done state)
--
-- Example:
--   #+TODO: TODO IN-PROGRESS | DONE
--
--   * To Do
--   ** TODO Write the parser                       :feature:
--      DEADLINE: <2025-01-20 Mon>
--   ** TODO Another task
--
--   * In Progress
--   ** IN-PROGRESS Refactor UI                     :refactor:
--
--   * Done
--   ** DONE Initial scaffold                        :setup:
--      CLOSED: [2025-01-05 Sun]
--
local util = require("kanban.util")
local M = {}

-- ── Parse helpers ─────────────────────────────────────────────────────────────

-- Known "done" keywords
local DONE_KEYWORDS = { DONE = true, CANCELLED = true, CLOSED = true, FIXED = true }

-- Return true if the given org keyword represents a "done" state.
local function is_done_keyword(kw)
  return DONE_KEYWORDS[kw] == true
end

-- Parse the tag string from the end of an org headline suffix ("   :tag1:tag2:").
local function parse_headline_tags(suffix)
  local tags = {}
  local tag_str = suffix:match(":([%w:_@#%%]+):$")
  if tag_str then
    for tag in tag_str:gmatch("[^:]+") do
      tags[#tags + 1] = tag
    end
  end
  return tags
end

-- Strip tags from the end of a headline title string.
local function strip_tags(title)
  return util.trim(title:gsub("%s+:[%w:_@#%%]+:%s*$", ""))
end

-- Parse a card block starting at lines[start_idx] and return the card table plus the next line index.
local function parse_card_block(lines, start_idx)
  -- lines[start_idx] is the "** KEYWORD Title  :tags:" line
  local header = lines[start_idx]
  local stars, rest = header:match("^(%*+)%s+(.*)")
  if not stars then return nil end

  local keyword, title_part
  keyword, title_part = rest:match("^(%u[%u%-]+)%s+(.*)")
  if not keyword or keyword:match("[a-z]") then
    -- No keyword — treat entire rest as title
    keyword    = nil
    title_part = rest
  end

  local tags  = parse_headline_tags(title_part)
  local title = strip_tags(title_part)
  local done  = keyword and is_done_keyword(keyword) or false

  local due_date  = nil
  local note_file = nil
  local body_lines = {}
  local i = start_idx + 1

  while i <= #lines do
    local next_line = lines[i]
    -- Stop at next heading of same or higher level
    if next_line:match("^%*") then break end

    -- DEADLINE / SCHEDULED
    local dl = next_line:match("DEADLINE:%s*[<%(](%d%d%d%d%-%d%d%-%d%d)")
    if dl then due_date = dl end
    local dl2 = next_line:match("SCHEDULED:%s*[<%(](%d%d%d%d%-%d%d%-%d%d)")
    if dl2 and not due_date then due_date = dl2 end

    -- Note file property
    local nf = next_line:match(":KANBAN_NOTE:%s*(.+)")
    if nf then note_file = util.trim(nf) end

    body_lines[#body_lines + 1] = next_line
    i = i + 1
  end

  return {
    id        = util.uuid(),
    title     = title,
    done      = done,
    keyword   = keyword,
    tags      = tags,
    due_date  = due_date,
    note_file = note_file,
    _body     = body_lines,
  }, i
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Parse org-mode content from a string.
---@param content string Raw file content
---@return table Board table with `header_lines`, `todo_keywords`, and `columns` fields
function M.parse(content)
  local lines         = util.split_lines(content)
  local columns       = {}
  local header_lines  = {}  -- lines before the first * heading
  local todo_keywords = {}  -- from #+TODO lines

  local current_col = nil
  local i = 1

  while i <= #lines do
    local line = lines[i]

    -- #+TODO keyword lines
    local todo_def = line:match("^#%+TODO:%s*(.*)")
    if todo_def then
      for kw in todo_def:gmatch("%u[%u%-]+") do
        todo_keywords[#todo_keywords + 1] = kw
      end
      header_lines[#header_lines + 1] = line
      i = i + 1

    -- Level-1 heading = column
    elseif line:match("^%*%s+") and not line:match("^%*%*") then
      local col_title = line:match("^%*%s+(.*)")
      col_title = util.trim(col_title)
      current_col = { name = col_title, cards = {} }
      columns[#columns + 1] = current_col
      i = i + 1

    -- Level-2 heading = card
    elseif line:match("^%*%*%s+") and current_col then
      local card, next_i = parse_card_block(lines, i)
      if card and next_i then
        current_col.cards[#current_col.cards + 1] = card
        i = next_i
      else
        i = i + 1
      end

    else
      if not current_col then
        header_lines[#header_lines + 1] = line
      end
      i = i + 1
    end
  end

  if #columns == 0 then
    columns = {
      { name = "To Do",       cards = {} },
      { name = "In Progress", cards = {} },
      { name = "Done",        cards = {} },
    }
  end

  return {
    header_lines  = header_lines,
    todo_keywords = todo_keywords,
    columns       = columns,
  }
end

--- Read and parse an org-mode kanban file from disk.
---@param filepath string Path to the file
---@return table Board table (default columns created when file is missing)
function M.parse_file(filepath)
  local content = util.read_file(filepath)
  if not content then
    return {
      header_lines = { "#+TODO: TODO IN-PROGRESS | DONE" },
      todo_keywords = { "TODO", "IN-PROGRESS", "DONE" },
      columns = {
        { name = "To Do",       cards = {} },
        { name = "In Progress", cards = {} },
        { name = "Done",        cards = {} },
      },
    }
  end
  return M.parse(content)
end

-- ── Serialize helpers ────────────────────────────────────────────────────────

-- Serialize a single card to a list of org-mode lines.
local function serialize_card(card)
  local lines = {}
  local kw = card.keyword
  if not kw then
    kw = card.done and "DONE" or "TODO"
  end

  -- Build tag string
  local tag_str = ""
  if #(card.tags or {}) > 0 then
    tag_str = "  :" .. table.concat(card.tags, ":") .. ":"
  end

  lines[#lines + 1] = "** " .. kw .. " " .. card.title .. tag_str

  -- Re-emit body, preserving DEADLINE/SCHEDULED/properties
  if card._body then
    for _, body_line in ipairs(card._body) do
      -- Re-emit note property
      if card.note_file and body_line:match(":KANBAN_NOTE:") then
        lines[#lines + 1] = "   :KANBAN_NOTE: " .. card.note_file
      elseif not body_line:match(":KANBAN_NOTE:") then
        lines[#lines + 1] = body_line
      end
    end
  else
    if card.due_date then
      lines[#lines + 1] = "   DEADLINE: <" .. card.due_date .. ">"
    end
    if card.note_file then
      lines[#lines + 1] = "   :PROPERTIES:"
      lines[#lines + 1] = "   :KANBAN_NOTE: " .. card.note_file
      lines[#lines + 1] = "   :END:"
    end
  end

  return lines
end

--- Serialize a board table to an org-mode string.
---@param board table Board table
---@return string Org-mode content
function M.serialize(board)
  local lines = {}

  -- Header / keyword definitions
  for _, header_line in ipairs(board.header_lines or {}) do
    lines[#lines + 1] = header_line
  end
  if #(board.header_lines or {}) == 0 then
    lines[#lines + 1] = "#+TODO: TODO IN-PROGRESS | DONE"
  end
  lines[#lines + 1] = ""

  for _, col in ipairs(board.columns) do
    lines[#lines + 1] = "* " .. col.name
    lines[#lines + 1] = ""
    for _, card in ipairs(col.cards) do
      local card_lines = serialize_card(card)
      for _, card_line in ipairs(card_lines) do
        lines[#lines + 1] = card_line
      end
      lines[#lines + 1] = ""
    end
  end

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
