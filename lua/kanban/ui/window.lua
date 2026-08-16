-- Low-level window/buffer creation helpers.
local M = {}

--- Create a scratch buffer that is wiped on close and never saved.
---@return number Buffer handle
function M.scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile  = false
  vim.bo[buf].modifiable = false
  return buf
end

--- Replace the contents of a buffer (temporarily lifting the modifiable lock).
---@param buf number Buffer handle
---@param lines table List of line strings
function M.set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Open a centered floating window for the given buffer.
---@param buf number Buffer handle to display
---@param opts table|nil Options: width, height, width_pct, height_pct, row, col,
---                               relative, anchor, border, zindex, title, footer,
---                               enter, hl_normal, hl_border, hl_cursor, cursorline
---@return number Window handle
function M.open_float(buf, opts)
  opts = opts or {}
  local terminal_width  = vim.o.columns
  local terminal_height = vim.o.lines
  local w = opts.width  or math.floor(terminal_width  * (opts.width_pct  or 0.8))
  local h = opts.height or math.floor(terminal_height * (opts.height_pct or 0.7))

  local row = opts.row or math.floor((terminal_height - h) / 2)
  local col = opts.col or math.floor((terminal_width  - w) / 2)

  local win_cfg = {
    relative  = opts.relative or "editor",
    width     = w,
    height    = h,
    row       = row,
    col       = col,
    anchor    = opts.anchor or "NW",
    style     = "minimal",
    border    = opts.border or "rounded",
    zindex    = opts.zindex or 50,
  }
  if opts.title then
    win_cfg.title     = " " .. opts.title .. " "
    win_cfg.title_pos = "center"
  end
  if opts.footer then
    win_cfg.footer     = opts.footer
    win_cfg.footer_pos = "right"
  end

  local win = vim.api.nvim_open_win(buf, opts.enter ~= false, win_cfg)

  -- Window-local options
  vim.wo[win].winblend    = 100
  vim.wo[win].wrap        = false
  vim.wo[win].number      = false
  vim.wo[win].signcolumn  = "no"
  vim.wo[win].cursorline  = opts.cursorline ~= false
  vim.wo[win].winhighlight =
    "Normal:" .. (opts.hl_normal or "KanbanNormal") ..
    ",FloatBorder:" .. (opts.hl_border or "KanbanBorder") ..
    ",CursorLine:" .. (opts.hl_cursor or "KanbanCursorLine")

  -- Swallow keys that would leak through to buffers underneath
  local noop = function() end
  local swallow = { "<BS>", "h", "l", "w", "b", "e", "0", "$", "^",
                    "<Left>", "<Right>", "<Up>", "<Down>",
                    "x", "s", "S", "c", "C", "o", "O", "p", "P", "u", "<C-r>" }
  for _, key in ipairs(swallow) do
    vim.keymap.set("n", key, noop, { buffer = buf, noremap = true, silent = true, nowait = true })
  end

  return win
end

--- Close a floating window and optionally delete its buffer.
---@param win number|nil Window handle
---@param buf number|nil Buffer handle
function M.close(win, buf)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

--- Open a small centered single-line input float (for short prompts like column names).
--- Confirm with <CR> or <C-s>, cancel with <Esc>.
---@param opts table|nil Options: title, default, placeholder, width, border, zindex, on_confirm, on_cancel
function M.small_input_float(opts)
  opts = opts or {}
  local border         = opts.border or "rounded"
  local terminal_width = vim.o.columns
  local terminal_height = vim.o.lines
  local width          = opts.width or math.min(70, terminal_width - 4)
  local height         = 3

  local row = math.floor((terminal_height - height) / 2) - 1
  local col = math.floor((terminal_width  - width)  / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "kanban_input"

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    anchor    = "NW",
    style     = "minimal",
    border    = border,
    title     = opts.title and (" " .. opts.title .. " ") or nil,
    title_pos = "center",
    footer     = "  <CR> confirm  <Esc> cancel  ",
    footer_pos = "right",
    zindex    = opts.zindex or 200,
  })

  vim.api.nvim_set_option_value("winblend", 100, { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", false, { win = win })
  vim.api.nvim_set_option_value("winhighlight",
    "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder", { win = win })

  -- Ghost/placeholder text shown when buffer is empty
  local placeholder_ns = vim.api.nvim_create_namespace("kanban_small_input_placeholder")
  local placeholder = opts.placeholder or "..."
  local function update_placeholder()
    vim.api.nvim_buf_clear_namespace(buf, placeholder_ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    if not lines[1] or lines[1] == "" then
      vim.api.nvim_buf_set_extmark(buf, placeholder_ns, 0, 0, {
        virt_text     = { { placeholder, "Comment" } },
        virt_text_pos = "overlay",
        hl_mode       = "combine",
      })
    end
  end

  -- Seed default text
  if opts.default and opts.default ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default })
    vim.api.nvim_win_set_cursor(win, { 1, #opts.default })
  end
  update_placeholder()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer   = buf,
    callback = update_placeholder,
  })

  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    local val   = vim.trim(lines[1] or "")
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if opts.on_confirm then opts.on_confirm(val) end
  end

  local function cancel()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if opts.on_cancel then opts.on_cancel() end
  end

  local map = function(modes, key, fn)
    vim.keymap.set(modes, key, fn, { buffer = buf, noremap = true, silent = true, nowait = true })
  end

  map({ "i", "n" }, "<CR>",  confirm)
  map({ "i", "n" }, "<C-s>", confirm)
  map({ "i", "n" }, "<Esc>", cancel)

  -- Block multi-line input
  map({ "i", "n" }, "<C-j>", function() end)
  map({ "i", "n" }, "<C-m>", function() end)

  if opts.default and opts.default ~= "" then
    vim.cmd("startinsert!")
  else
    vim.cmd("startinsert")
  end
end

--- Open a full-screen editable float for text input (add/edit card).
--- Confirm with <C-s>, cancel with <Esc>.
---@param opts table|nil Options: title, default, placeholder, width, height, border, zindex, on_confirm, on_cancel
function M.input_float(opts)
  opts = opts or {}
  local border          = opts.border or "rounded"
  local terminal_width  = vim.o.columns
  local terminal_height = vim.o.lines
  local width           = terminal_width  - 2
  local height          = terminal_height - 4

  local row = 1
  local col = 0

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "kanban_input"

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    anchor    = "NW",
    style     = "minimal",
    border    = border,
    title     = opts.title and (" " .. opts.title .. " ") or nil,
    title_pos = "center",
    zindex    = opts.zindex or 100,
  })

  vim.api.nvim_set_option_value("winblend", 100, { win = win })
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("cursorline", false, { win = win })
  vim.api.nvim_set_option_value("winhighlight",
    "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder", { win = win })

  -- Footer hint
  vim.api.nvim_win_set_config(win, {
    footer     = "  <C-s> confirm  <Esc> cancel  ",
    footer_pos = "right",
  })

  -- Seed default text and place cursor at end
  if opts.default and opts.default ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default })
    vim.api.nvim_win_set_cursor(win, { 1, #opts.default - 1 })
  end

  -- Ghost/placeholder text shown when buffer is empty
  local placeholder_ns = vim.api.nvim_create_namespace("kanban_input_placeholder")
  local placeholder = opts.placeholder or "title #tag1 #tag2 ..."
  local function update_placeholder()
    vim.api.nvim_buf_clear_namespace(buf, placeholder_ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
    if not lines[1] or lines[1] == "" then
      vim.api.nvim_buf_set_extmark(buf, placeholder_ns, 0, 0, {
        virt_text          = { { placeholder, "Comment" } },
        virt_text_pos      = "overlay",
        hl_mode            = "combine",
      })
    end
  end
  update_placeholder()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer   = buf,
    callback = update_placeholder,
  })

  local function confirm()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local val   = vim.trim(table.concat(lines, " "))
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if val ~= "" and opts.on_confirm then opts.on_confirm(val) end
  end

  local function cancel()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if opts.on_cancel then opts.on_cancel() end
  end

  local map = function(modes, key, fn)
    vim.keymap.set(modes, key, fn, { buffer = buf, noremap = true, silent = true, nowait = true })
  end

  map({"i", "n"}, "<C-s>", confirm)
  map({"i", "n"}, "<Esc>", cancel)

  if opts.default and opts.default ~= "" then
    vim.cmd("startinsert!")
  else
    vim.cmd("startinsert")
  end
end

return M
