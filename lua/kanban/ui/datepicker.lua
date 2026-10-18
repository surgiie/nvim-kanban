-- Full-screen calendar for picking a due date.
local win_util = require("kanban.ui.window")
local M = {}

local WEEKDAYS = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
local MONTHS = {
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
}

local function days_in_month(year, month)
  -- Day 0 of the next month normalizes to the last day of this one
  return os.date("*t", os.time({ year = year, month = month + 1, day = 0 })).day
end

-- Return the calendar lines and the 0-based { row, col } of each day number.
local function build_lines(year, month)
  local lines = {
    string.format("  %s %d  ", MONTHS[month], year),
    " " .. table.concat(WEEKDAYS, " "),
  }
  local positions = {}
  local weekday = os.date("*t", os.time({ year = year, month = month, day = 1 })).wday
  local cells = {}
  for _ = 1, weekday - 1 do cells[#cells + 1] = "  " end

  local day_count = days_in_month(year, month)
  for day = 1, day_count do
    positions[day] = { #lines, 1 + #cells * 3 }
    cells[#cells + 1] = string.format("%2d", day)
    if #cells == 7 or day == day_count then
      lines[#lines + 1] = " " .. table.concat(cells, " ")
      cells = {}
    end
  end

  vim.list_extend(lines, { "", "  hjkl: day  H/L: month  <CR>: select  x: clear" })
  return lines, positions
end

--- Open the picker. `on_confirm` receives YYYY-MM-DD, or nil when cleared with x.
---@param opts { current_date: string?, on_confirm: fun(date: string|nil) }
function M.open(opts)
  local config = require("kanban").config
  local today  = os.date("*t")
  local year, month, selected_day = today.year, today.month, today.day

  local y, m, d = (opts.current_date or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if y then
    year, month, selected_day = tonumber(y) --[[@as integer]], tonumber(m) --[[@as integer]], tonumber(d) --[[@as integer]]
  end

  local buf = win_util.scratch_buf()
  local ns  = vim.api.nvim_create_namespace("kanban_calendar")

  local function render()
    local lines, positions = build_lines(year, month)
    win_util.set_lines(buf, lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "KanbanCalHeader", 0, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "KanbanCalWeekday", 1, 0, -1)
    local current_month = year == today.year and month == today.month
    local past_month = year < today.year or (year == today.year and month < today.month)
    for day, position in pairs(positions) do
      local group = "KanbanCalDay"
      if past_month or (current_month and day < today.day) then group = "KanbanOverdue" end
      if current_month and day == today.day then group = "KanbanCalToday" end
      if day == selected_day then group = "KanbanCalSelected" end
      vim.api.nvim_buf_add_highlight(buf, ns, group, position[1], position[2], position[2] + 2)
    end
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = vim.o.columns - 2,
    height    = vim.o.lines - 4,
    row       = 1,
    col       = 0,
    style     = "minimal",
    border    = config.date_picker.border,
    title     = " Pick a date ",
    title_pos = "center",
    zindex    = 110,
  })
  vim.wo[win].winhighlight = "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"
  vim.wo[win].cursorline   = false
  render()

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local function shift_month(delta)
    month = month + delta
    if month < 1 then month, year = 12, year - 1 end
    if month > 12 then month, year = 1, year + 1 end
    selected_day = math.min(selected_day, days_in_month(year, month))
    render()
  end

  local function move_day(delta)
    selected_day = selected_day + delta
    if selected_day < 1 then
      shift_month(-1)
      selected_day = days_in_month(year, month)
    elseif selected_day > days_in_month(year, month) then
      shift_month(1)
      selected_day = 1
    end
    render()
  end

  local function map(key, action)
    vim.keymap.set("n", key, action, { buffer = buf, noremap = true, silent = true, nowait = true })
  end
  for keys, delta in pairs({ [{ "h", "<Left>" }] = -1, [{ "l", "<Right>" }] = 1,
                             [{ "j", "<Down>" }] = 7, [{ "k", "<Up>" }] = -7 }) do
    for _, key in ipairs(keys) do map(key, function() move_day(delta) end) end
  end
  map("H", function() shift_month(-1) end)
  map("L", function() shift_month(1) end)
  map("<CR>", function()
    close()
    opts.on_confirm(string.format("%04d-%02d-%02d", year, month, selected_day))
  end)
  map("x", function()
    close()
    opts.on_confirm(nil)
  end)
  map("<Esc>", close)
  map("<BS>", function() end)

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer   = buf,
    once     = true,
    callback = function() vim.schedule(close) end,
  })
end

return M
