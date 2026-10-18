local M = {}

M.defaults = {
  -- Global keymap that toggles the board (false to disable)
  keymap = "<leader>kb",

  -- Board size as a fraction of the editor
  width  = 0.92,
  height = 0.85,

  -- Minimum column width; columns grow to fill the board
  column_width = 28,
  column_gap   = 1,

  -- Set any icon to "" to hide it
  icons = {
    card      = "󰆼 ",
    card_done = "󰄲 ",
    tag       = "󰓹 ",
    due       = "󰃰 ",
    overdue   = "󰃮 ",
    note      = "󰎞 ",
    column    = "󰙅 ",
    search    = "󰍉 ",
    add       = "󰐕 ",
    edit      = "󰏫 ",
  },

  -- Directory for note files (nil = notes/ beside the board file)
  notes_dir = nil,

  -- Save the board file after every change
  auto_save = true,

  -- Quit Neovim when the board closes and no other buffers with a file or
  -- unsaved text are open
  quit_on_close = true,

  -- Set any keymap to false to disable it
  keymaps = {
    next_column       = "l",
    prev_column       = "h",
    card_down         = "j",
    card_up           = "k",
    first_card        = "gg",
    last_card         = "G",

    open_card         = "o",
    add_card          = "a",
    edit_card         = "e",
    delete_card       = "d",
    force_delete_card = "x",
    archive_card      = "A",
    move_card_right   = "<CR>",
    move_card_left    = "<BS>",
    move_card_up      = "K",
    move_card_down    = "J",
    toggle_done       = "<Space>",
    open_note         = "n",
    set_due_date      = "D",

    add_column        = "C",
    rename_column     = "R",
    delete_column     = "X",
    move_column_left  = "H",
    move_column_right = "L",

    search            = "/",
    reload            = "r",
    save              = "<leader>ks",
    open_source       = "<leader>kt",
    close             = "q",
    close2            = "<Esc>",
    help              = "?",
  },

  popup = {
    border = "rounded",
    zindex = 100,
  },

  date_picker = {
    border = "rounded",
  },

  -- Column that archived cards are moved to (created on first use)
  archive_column = "Archive",

  -- Highlight group overrides, e.g. { KanbanCardSelected = { bg = "#3d4220" } }
  highlights = {},
}

---@param user_opts table|nil
---@return table
function M.merge(user_opts)
  return vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
