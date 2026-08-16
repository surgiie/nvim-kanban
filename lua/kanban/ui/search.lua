-- Floating search popup: fuzzy-filter cards across all columns.
local win_util = require("kanban.ui.window")
local board    = require("kanban.board")
local util     = require("kanban.util")
local M = {}

--- Open the search popup.
--- Calls on_select(col_idx, card_idx) when the user confirms a result.
---@param on_select function Callback invoked with (col_idx, card_idx) on confirmation
function M.open(on_select)
  local cfg    = require("kanban").config
  local icons  = cfg.icons
  local width  = math.max(60, math.floor(vim.o.columns * 0.6))
  local border = cfg.popup.border or "rounded"

  -- Result list buffer
  local res_buf = win_util.scratch_buf()
  local ns      = vim.api.nvim_create_namespace("kanban_search")

  -- Prompt buffer
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype   = "prompt"
  vim.bo[prompt_buf].bufhidden = "wipe"

  local terminal_width  = vim.o.columns
  local terminal_height = vim.o.lines

  local res_height = math.min(15, math.floor(terminal_height * 0.4))
  local total_h    = res_height + 3  -- result area + separator + prompt
  local start_row  = math.floor((terminal_height - total_h) / 2)
  local start_col  = math.floor((terminal_width  - width)   / 2)

  -- Results window (above prompt)
  local res_win = vim.api.nvim_open_win(res_buf, false, {
    relative  = "editor",
    width     = width,
    height    = res_height,
    row       = start_row,
    col       = start_col,
    anchor    = "NW",
    style     = "minimal",
    border    = { "╭", "─", "╮", "│", "│", " ", "│", "│" },
    title     = " " .. icons.search .. " Search cards ",
    title_pos = "center",
    zindex    = 100,
  })
  vim.wo[res_win].winblend     = 100
  vim.wo[res_win].winhighlight =
    "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"
  vim.wo[res_win].cursorline = true
  vim.wo[res_win].wrap = false
  vim.wo[res_win].number = false
  vim.wo[res_win].signcolumn = "no"
  vim.keymap.set("n", "<BS>", function() end, { buffer = res_buf, noremap = true, silent = true, nowait = true })

  -- Prompt window (below results)
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative  = "editor",
    width     = width,
    height    = 1,
    row       = start_row + res_height,
    col       = start_col,
    anchor    = "NW",
    style     = "minimal",
    border    = { "│", " ", "│", "│", "╰", "─", "╯", "│" },
    zindex    = 100,
  })
  vim.wo[prompt_win].winblend     = 100
  vim.wo[prompt_win].winhighlight =
    "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"

  vim.fn.prompt_setprompt(prompt_buf, icons.search .. " ")

  local results  = {}
  local selected = 1

  -- Re-render the results list for the given query string.
  local function render_results(query)
    results  = board.search(query)
    selected = 1

    if #results == 0 then
      local empty = { "  (no results)" }
      vim.bo[res_buf].modifiable = true
      vim.api.nvim_buf_set_lines(res_buf, 0, -1, false, empty)
      vim.bo[res_buf].modifiable = false
      vim.api.nvim_buf_clear_namespace(res_buf, ns, 0, -1)
      return
    end

    local lines    = {}
    local hl_specs = {}

    for i, r in ipairs(results) do
      local card        = r.card
      local col_name    = r.col_name
      local done_icon   = card.done and icons.card_done or icons.card
      local line = string.format("  %s %-24s  %s%s",
        done_icon,
        util.safe_truncate(card.title, 28),
        icons.column,
        util.safe_truncate(col_name, 16)
      )
      -- Append tags
      if #(card.tags or {}) > 0 then
        line = line .. "  " .. icons.tag .. table.concat(card.tags, " " .. icons.tag)
      end
      lines[#lines + 1] = line

      local highlight_group = card.done and "KanbanCardDone" or "KanbanCard"
      if i == selected then highlight_group = "KanbanCardSelected" end
      hl_specs[#hl_specs + 1] = { i - 1, 0, -1, highlight_group }
    end

    vim.bo[res_buf].modifiable = true
    vim.api.nvim_buf_set_lines(res_buf, 0, -1, false, lines)
    vim.bo[res_buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(res_buf, ns, 0, -1)
    for _, spec in ipairs(hl_specs) do
      vim.api.nvim_buf_add_highlight(res_buf, ns, spec[4], spec[1], spec[2], spec[3])
    end

    pcall(vim.api.nvim_win_set_cursor, res_win, { 1, 0 })
  end

  -- Refresh highlight groups after changing the selected result index.
  local function highlight_selected()
    vim.api.nvim_buf_clear_namespace(res_buf, ns, 0, -1)
    for i, r in ipairs(results) do
      local card            = r.card
      local highlight_group = card.done and "KanbanCardDone" or "KanbanCard"
      if i == selected then highlight_group = "KanbanCardSelected" end
      vim.api.nvim_buf_add_highlight(res_buf, ns, highlight_group, i - 1, 0, -1)
    end
    if selected > 0 and selected <= #results then
      pcall(vim.api.nvim_win_set_cursor, res_win, { selected, 0 })
    end
  end

  -- Close both popup windows.
  local function close()
    if vim.api.nvim_win_is_valid(prompt_win) then
      vim.api.nvim_win_close(prompt_win, true)
    end
    if vim.api.nvim_win_is_valid(res_win) then
      vim.api.nvim_win_close(res_win, true)
    end
  end

  -- Confirm the currently selected result and invoke on_select.
  local function confirm()
    if #results == 0 then close(); return end
    local r = results[selected]
    close()
    if on_select and r then
      on_select(r.col_idx, r.card_idx)
    end
  end

  local p_opts = { buffer = prompt_buf, noremap = true, silent = true, nowait = true }

  vim.keymap.set({ "i", "n" }, "<CR>",  confirm,        p_opts)
  vim.keymap.set({ "i", "n" }, "<Esc>", close,          p_opts)
  vim.keymap.set("n",          "<BS>",  function() end, p_opts)
  vim.keymap.set({ "i", "n" }, "<C-n>", function()
    selected = math.min(selected + 1, math.max(#results, 1))
    highlight_selected()
  end, p_opts)
  vim.keymap.set({ "i", "n" }, "<C-p>", function()
    selected = math.max(selected - 1, 1)
    highlight_selected()
  end, p_opts)
  vim.keymap.set({ "i", "n" }, "<Down>", function()
    selected = math.min(selected + 1, math.max(#results, 1))
    highlight_selected()
  end, p_opts)
  vim.keymap.set({ "i", "n" }, "<Up>", function()
    selected = math.max(selected - 1, 1)
    highlight_selected()
  end, p_opts)

  -- Live update as user types
  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer   = prompt_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, -1, false)
      local raw   = table.concat(lines, "")
      -- Strip prompt prefix character(s)
      local query = raw:match("^" .. vim.pesc(icons.search .. " ") .. "(.*)") or raw
      render_results(query)
    end,
  })

  render_results("")
  vim.cmd("startinsert!")
end

return M
