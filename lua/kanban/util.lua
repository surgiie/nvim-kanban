local M = {}

--- Apply a function to every element of a table and return the results.
---@param tbl table Input list
---@param fn function Mapping function(value, index) → new_value
---@return table Mapped list
function M.map(tbl, fn)
  local result = {}
  for i, v in ipairs(tbl) do result[i] = fn(v, i) end
  return result
end

--- Return a new list containing only the elements for which fn returns true.
---@param tbl table Input list
---@param fn function Predicate function(value) → bool
---@return table Filtered list
function M.filter(tbl, fn)
  local result = {}
  for _, v in ipairs(tbl) do
    if fn(v) then result[#result + 1] = v end
  end
  return result
end

--- Return the first element and its index for which fn returns true.
---@param tbl table Input list
---@param fn function Predicate function(value) → bool
---@return any|nil, number|nil First matching value and its index, or nil, nil
function M.find(tbl, fn)
  for i, v in ipairs(tbl) do
    if fn(v) then return v, i end
  end
  return nil, nil
end

--- Check whether a list contains a specific value.
---@param tbl table Input list
---@param value any Value to search for
---@return boolean True if the value is present
function M.contains(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then return true end
  end
  return false
end

--- Strip leading and trailing whitespace from a string.
---@param s string Input string
---@return string Trimmed string
function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

--- Split a string into a list of lines.
---@param s string Input string (may or may not end with a newline)
---@return table List of line strings
function M.split_lines(s)
  local lines = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  return lines
end

--- Pad a string on the right with spaces to reach the desired display width.
---@param s string Input string
---@param width number Target display width in columns
---@return string Padded string
function M.pad_right(s, width)
  local len = vim.fn.strdisplaywidth(s)
  if len >= width then return s end
  return s .. string.rep(" ", width - len)
end

--- Truncate a UTF-8 string to at most max_width display columns, appending "…".
---@param s string Input string
---@param max_width number Maximum display width including the ellipsis
---@return string Truncated string
function M.truncate(s, max_width)
  local len = vim.fn.strdisplaywidth(s)
  if len <= max_width then return s end
  -- Walk codepoints via vim.fn.strcharpart (no utf8 global needed)
  local result = ""
  local w = 0
  local char_idx = 0
  while true do
    local char = vim.fn.strcharpart(s, char_idx, 1)
    if char == "" then break end
    local cw = vim.fn.strdisplaywidth(char)
    if w + cw > max_width - 1 then break end
    result = result .. char
    w = w + cw
    char_idx = char_idx + 1
  end
  return result .. "…"
end

--- Truncate a string safely, falling back to byte-based truncation on error.
---@param s string|nil Input string (nil returns "")
---@param max_width number Maximum display width
---@return string Truncated string, never nil
function M.safe_truncate(s, max_width)
  if not s then return "" end
  local success, result = pcall(M.truncate, s, max_width)
  if success then return result end
  -- fallback: simple byte-based truncation
  if #s > max_width - 1 then
    return s:sub(1, max_width - 1) .. "…"
  end
  return s
end

--- Parse a YYYY-MM-DD date string into a table with year/month/day fields.
---@param date_str string Date in "YYYY-MM-DD" format
---@return table|nil Table with year, month, day keys, or nil on parse failure
function M.date_to_table(date_str)
  -- Parse YYYY-MM-DD
  local y, m, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not y then return nil end
  return { year = tonumber(y), month = tonumber(m), day = tonumber(d) }
end

--- Return today's date as a "YYYY-MM-DD" string.
---@return string Today's date
function M.today()
  return tostring(os.date("%Y-%m-%d"))
end

--- Return true if the given date string is strictly before today.
---@param date_str string|nil Date in "YYYY-MM-DD" format
---@return boolean True if the date is in the past
function M.is_overdue(date_str)
  if not date_str then return false end
  return date_str < M.today()
end

--- Return true if the given date string equals today's date.
---@param date_str string Date in "YYYY-MM-DD" format
---@return boolean True if the date is today
function M.is_today(date_str)
  return date_str == M.today()
end

--- Return the number of whole days until the given date (negative = past).
---@param date_str string|nil Date in "YYYY-MM-DD" format
---@return number|nil Days remaining, or nil if date_str is nil/invalid
function M.days_until(date_str)
  if not date_str then return nil end
  local dt = M.date_to_table(date_str)
  if not dt then return nil end
  local target = os.time(dt)
  local now    = os.time()
  return math.floor((target - now) / 86400)
end

--- Generate a simple pseudo-random ID based on time and a random number.
---@return string ID string in the form "hextime-hexrand"
function M.uuid()
  local t = os.time()
  local r = math.random(0, 0xffff)
  return string.format("%x-%x", t, r)
end

--- Create a directory (and any missing parents) if it does not exist.
---@param path string Directory path to create
function M.ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

--- Return true if a file exists and is readable.
---@param path string File path to check
---@return boolean True if the file is readable
function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

--- Read the entire contents of a file as a string.
---@param path string File path to read
---@return string|nil File contents, or nil if the file cannot be opened
function M.read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

--- Write a string to a file, overwriting any existing content.
---@param path string Destination file path
---@param content string Content to write
---@return boolean True on success, false if the file could not be opened
function M.write_file(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

--- Convert a string to a URL-safe slug (lowercase, underscores for special chars).
---@param s string Input string
---@return string Slug string
function M.slug(s)
  local result = s:lower():gsub("[^%w%-]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  return result
end

return M
