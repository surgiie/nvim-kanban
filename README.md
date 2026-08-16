# nvim-kanban

A minimal kanban board for Neovim.

![kantui overview](https://i.imgur.com/nbtuSK6.png)


## Requirements

- Neovim >= 0.9.0
- A [Nerd Font](https://www.nerdfonts.com/) for icons (optional but recommended)

## Installation

### lazy.nvim

```lua
{
  "surgiie/nvim-kanban",
  config = function()
    require("kanban").setup()
  end,
}
```

## Quick start

Press `<leader>kb` in any project directory. If `.kanban/board.md` does not exist you will be prompted to create it. The board opens automatically.

```
.kanban/
  board.md      ← board file
  notes/        ← per-card note files
```

Opening a `.md` or `.org` file that contains `kanban-plugin:` in its frontmatter will also trigger the board to open automatically. Press `<leader>kt` to toggle between the board view and the raw source file.

## Board format

Boards are standard Markdown files with a small frontmatter block:

```markdown
---
kanban-plugin: basic
---

## To Do

- [ ] Write tests #backend @due(2026-09-01)
- [x] Initial scaffolding #setup

## In Progress

- [ ] API redesign @due(2026-08-20) @note(.kanban/notes/api-redesign.md)

## Done
```

- `- [ ]` / `- [x]` — open / done card
- `#tag` — attach one or more tags
- `@due(YYYY-MM-DD)` — set a due date
- `@note(path)` — link a note file (managed automatically)

Org-mode files (`*.org`) are also supported.

## Notes

Each card can have one linked note file (a plain Markdown file in `.kanban/notes/`).

- Press `n` on a card (or inside the card detail popup) to open or create a note
- The note file is only attached to the card **after the buffer is saved with content** — closing an empty buffer does nothing and leaves no file behind
- If you save content and then delete all of it, closing the buffer removes the file and detaches it from the card automatically
- Delete a note from within the card detail popup with `x`

## Keymaps

### Global

| Key | Action |
|-----|--------|
| `<leader>kb` | Toggle board open / closed |

### Inside the board

#### Navigation

| Key | Action |
|-----|--------|
| `h` / `l` | Move to previous / next column |
| `j` / `k` | Move card cursor down / up |
| `gg` | Jump to first card |
| `G` | Jump to last card |

#### Card actions

| Key | Action |
|-----|--------|
| `o` | Open card detail popup |
| `a` | Add new card (supports inline `#tags`) |
| `e` | Edit card title and tags |
| `d` | Delete card (with confirmation) |
| `x` | Delete card (no confirmation) |
| `J` / `K` | Reorder card down / up within column |
| `<CR>` | Move card to next column |
| `<BS>` | Move card to previous column |
| `<Space>` | Toggle card done / undone |
| `n` | Open / create a note file for this card |
| `D` | Set or clear due date (calendar picker) |
| `A` | Archive card |

#### Card detail popup

| Key | Action |
|-----|--------|
| `e` | Edit card title / tags |
| `D` | Set due date |
| `n` | Open / create note file |
| `x` | Delete note file (with confirmation) |
| `q` / `<Esc>` | Close detail and return to board |

#### Column actions

| Key | Action |
|-----|--------|
| `C` | Add column |
| `R` | Rename column |
| `X` | Delete column and all its cards (with confirmation) |
| `H` / `L` | Reorder column left / right |

#### Board actions

| Key | Action |
|-----|--------|
| `/` | Live search across all cards |
| `r` | Reload board from disk |
| `<leader>ks` | Save board to disk |
| `<leader>kt` | Toggle between board and raw source file |
| `q` / `<Esc>` | Close board |
| `?` | Show help popup |

### Date picker

| Key | Action |
|-----|--------|
| `h` / `l` | Previous / next day |
| `j` / `k` | Previous / next week |
| `H` / `L` | Previous / next month |
| `<CR>` | Confirm selected date |
| `x` | Clear due date |
| `<Esc>` | Cancel |

## Configuration

Call `require("kanban").setup(opts)` with any of the following options. All are optional — the defaults are shown below.

```lua
require("kanban").setup({
  -- File format: "markdown" or "org" (nil = auto-detect from extension)
  format = nil,

  -- Global toggle keymap (set to false to disable)
  keymap = "<leader>kb",

  -- Board window size as a fraction of the terminal
  width  = 0.92,
  height = 0.85,

  -- Minimum column width in characters
  column_width = 28,

  -- Gap between columns in characters
  column_gap = 1,

  -- Save the board file after every change
  auto_save = true,

  -- Column name used for archived cards
  archive_column = "Archive",

  -- Directory for note files (nil = notes/ beside the board file)
  notes_dir = nil,

  -- Override any default keymap (set to false to disable it)
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
    edit_card         = "e",
    delete_card       = "d",    -- with confirmation; "x" always skips confirm
    archive_card      = "A",
    move_card_right   = "<CR>",
    move_card_left    = "<BS>",
    move_card_up      = "K",
    move_card_down    = "J",
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

  -- Popup window styling (input floats, detail popup)
  popup = {
    border = "rounded",
    width  = 60,
    height = 6,
    zindex = 100,
  },

  -- Date picker styling
  date_picker = {
    border = "rounded",
    width  = 34,
  },

  -- Override Nerd Font icons (set any to "" to hide)
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

  -- Override highlight groups (see :h nvim_set_hl for the attribute table format)
  highlights = {
    -- KanbanCardSelected = { bg = "#3d4220", bold = true },
  },
})
```

## Highlight groups

| Group | Default link | Used for |
|-------|-------------|----------|
| `KanbanNormal` | `NormalFloat` | Board window background |
| `KanbanBorder` | `FloatBorder` | Board outer border |
| `KanbanColumnHeader` | `Function` | Column title |
| `KanbanColumnBorder` | `FloatBorder` | Column separator line |
| `KanbanCard` | `Normal` | Card title |
| `KanbanCardDone` | `Comment` | Done card (strikethrough) |
| `KanbanCardSelected` | `Visual` | Focused card highlight |
| `KanbanTag` | `Special` | Tag text |
| `KanbanDueDate` | `WarningMsg` | Upcoming due date |
| `KanbanDueToday` | `WarningMsg` | Due date is today |
| `KanbanOverdue` | `ErrorMsg` | Past due date |
| `KanbanNote` | `Comment` | Note indicator |
| `KanbanHint` | `Comment` | Empty column hint / help text |
