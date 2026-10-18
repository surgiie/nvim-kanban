local M = {}

--- Unlisted, unmodifiable scratch buffer that is wiped when hidden.
---@return integer
function M.scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden  = "wipe"
  vim.bo[buf].modifiable = false
  return buf
end

---@param buf integer
---@param lines string[]
function M.set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

--- Delete a buffer without closing the windows that show it; each gets an
--- empty buffer instead. Closing them could leave a sidebar such as a file
--- tree as the last window, which some plugins answer by quitting Neovim.
---@param buf integer
function M.delete_buf_keep_windows(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
  end
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

-- Make :w / :wq / :x in a nofile input buffer confirm instead of erroring.
local function redirect_write_to_confirm(buf, confirm)
  local command = "KanbanConfirm" .. buf
  vim.api.nvim_buf_create_user_command(buf, command, confirm, {})
  for _, write_command in ipairs({ "w", "wq", "x" }) do
    vim.cmd(string.format(
      "cnoreabbrev <buffer> <expr> %s (getcmdtype() == ':' && getcmdline() == '%s') ? '%s' : '%s'",
      write_command, write_command, command, write_command
    ))
  end
end

local function show_placeholder(buf, placeholder)
  local ns = vim.api.nvim_create_namespace("kanban_input_placeholder")
  local function update()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    if (vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "") == "" then
      vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
        virt_text     = { { placeholder, "Comment" } },
        virt_text_pos = "overlay",
        hl_mode       = "combine",
      })
    end
  end
  update()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = buf, callback = update })
end

local function open_input(opts, layout)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "kanban_input"

  local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("force", layout.geometry, {
    relative   = "editor",
    style      = "minimal",
    border     = opts.border or "rounded",
    title      = opts.title and (" " .. opts.title .. " "),
    title_pos  = opts.title and "center",
    footer     = layout.footer,
    footer_pos = "right",
    zindex     = opts.zindex or 200,
  }))
  vim.wo[win].winblend     = 100
  vim.wo[win].wrap         = layout.wrap
  vim.wo[win].cursorline   = false
  vim.wo[win].winhighlight = "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"

  local default = opts.default or ""
  if default ~= "" then vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default }) end
  show_placeholder(buf, opts.placeholder or "")

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function confirm()
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), " "))
    close()
    if text ~= "" then
      opts.on_confirm(text)
    elseif opts.on_empty or opts.on_cancel then
      (opts.on_empty or opts.on_cancel)()
    end
  end
  local function cancel()
    close()
    if opts.on_cancel then opts.on_cancel() end
  end

  local function map(modes, key, action)
    vim.keymap.set(modes, key, action, { buffer = buf, noremap = true, silent = true, nowait = true })
  end
  map({ "i", "n" }, "<C-s>", confirm)
  map("i", "<Esc>", "<Esc>")
  map("n", "<Esc>", cancel)
  for _, key in ipairs(layout.confirm_keys or {}) do map({ "i", "n" }, key, confirm) end
  for _, key in ipairs(layout.blocked_keys or {}) do map({ "i", "n" }, key, function() end) end
  redirect_write_to_confirm(buf, confirm)

  vim.cmd(default ~= "" and "startinsert!" or "startinsert")
end

--- Centered single-line input. Confirm with <CR> or <C-s>, cancel with <Esc>.
--- Confirming with no text calls `on_cancel`.
---@param opts { title: string?, default: string?, placeholder: string?, border: string?, zindex: integer?, on_confirm: fun(text: string), on_cancel: fun()? }
function M.small_input_float(opts)
  local width = math.min(70, vim.o.columns - 4)
  open_input(opts, {
    geometry     = {
      width  = width,
      height = 3,
      row    = math.floor((vim.o.lines - 3) / 2) - 1,
      col    = math.floor((vim.o.columns - width) / 2),
    },
    footer       = "  <CR> confirm  <Esc> cancel  ",
    wrap         = false,
    confirm_keys = { "<CR>" },
    blocked_keys = { "<C-j>" },
  })
end

--- Full-screen input whose lines are joined with spaces. Confirm with <C-s>,
--- cancel with <Esc>. Confirming with no text calls `on_empty`, or `on_cancel`
--- when `on_empty` is not given.
---@param opts { title: string?, default: string?, placeholder: string?, border: string?, zindex: integer?, on_confirm: fun(text: string), on_cancel: fun()?, on_empty: fun()? }
function M.input_float(opts)
  open_input(opts, {
    geometry = { width = vim.o.columns - 2, height = vim.o.lines - 4, row = 1, col = 0 },
    footer   = "  <C-s> confirm  <Esc> cancel  ",
    wrap     = true,
  })
end

return M
