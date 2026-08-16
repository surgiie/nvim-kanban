-- A small floating calendar for picking a due date.
-- Navigate months with h/l, days with j/k or arrow keys, select with <CR>.
local win_util = require("kanban.ui.window")
local M = {}

local WEEKDAYS  = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
local MONTHS    = {
  "January","February","March","April","May","June",
  "July","August","September","October","November","December"
}

-- ── Calendar helpers ──────────────────────────────────────────────────────────

-- Return the total number of seconds in the given month (used to derive day count).
local function days_in_month(year, month)
  if month == 12 then
    return os.time({ year = year + 1, month = 1, day = 1 }) - os.time({ year = year, month = 12, day = 1 })
  end
  return os.time({ year = year, month = month + 1, day = 1 }) - os.time({ year = year, month = month, day = 1 })
end

-- Return the wday (1=Sun … 7=Sat) for the first day of the given month.
local function first_weekday_of_month(year, month, day)
  local t = os.date("*t", os.time({ year = year, month = month, day = day }))
  return t.wday  -- 1=Sun
end

-- Build the display lines for the calendar and return them along with derived grid data.
local function build_lines(year, month)
  local lines = {}

  -- Header
  lines[1] = string.format("  %s %d  ", MONTHS[month], year)

  -- Weekday row
  lines[2] = " " .. table.concat(WEEKDAYS, " ")

  -- Day grid
  local first_wd  = first_weekday_of_month(year, month, 1)  -- 1=Sun
  local num_days  = math.floor(days_in_month(year, month) / 86400)
  local day       = 1
  local grid_col  = first_wd  -- 1-based column

  local row_parts = {}
  for _ = 1, (first_wd - 1) do row_parts[#row_parts + 1] = "  " end

  while day <= num_days do
    row_parts[#row_parts + 1] = string.format("%2d", day)
    grid_col = grid_col + 1
    if grid_col > 7 then
      lines[#lines + 1] = " " .. table.concat(row_parts, " ")
      row_parts = {}
      grid_col = 1
    end
    day = day + 1
  end
  if #row_parts > 0 then
    lines[#lines + 1] = " " .. table.concat(row_parts, " ")
  end

  -- Footer hint
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  hjkl: day  H/L: month  <CR>: select  x: clear"

  return lines, num_days, first_wd
end

-- Apply highlight groups to every day cell in the calendar buffer.
-- Each spec: { row, col_start, col_end, highlight_group }
local function build_highlights(ns, buf, year, month, selected_day, first_wd)
  local today    = os.date("*t")
  local num_days = math.floor(days_in_month(year, month) / 86400)

  -- Header row = 0, weekday row = 1, day rows start at 2
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- Header highlight
  vim.api.nvim_buf_add_highlight(buf, ns, "KanbanCalHeader", 0, 0, -1)
  -- Weekday row
  vim.api.nvim_buf_add_highlight(buf, ns, "KanbanCalWeekday", 1, 0, -1)

  -- Day cells
  local grid_col  = first_wd
  local day       = 1
  local grid_row  = 2
  local row_col   = grid_col - 1  -- 0-based offset in line

  while day <= num_days do
    -- Each cell: " " + 2-char day = 3 chars wide; row starts with " " prefix
    -- Line format: " " .. cells separated by " "
    -- Position: 1 + (col-1)*3 = 1 + (row_col)*3
    local char_start = 1 + row_col * 3
    local char_end   = char_start + 2

    local highlight_group = "KanbanCalDay"
    local is_past = (year < today.year)
      or (year == today.year and month < today.month)
      or (year == today.year and month == today.month and day < today.day)
    if is_past then
      highlight_group = "KanbanOverdue"
    end
    if today.year == year and today.month == month and today.day == day then
      highlight_group = "KanbanCalToday"
    end
    if selected_day == day then
      highlight_group = "KanbanCalSelected"
    end

    vim.api.nvim_buf_add_highlight(buf, ns, highlight_group, grid_row, char_start, char_end)

    grid_col = grid_col + 1
    row_col  = row_col + 1
    if grid_col > 7 then
      grid_col = 1
      row_col  = 0
      grid_row = grid_row + 1
    end
    day = day + 1
  end
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Open the date-picker floating calendar.
---@param opts table|nil Options: current_date (string "YYYY-MM-DD"), on_confirm(date_str), on_cancel()
function M.open(opts)
  opts = opts or {}
  local config  = require("kanban").config
  local border = config.date_picker.border or "rounded"

  -- Start at today or the currently set date
  local initial   = opts.current_date
  local today     = os.date("*t")
  local year      = today.year
  local month     = today.month
  local sel_day   = today.day

  if initial and initial ~= "" then
    local y, m, d = initial:match("(%d%d%d%d)-(%d%d)-(%d%d)")
    if y then
      ---@diagnostic disable-next-line: param-type-mismatch
      year    = math.floor(tonumber(y) or year)
      ---@diagnostic disable-next-line: param-type-mismatch
      month   = math.floor(tonumber(m) or month)
      ---@diagnostic disable-next-line: param-type-mismatch
      sel_day = math.floor(tonumber(d) or sel_day)
    end
  end

  local buf = win_util.scratch_buf()
  local ns  = vim.api.nvim_create_namespace("kanban_cal")

  -- ── Render ───────────────────────────────────────────────────────────────

  -- Re-render the calendar buffer for the current year/month/sel_day.
  local function render()
    local lines, _, first_wd = build_lines(year, month)
    win_util.set_lines(buf, lines)
    build_highlights(ns, buf, year, month, sel_day, first_wd)
  end

  local terminal_width  = vim.o.columns
  local terminal_height = vim.o.lines
  local width = terminal_width - 2
  local h     = terminal_height - 4
  local row = 1
  local col = 0

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = h,
    row      = row,
    col      = col,
    anchor   = "NW",
    style    = "minimal",
    border   = border,
    title    = " Pick a date ",
    title_pos = "center",
    zindex   = 110,
  })

  vim.wo[win].winblend     = 0
  vim.wo[win].winhighlight = "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"
  vim.wo[win].cursorline   = false

  render()

  local map_opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  -- Close the picker window.
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Navigate to the previous month, clamping the selected day.
  local function prev_month()
    month = month - 1
    if month < 1 then month = 12; year = year - 1 end
    -- Clamp sel_day to new month
    local num_days = math.floor(days_in_month(year, month) / 86400)
    ---@diagnostic disable-next-line: param-type-mismatch
    sel_day = math.min(math.floor(sel_day), num_days)
    render()
  end

  -- Navigate to the next month, clamping the selected day.
  local function next_month()
    month = month + 1
    if month > 12 then month = 1; year = year + 1 end
    local num_days = math.floor(days_in_month(year, month) / 86400)
    ---@diagnostic disable-next-line: param-type-mismatch
    sel_day = math.min(math.floor(sel_day), num_days)
    render()
  end

  -- Move the selection by delta days, wrapping across months as needed.
  local function move_day(delta)
    local num_days = math.floor(days_in_month(year, month) / 86400)
    sel_day = sel_day + delta
    if sel_day < 1 then
      prev_month()
      sel_day = math.floor(days_in_month(year, month) / 86400)
    elseif sel_day > num_days then
      next_month()
      sel_day = 1
    else
      render()
    end
  end

  -- ── Keymaps ──────────────────────────────────────────────────────────────

  vim.keymap.set("n", "h",       function() move_day(-1) end,  map_opts)
  vim.keymap.set("n", "l",       function() move_day(1) end,   map_opts)
  vim.keymap.set("n", "j",       function() move_day(7) end,   map_opts)
  vim.keymap.set("n", "k",       function() move_day(-7) end,  map_opts)
  vim.keymap.set("n", "H",       prev_month,                   map_opts)
  vim.keymap.set("n", "L",       next_month,                   map_opts)
  vim.keymap.set("n", "<Left>",  function() move_day(-1) end,  map_opts)
  vim.keymap.set("n", "<Right>", function() move_day(1) end,   map_opts)
  vim.keymap.set("n", "<Down>",  function() move_day(7) end,   map_opts)
  vim.keymap.set("n", "<Up>",    function() move_day(-7) end,  map_opts)

  vim.keymap.set("n", "<CR>", function()
    close()
    local date_str = string.format("%04d-%02d-%02d", year, month, sel_day)
    if opts.on_confirm then opts.on_confirm(date_str) end
  end, map_opts)

  vim.keymap.set("n", "<Esc>", function()
    close()
    if opts.on_cancel then opts.on_cancel() end
  end, map_opts)

  vim.keymap.set("n", "x",    function()
    close()
    if opts.on_confirm then opts.on_confirm("") end
  end, map_opts)
  vim.keymap.set("n", "<BS>", function() end, map_opts)

  -- Auto-close when focus leaves
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer  = buf,
    once    = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end)
    end,
  })
end

return M
