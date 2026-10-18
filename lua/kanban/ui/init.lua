-- Board controller: owns the cursor, maps keys on the column windows, and
-- routes actions to the board model and the views.
local board_view = require("kanban.ui.board_view")
local win_util   = require("kanban.ui.window")
local board_mod  = require("kanban.board")
local parser     = require("kanban.parser")
local util       = require("kanban.util")
local M = {}

M._state = { col_idx = 1, card_idx = 1 }
M._filepath = nil
M._keymaps_attached = {}
M._trap_augroup = nil
M._open_generation = 0

-- Keys that would edit the read-only board buffers and only produce errors
local EDITING_KEYS = {
  "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "cc", "cw", "r", "R",
  "v", "V", "<C-v>", "x", "X", "p", "P", "u", "<C-r>", ".", "~", "dd", "dw", "yy", "yw",
}

-- <leader> combos commonly mapped to window jumps, which would leave the board
local LEADER_SUFFIXES = { "h", "j", "k", "l", "H", "J", "K", "L", "w", "W", "p", "P", "v", "c", "r", "n", "b" }

vim.api.nvim_create_autocmd("VimLeavePre", {
  group    = vim.api.nvim_create_augroup("KanbanSaveOnExit", { clear = true }),
  callback = function()
    if board_mod.is_modified() then board_mod.save() end
  end,
})

local function cfg()
  return require("kanban").config
end

---@return table
local function board()
  return board_mod.get() --[[@as table]]
end

local function num_cards(col_idx)
  local col = board_mod.get_column(col_idx)
  return col and #col.cards or 0
end

local function focused_card()
  return board_mod.get_card(M._state.col_idx, M._state.card_idx)
end

local function notify(message)
  vim.notify("[kanban] " .. message, vim.log.levels.INFO)
end

local function clamp_state()
  M._state.col_idx = math.max(1, math.min(M._state.col_idx, board_mod.column_count()))
  local cards = num_cards(M._state.col_idx)
  M._state.card_idx = cards == 0 and 0 or math.max(1, math.min(M._state.card_idx, cards))
end

local function save_if_auto()
  if cfg().auto_save and board_mod.is_modified() then board_mod.save() end
end

local function render()
  clamp_state()
  board_view.refresh_all(board(), M._state)
  M._attach_keymaps()
end

local function render_column()
  board_view.refresh_column(board(), M._state.col_idx, M._state)
end

local function return_to_board(col_idx, card_idx)
  M._state = { col_idx = col_idx, card_idx = card_idx }
  M.open(M._filepath, { keep_state = true })
end

local actions = {}

-- Close the board for a popup and return a function that reopens it on the
-- card that was focused.
local function suspend_board()
  local col_idx, card_idx = M._state.col_idx, M._state.card_idx
  actions.close()
  return function() return_to_board(col_idx, card_idx) end
end

local function block_keys(buf, keys, allowed)
  for _, key in ipairs(keys) do
    if not allowed[key] then
      vim.keymap.set("n", key, function() end, { buffer = buf, noremap = true, silent = true, nowait = true })
    end
  end
end

local function confirm_delete_card(card)
  local prompt = "Delete card: \"" .. card.title .. "\""
  if card.note_file then prompt = prompt .. " and its note" end
  return vim.fn.confirm(prompt .. "?", "&Yes\n&No", 2) == 1
end

local function file_has_content(path)
  local content = util.read_file(path)
  return content ~= nil and not content:match("^%s*$")
end

-- Notes open in a float because the board is all floats: editing in the one
-- real window left behind would make :q on the note quit Neovim. Opening a
-- placeholder first and then :edit-ing lets filetype detection and BufRead
-- autocmds run as usual.
local function edit_in_float(path, title)
  local placeholder = vim.api.nvim_create_buf(false, true)
  vim.bo[placeholder].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(placeholder, true, {
    relative   = "editor",
    width      = vim.o.columns - 2,
    height     = vim.o.lines - 4,
    row        = 1,
    col        = 0,
    border     = cfg().popup.border,
    title      = " " .. title .. " ",
    title_pos  = "center",
    footer     = "  :w save & return  :q return  ",
    footer_pos = "right",
    zindex     = 200,
  })
  vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:KanbanPopupBorder"
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

-- Edit a card's note and return to the board when it is saved or closed. A
-- note with content is attached to the card; an empty one is deleted.
local function edit_card_note(col_idx, card_idx)
  local card = board_mod.get_card(col_idx, card_idx)
  if not card then return end
  local path = board_mod.note_path(card)
  edit_in_float(path, cfg().icons.note .. card.title)
  local note_buf = vim.api.nvim_get_current_buf()
  local note_win = vim.api.nvim_get_current_win()
  local finished = false

  local function finish()
    if finished then return end
    finished = true
    if not file_has_content(path) then
      if card.note_file then board_mod.detach_note(card) else os.remove(path) end
    elseif not card.note_file then
      board_mod.update_card(col_idx, card_idx, { note_file = path })
    end
    save_if_auto()
    -- Deleting the buffer from inside BufWritePost is unsafe
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(note_buf) then pcall(vim.api.nvim_buf_delete, note_buf, {}) end
      return_to_board(col_idx, card_idx)
    end)
  end

  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer   = note_buf,
    callback = function(event)
      -- `:w other.md` writes elsewhere and should not end the edit
      if vim.fn.fnamemodify(event.file, ":p") == vim.fn.fnamemodify(path, ":p") then finish() end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", { pattern = tostring(note_win), once = true, callback = finish })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, { buffer = note_buf, once = true, callback = finish })
end

-- ── Navigation ───────────────────────────────────────────────────────────────

local function focus_column(col_idx)
  if col_idx < 1 or col_idx > board_mod.column_count() then return end
  M._state.col_idx = col_idx
  render()
end

local function move_cursor(card_idx)
  local cards = num_cards(M._state.col_idx)
  if cards == 0 then return end
  M._state.card_idx = math.max(1, math.min(card_idx, cards))
  render_column()
end

function actions.next_column() focus_column(M._state.col_idx + 1) end
function actions.prev_column() focus_column(M._state.col_idx - 1) end
function actions.card_down()   move_cursor(M._state.card_idx + 1) end
function actions.card_up()     move_cursor(M._state.card_idx - 1) end
function actions.first_card()  move_cursor(1) end
function actions.last_card()   move_cursor(math.huge) end

-- ── Cards ────────────────────────────────────────────────────────────────────

local function reorder_card(delta)
  local col_idx, card_idx = M._state.col_idx, M._state.card_idx
  local target = card_idx + delta
  if card_idx == 0 or target < 1 or target > num_cards(col_idx) then return end
  M._state.card_idx = board_mod.move_card(col_idx, card_idx, col_idx, target) --[[@as integer]]
  save_if_auto()
  render_column()
end

local function move_card_to_column(delta)
  local from_col, to_col = M._state.col_idx, M._state.col_idx + delta
  if M._state.card_idx == 0 or not board_mod.get_column(to_col) then return end
  M._state = { col_idx = to_col, card_idx = board_mod.move_card(from_col, M._state.card_idx, to_col) }
  save_if_auto()
  render()
end

function actions.move_card_up()    reorder_card(-1) end
function actions.move_card_down()  reorder_card(1) end
function actions.move_card_right() move_card_to_column(1) end
function actions.move_card_left()  move_card_to_column(-1) end

function actions.toggle_done()
  if not focused_card() then return end
  board_mod.toggle_done(M._state.col_idx, M._state.card_idx)
  save_if_auto()
  render_column()
end

function actions.add_card()
  local col_idx = M._state.col_idx
  local resume = suspend_board()
  win_util.input_float({
    title       = cfg().icons.add .. " New card",
    placeholder = "title #tag1 #tag2 ...",
    border      = cfg().popup.border,
    zindex      = cfg().popup.zindex,
    on_confirm  = function(text)
      local title, tags = parser.split_tags(text)
      if title == "" then return resume() end
      local _, position = board_mod.add_card(col_idx, title, tags)
      save_if_auto()
      return_to_board(col_idx, position)
    end,
    on_cancel   = resume,
  })
end

function actions.edit_card()
  local card = focused_card()
  if not card then return end
  local col_idx, card_idx = M._state.col_idx, M._state.card_idx
  local default = card.title
  for _, tag in ipairs(card.tags) do default = default .. " #" .. tag end

  local resume = suspend_board()
  win_util.input_float({
    title       = cfg().icons.edit .. " Edit card",
    default     = default,
    placeholder = "title #tag1 #tag2 ...",
    border      = cfg().popup.border,
    zindex      = cfg().popup.zindex,
    on_confirm  = function(text)
      local title, tags = parser.split_tags(text)
      if title ~= "" then
        board_mod.update_card(col_idx, card_idx, { title = title, tags = tags })
        save_if_auto()
      end
      resume()
    end,
    on_cancel   = resume,
    on_empty    = function()
      if confirm_delete_card(card) then
        board_mod.delete_card(col_idx, card_idx)
        save_if_auto()
      end
      resume()
    end,
  })
end

local function delete_focused_card()
  board_mod.delete_card(M._state.col_idx, M._state.card_idx)
  save_if_auto()
  render()
end

function actions.force_delete_card()
  if focused_card() then delete_focused_card() end
end

function actions.delete_card()
  local card = focused_card()
  if card and confirm_delete_card(card) then delete_focused_card() end
end

function actions.archive_card()
  if not focused_card() then return end
  if board_mod.archive_card(M._state.col_idx, M._state.card_idx) then
    save_if_auto()
    render()
  end
end

function actions.set_due_date()
  local card = focused_card()
  if not card then return end
  local col_idx, card_idx = M._state.col_idx, M._state.card_idx
  require("kanban.ui.datepicker").open({
    current_date = card.due_date,
    on_confirm   = function(date)
      board_mod.set_due_date(col_idx, card_idx, date)
      save_if_auto()
      board_view.refresh_column(board(), col_idx, M._state)
    end,
  })
end

function actions.open_note()
  if not focused_card() then return end
  local col_idx, card_idx = M._state.col_idx, M._state.card_idx
  actions.close()
  edit_card_note(col_idx, card_idx)
end

function actions.open_card()
  if not focused_card() then return end
  local col_idx, card_idx = M._state.col_idx, M._state.card_idx
  local resume = suspend_board()

  local buf = win_util.scratch_buf()
  local win = vim.api.nvim_open_win(buf, true, {
    relative   = "editor",
    width      = vim.o.columns - 2,
    height     = vim.o.lines - 4,
    row        = 1,
    col        = 0,
    style      = "minimal",
    border     = cfg().popup.border,
    title      = " Card detail ",
    title_pos  = "center",
    footer     = "  [e] edit  [D] due  [n] note  [x] delete note  [q/<Esc>] close  ",
    footer_pos = "right",
    zindex     = 200,
  })
  vim.wo[win].winblend     = 100
  vim.wo[win].wrap         = false
  vim.wo[win].cursorline   = false
  vim.wo[win].winhighlight = "Normal:KanbanPopupNormal,FloatBorder:KanbanPopupBorder"
  local ns = vim.api.nvim_create_namespace("kanban_detail")

  local function render_detail()
    local card = board_mod.get_card(col_idx, card_idx) --[[@as table]]
    local lines = {
      "  " .. card.title,
      "",
      "  Column:   " .. board_mod.get_column(col_idx).name,
      "  Status:   " .. (card.done and "Done" or "In progress"),
    }
    if card.due_date then lines[#lines + 1] = "  Due:      " .. card.due_date end
    if #card.tags > 0 then lines[#lines + 1] = "  Tags:     " .. table.concat(card.tags, ", ") end
    if card.note_file then lines[#lines + 1] = "  Note:     " .. card.note_file end
    win_util.set_lines(buf, lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(buf, ns, "KanbanColumnHeader", 0, 0, -1)
  end

  local function close_detail()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local mappings = {
    q       = function() close_detail(); resume() end,
    ["<Esc>"] = function() close_detail(); resume() end,
    e       = function() close_detail(); resume(); actions.edit_card() end,
    D       = function() close_detail(); resume(); actions.set_due_date() end,
    n       = function() close_detail(); edit_card_note(col_idx, card_idx) end,
    x       = function()
      local card = board_mod.get_card(col_idx, card_idx) --[[@as table]]
      if not card.note_file then return end
      if vim.fn.confirm("Delete note file \"" .. card.note_file .. "\"?", "&Yes\n&No", 2) ~= 1 then return end
      board_mod.detach_note(card)
      save_if_auto()
      render_detail()
    end,
  }
  for key, action in pairs(mappings) do
    vim.keymap.set("n", key, action, { buffer = buf, noremap = true, silent = true, nowait = true })
  end
  block_keys(buf, EDITING_KEYS, mappings)
  render_detail()
end

-- ── Columns ──────────────────────────────────────────────────────────────────

function actions.add_column()
  local resume = suspend_board()
  win_util.small_input_float({
    title       = cfg().icons.add .. " New column",
    placeholder = "Column name ...",
    border      = cfg().popup.border,
    on_confirm  = function(name)
      local col_idx = board_mod.add_column(name)
      save_if_auto()
      return_to_board(col_idx, 0)
    end,
    on_cancel   = resume,
  })
end

function actions.rename_column()
  local col_idx = M._state.col_idx
  local resume = suspend_board()
  win_util.small_input_float({
    title       = cfg().icons.edit .. " Rename column",
    default     = board_mod.get_column(col_idx).name,
    placeholder = "Column name ...",
    border      = cfg().popup.border,
    on_confirm  = function(name)
      board_mod.rename_column(col_idx, name)
      save_if_auto()
      resume()
    end,
    on_cancel   = resume,
  })
end

function actions.delete_column()
  if board_mod.column_count() <= 1 then
    notify("Cannot delete the last column.")
    return
  end
  local col = board_mod.get_column(M._state.col_idx) --[[@as table]]
  if vim.fn.confirm("Delete column \"" .. col.name .. "\" and all its cards?", "&Yes\n&No", 2) ~= 1 then return end
  board_mod.delete_column(M._state.col_idx)
  save_if_auto()
  render()
end

local function move_column(delta)
  M._state.col_idx = board_mod.move_column(M._state.col_idx, delta)
  save_if_auto()
  render()
end

function actions.move_column_left()  move_column(-1) end
function actions.move_column_right() move_column(1) end

-- ── Board ────────────────────────────────────────────────────────────────────

function actions.search()
  require("kanban.ui.search").open(function(col_idx, card_idx)
    M._state = { col_idx = col_idx, card_idx = card_idx }
    render()
  end)
end

function actions.reload()
  board_mod.load(M._filepath)
  render()
  notify("Board reloaded.")
end

function actions.save()
  board_mod.save()
  notify("Board saved.")
end

function actions.close()
  board_view.close()
  M._keymaps_attached = {}
  if M._trap_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._trap_augroup)
    M._trap_augroup = nil
  end
end

-- True when a listed buffer other than the board file holds a file or unsaved text.
local function has_other_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= M._filepath and (name ~= "" or vim.bo[buf].modified) then return true end
    end
  end
  return false
end

function actions.quit()
  actions.close()
  if cfg().quit_on_close and not has_other_buffers() then vim.cmd("qa") end
end

function actions.open_source()
  local path = M._filepath --[[@as string]]
  local col_idx, card_idx = M._state.col_idx, M._state.card_idx
  if board_mod.is_modified() then board_mod.save() end
  actions.close()

  vim.g.kanban_suspend_autoopen = true
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.g.kanban_suspend_autoopen = nil
  local source_buf = vim.api.nvim_get_current_buf()

  local toggle_key = cfg().keymaps.open_source
  if toggle_key then
    vim.keymap.set("n", toggle_key, function()
      if vim.bo[source_buf].modified then vim.cmd("silent write") end
      win_util.delete_buf_keep_windows(source_buf)
    end, { buffer = source_buf, noremap = true, silent = true, desc = "Return to kanban board" })
  end

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    buffer   = source_buf,
    once     = true,
    callback = function()
      vim.schedule(function()
        M._state = { col_idx = col_idx, card_idx = card_idx }
        M.open(path, { keep_state = true, reload = true })
      end)
    end,
  })
end

function actions.help()
  require("kanban.ui.help").open(suspend_board())
end

-- ── Keymaps ──────────────────────────────────────────────────────────────────

local function action_for(keymap_name)
  if keymap_name == "close" or keymap_name == "close2" then return actions.quit end
  return actions[keymap_name]
end

-- Leader combos to block, skipping any that prefix one of the board's own keymaps
local function blocked_leader_combos(keymaps)
  local leader = vim.g.mapleader or "\\"
  local expanded_keys = {}
  for _, key in pairs(keymaps) do
    if key then
      expanded_keys[#expanded_keys + 1] = key:gsub("<[Ll]eader>", function() return leader end)
    end
  end
  local combos = {}
  for _, suffix in ipairs(LEADER_SUFFIXES) do
    local combo = leader .. suffix
    local prefixes_keymap = false
    for _, key in ipairs(expanded_keys) do
      if vim.startswith(key, combo) then prefixes_keymap = true end
    end
    if not prefixes_keymap then combos[#combos + 1] = combo end
  end
  return combos
end

function M._attach_keymaps()
  local keymaps = cfg().keymaps
  local mapped = {}
  for _, key in pairs(keymaps) do
    if key then mapped[key] = true end
  end
  local leader_combos = blocked_leader_combos(keymaps)

  for col_idx = 1, board_mod.column_count() do
    local entry = board_view.col_entry(col_idx)
    if entry and not M._keymaps_attached[entry.buf] then
      M._keymaps_attached[entry.buf] = true
      local map_opts = { buffer = entry.buf, noremap = true, silent = true, nowait = true }

      for keymap_name, key in pairs(keymaps) do
        local action = action_for(keymap_name)
        if key and action then
          vim.keymap.set("n", key, function()
            -- The window may have been focused by mouse rather than h/l
            M._state.col_idx = col_idx
            action()
          end, map_opts)
        end
      end
      block_keys(entry.buf, EDITING_KEYS, mapped)
      block_keys(entry.buf, leader_combos, {})
      vim.keymap.set("n", "ZZ", actions.close, map_opts)
      vim.keymap.set("n", "ZQ", actions.close, map_opts)

      vim.api.nvim_create_autocmd("WinEnter", {
        buffer   = entry.buf,
        callback = function()
          -- Focus passes through old column windows while the board is re-created
          if board_view.col_entry(col_idx) ~= entry or M._state.col_idx == col_idx then return end
          local previous = M._state.col_idx
          M._state.col_idx = col_idx
          board_view.refresh_column(board(), previous, M._state)
          board_view.refresh_column(board(), col_idx, M._state)
        end,
      })
      -- :q on one column closes the whole board
      vim.api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(entry.win),
        once     = true,
        callback = function()
          if board_view.is_open() then vim.schedule(actions.close) end
        end,
      })
    end
  end
end

-- ── Entry points ─────────────────────────────────────────────────────────────

--- Open a board. `keep_state` keeps the cursor and the loaded board (unless
--- `reload` is set) when reopening after a popup.
---@param filepath string|nil Defaults to .kanban/board.md in the cwd
---@param opts { keep_state: boolean?, reload: boolean? }|nil
function M.open(filepath, opts)
  opts = opts or {}
  if board_view.is_open() then
    board_view.focus_column(M._state.col_idx)
    return
  end

  filepath = vim.fn.fnamemodify(vim.fn.expand(filepath or ".kanban/board.md"), ":p")
  if not util.file_exists(filepath)
    and vim.fn.confirm("Board file not found: " .. filepath .. "\nCreate it?", "&Yes\n&No", 1) ~= 1 then
    return
  end
  util.ensure_dir(vim.fn.fnamemodify(filepath, ":h"))

  M._open_generation = M._open_generation + 1
  M._filepath = filepath
  -- Leave insert mode, which the input popups start
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  if not (opts.keep_state and not opts.reload and board_mod.is_loaded(filepath)) then
    board_mod.load(filepath)
  end
  if not opts.keep_state then M._state = { col_idx = 1, card_idx = 1 } end
  clamp_state()
  M._keymaps_attached = {}
  board_view.open(board(), M._state)
  M._attach_keymaps()

  -- Column windows are floats, so entering a non-float window means focus left the board
  local generation = M._open_generation
  M._trap_augroup = vim.api.nvim_create_augroup("KanbanFocusTrap", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group    = M._trap_augroup,
    callback = function()
      if not board_view.is_open() then return end
      if vim.api.nvim_win_get_config(0).relative ~= "" then return end
      vim.schedule(function()
        if M._open_generation == generation then actions.close() end
      end)
    end,
  })
end

function M.close()
  actions.quit()
end

---@param filepath string|nil
function M.toggle(filepath)
  if board_view.is_open() then M.close() else M.open(filepath) end
end

return M
