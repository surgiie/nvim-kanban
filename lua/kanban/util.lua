local M = {}

local uv = vim.uv or vim.loop
local id_counter = 0

---@param text string
---@return string
function M.trim(text)
  return text:match("^%s*(.-)%s*$")
end

---@param text string
---@return string[]
function M.split_lines(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

--- Pad with spaces to the given display width.
---@param text string
---@param width integer
---@return string
function M.pad_right(text, width)
  local text_width = vim.fn.strdisplaywidth(text)
  if text_width >= width then return text end
  return text .. string.rep(" ", width - text_width)
end

--- Truncate to at most `max_width` display columns, ending with "…" when cut.
---@param text string|nil
---@param max_width integer
---@return string
function M.truncate(text, max_width)
  if not text then return "" end
  if vim.fn.strdisplaywidth(text) <= max_width then return text end
  local result, result_width, char_index = "", 0, 0
  while true do
    local char = vim.fn.strcharpart(text, char_index, 1)
    if char == "" then break end
    local char_width = vim.fn.strdisplaywidth(char)
    if result_width + char_width > max_width - 1 then break end
    result = result .. char
    result_width = result_width + char_width
    char_index = char_index + 1
  end
  return result .. "…"
end

---@return string Today as YYYY-MM-DD
function M.today()
  return tostring(os.date("%Y-%m-%d"))
end

---@param date_string string|nil YYYY-MM-DD
---@return boolean
function M.is_overdue(date_string)
  return date_string ~= nil and date_string < M.today()
end

---@param date_string string|nil YYYY-MM-DD
---@return boolean
function M.is_today(date_string)
  return date_string == M.today()
end

--- Short ID that is unique within a session and unlikely to repeat across sessions.
---@return string
function M.new_id()
  id_counter = id_counter + 1
  return string.format("%x-%05x", os.time(), (uv.hrtime() + id_counter) % 0x100000)
end

---@param path string
function M.ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

---@param path string
---@return boolean
function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

---@param path string
---@return string|nil
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
end

---@param path string
---@param content string
---@return boolean
function M.write_file(path, content)
  local file = io.open(path, "w")
  if not file then return false end
  file:write(content)
  file:close()
  return true
end

--- True for a markdown file directly inside a `.kanban/` directory.
---@param path string
---@return boolean
function M.is_board_path(path)
  return path:match("%.md$") ~= nil and vim.fn.fnamemodify(path, ":h:t") == ".kanban"
end

--- Lowercase, with runs of anything other than letters, digits and `-` turned into `_`.
---@param text string
---@return string
function M.slug(text)
  local result = text:lower():gsub("[^%w%-]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  return result
end

return M
