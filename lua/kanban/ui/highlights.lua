local M = {}

local defaults = {
  KanbanNormal       = { link = "NormalFloat" },
  KanbanBorder       = { link = "FloatBorder" },
  KanbanCursorLine   = { link = "CursorLine" },

  KanbanColumnHeader = { bold = true, link = "Function" },
  KanbanColumnBorder = { link = "FloatBorder" },

  KanbanCard         = { link = "Normal" },
  KanbanCardDone     = { strikethrough = true, link = "Comment" },
  KanbanCardSelected = { link = "Visual" },

  KanbanTag          = { link = "Special" },
  KanbanDueDate      = { link = "WarningMsg" },
  KanbanDueToday     = { bold = true, link = "WarningMsg" },
  KanbanOverdue      = { bold = true, link = "ErrorMsg" },
  KanbanNote         = { link = "Comment" },

  KanbanPopupNormal  = { link = "NormalFloat" },
  KanbanPopupBorder  = { link = "FloatBorder" },

  KanbanCalHeader    = { bold = true, link = "Title" },
  KanbanCalWeekday   = { link = "Comment" },
  KanbanCalDay       = { link = "Normal" },
  KanbanCalToday     = { bold = true, link = "WarningMsg" },
  KanbanCalSelected  = { link = "Visual" },

  KanbanHint         = { link = "Comment" },
  KanbanHintKey      = { link = "Special" },
}

---@param overrides table<string, table>|nil Group name to nvim_set_hl attributes
function M.define(overrides)
  overrides = overrides or {}
  for name, attributes in pairs(defaults) do
    vim.api.nvim_set_hl(0, name, overrides[name] or attributes)
  end
end

return M
