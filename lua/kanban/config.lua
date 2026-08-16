local M = {}

M.defaults = {
  -- "markdown" or "org" — auto-detected from extension when nil
  format = nil,

  -- Global keymap to toggle the default board (set to false to disable)
  keymap = "<leader>kb",

  -- Board width as a fraction of terminal width (1.0 = full width, evenly split)
  width = 0.92,
  height = 0.85,

  -- Minimum column width in characters (columns expand to fill board_width evenly)
  column_width = 28,

  -- Minimum gap between columns
  column_gap = 1,

  -- Icons shown in various places (set to "" to hide)
  icons = {
    card        = "󰆼 ",
    card_done   = "󰄲 ",
    tag         = "󰓹 ",
    due         = "󰃰 ",
    overdue     = "󰃮 ",
    note        = "󰎞 ",
    checkbox    = "󰄱 ",
    checked     = "󰄲 ",
    column      = "󰙅 ",
    archive     = "󰀼 ",
    search      = "󰍉 ",
    add         = "󰐕 ",
    delete      = "󰆴 ",
    edit        = "󰏫 ",
    move        = "󰁙 ",
    calendar    = "󰃭 ",
  },

  -- Note files directory (nil = same dir as board file)
  notes_dir = nil,

  -- Auto-save board after every change
  auto_save = true,

  -- Keymaps (set any to false to disable)
  keymaps = {
    -- Navigation
    next_column       = "l",
    prev_column       = "h",
    card_down         = "j",
    card_up           = "k",
    first_card        = "gg",
    last_card         = "G",

    -- Card actions
    open_card         = "o",
    add_card          = "a",
    move_card_up      = "K",
    move_card_down    = "J",
    edit_card         = "e",
    delete_card       = "d",
    archive_card      = "A",
    move_card_right   = "<CR>",
    move_card_left    = "<BS>",
    toggle_done       = "<Space>",
    open_note         = "n",
    set_due_date      = "D",

    -- Column actions
    add_column        = "C",
    rename_column     = "R",
    delete_column     = "X",
    move_column_left  = "H",
    move_column_right = "L",

    -- Board actions
    search            = "/",
    reload            = "r",
    save              = "<leader>ks",
    open_source       = "<leader>kt",
    close             = "q",
    close2            = "<Esc>",
    help              = "?",
  },

  -- Popup styling (for input, date picker, etc.)
  popup = {
    border  = "rounded",
    width   = 60,
    height  = 6,
    zindex  = 100,
  },

  -- Date picker settings
  date_picker = {
    border = "rounded",
    width  = 34,
  },

  -- Archive column name (cards moved here are "archived")
  archive_column = "Archive",

  -- Highlight group overrides (empty = use defaults linked to built-in groups)
  highlights = {},
}

--- Merge user options over the plugin defaults.
---@param user_opts table|nil User-supplied configuration table
---@return table Merged configuration
function M.merge(user_opts)
  local merged = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
  return merged
end

--- Detect the board format ("markdown" or "org") from the file extension.
---@param filepath string|nil Path to the board file
---@return string Format name: "markdown" or "org"
function M.detect_format(filepath)
  if not filepath then return "markdown" end
  local ext = filepath:match("%.([^%.]+)$")
  if ext == "org" then return "org" end
  return "markdown"
end

return M
