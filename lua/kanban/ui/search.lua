-- Live search across all cards: a prompt with a results list above it.
local win_util = require("kanban.ui.window")
local board    = require("kanban.board")
local util     = require("kanban.util")
local M = {}

local INSERT_HINT = "  <C-j>/<C-k> select  <CR> open  <Esc> normal mode  "
local NORMAL_HINT = "  j/k select  <CR> open  i type  <Esc> close  "

--- Open the search popup; `on_select` receives the chosen card's position.
---@param on_select fun(col_idx: integer, card_idx: integer)
function M.open(on_select)
  local config = require("kanban").config
  local icons  = config.icons
  local prompt = icons.search .. " "
  local width  = math.max(60, math.floor(vim.o.columns * 0.6))
  local results_height = math.min(15, math.floor(vim.o.lines * 0.4))
  local row = math.floor((vim.o.lines - results_height - 3) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  local ns  = vim.api.nvim_create_namespace("kanban_search")

  local results_buf = win_util.scratch_buf()
  local results_win = vim.api.nvim_open_win(results_buf, false, {
    relative  = "editor",
    width     = width,
    height    = results_height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = { "╭", "─", "╮", "│", "│", " ", "│", "│" },
    title     = " " .. prompt .. "Search cards ",
    title_pos = "center",
    zindex    = 100,
  })

  local prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype   = "prompt"
  vim.bo[prompt_buf].bufhidden = "wipe"
  vim.fn.prompt_setprompt(prompt_buf, prompt)
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative   = "editor",
    width      = width,
    height     = 1,
    row        = row + results_height,
    col        = col,
    style      = "minimal",
    border     = { "│", " ", "│", "│", "╰", "─", "╯", "│" },
    footer     = INSERT_HINT,
    footer_pos = "right",
    zindex     = 100,
  })
  vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
    buffer   = prompt_buf,
    callback = function(event)
      if not vim.api.nvim_win_is_valid(prompt_win) then return end
      local hint = event.event == "InsertEnter" and INSERT_HINT or NORMAL_HINT
      vim.api.nvim_win_set_config(prompt_win, { footer = hint, footer_pos = "right" })
    end,
  })

  for _, win in ipairs({ results_win, prompt_win }) do
    vim.wo[win].winhighlight = "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"
  end
  -- The prompt can blend into the background, but a fully blended results
  -- window would also hide the selected row's background highlight
  vim.wo[prompt_win].winblend  = 100
  vim.wo[results_win].winblend = 0
  vim.wo[results_win].wrap     = false

  local results, selected = {}, 1

  local function highlight_results()
    vim.api.nvim_buf_clear_namespace(results_buf, ns, 0, -1)
    for i, result in ipairs(results) do
      local group = i == selected and "KanbanCardSelected"
        or (result.card.done and "KanbanCardDone" or "KanbanCard")
      vim.api.nvim_buf_add_highlight(results_buf, ns, group, i - 1, 0, -1)
    end
    if results[selected] then
      vim.api.nvim_buf_set_extmark(results_buf, ns, selected - 1, 0, {
        virt_text     = { { "▶", "KanbanCardSelected" } },
        virt_text_pos = "overlay",
      })
    end
    if results[selected] then pcall(vim.api.nvim_win_set_cursor, results_win, { selected, 0 }) end
  end

  local function search(query)
    results, selected = board.search(query), 1
    local lines = {}
    for _, result in ipairs(results) do
      local card = result.card
      local line = string.format("  %s %-24s  %s%s",
        card.done and icons.card_done or icons.card,
        util.truncate(card.title, 28),
        icons.column,
        util.truncate(result.col_name, 16))
      if #card.tags > 0 then
        line = line .. "  " .. icons.tag .. table.concat(card.tags, " " .. icons.tag)
      end
      lines[#lines + 1] = line
    end
    win_util.set_lines(results_buf, #lines > 0 and lines or { "  (no results)" })
    highlight_results()
  end

  local function close()
    for _, win in ipairs({ prompt_win, results_win }) do
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
  end

  local function move_selection(delta)
    selected = math.max(1, math.min(selected + delta, #results))
    highlight_results()
  end

  local function open_selected()
    local result = results[selected]
    close()
    if result then on_select(result.col_idx, result.card_idx) end
  end
  local function map(modes, keys, action)
    for _, key in ipairs(keys) do
      vim.keymap.set(modes, key, action, { buffer = prompt_buf, noremap = true, silent = true, nowait = true })
    end
  end
  -- <Esc> in insert mode is left alone so it drops to normal mode, where
  -- j/k select and a second <Esc> closes
  map({ "i", "n" }, { "<CR>" }, open_selected)
  map({ "i", "n" }, { "<C-n>", "<Down>", "<Tab>", "<C-j>" }, function() move_selection(1) end)
  map({ "i", "n" }, { "<C-p>", "<Up>", "<S-Tab>", "<C-k>" }, function() move_selection(-1) end)
  map("n", { "j" }, function() move_selection(1) end)
  map("n", { "k" }, function() move_selection(-1) end)
  map("n", { "<Esc>", "q" }, close)
  map("n", { "<BS>" }, function() end)

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer   = prompt_buf,
    callback = function()
      local text = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ""
      search(text:sub(#prompt + 1))
    end,
  })

  search("")
  vim.cmd("startinsert!")
end

return M
