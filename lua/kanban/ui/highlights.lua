local M = {}

--- Define or redefine all KanbanXxx highlight groups.
--- User overrides from config.highlights are applied first; defaults link to standard groups.
---@param user_overrides table|nil Map of highlight group name → nvim_set_hl attribute table
function M.define(user_overrides)
  local set_hl = vim.api.nvim_set_hl
  user_overrides = user_overrides or {}

  -- Apply a highlight group, preferring the user override when present.
  local function set(name, defaults)
    if user_overrides[name] then
      set_hl(0, name, user_overrides[name])
    else
      set_hl(0, name, defaults)
    end
  end

  -- Window chrome
  set("KanbanNormal",        { link = "NormalFloat" })
  set("KanbanBorder",        { link = "FloatBorder" })
  set("KanbanCursorLine",    { link = "CursorLine" })
  set("KanbanTitle",         { link = "Title" })

  -- Column
  set("KanbanColumnHeader",  { bold = true, link = "Function" })
  set("KanbanColumnBorder",  { link = "FloatBorder" })
  set("KanbanColumnCount",   { link = "Comment" })

  -- Cards
  set("KanbanCard",          { link = "Normal" })
  set("KanbanCardDone",      { strikethrough = true, link = "Comment" })
  set("KanbanCardSelected",  { link = "Visual" })
  set("KanbanCardFocused",   { link = "CursorLine" })

  -- Metadata
  set("KanbanTag",           { link = "Special" })
  set("KanbanDueDate",       { link = "WarningMsg" })
  set("KanbanOverdue",       { bold = true, link = "ErrorMsg" })
  set("KanbanDueToday",      { bold = true, link = "WarningMsg" })
  set("KanbanNote",          { link = "Comment" })
  set("KanbanCheckbox",      { link = "Constant" })
  set("KanbanCheckboxDone",  { link = "Comment" })

  -- Popups
  set("KanbanPopupNormal",   { link = "NormalFloat" })
  set("KanbanPopupBorder",   { link = "FloatBorder" })
  set("KanbanPopupTitle",    { link = "FloatTitle" })

  -- Search
  set("KanbanSearchMatch",   { link = "Search" })

  -- Date picker
  set("KanbanCalHeader",     { bold = true, link = "Title" })
  set("KanbanCalDay",        { link = "Normal" })
  set("KanbanCalToday",      { bold = true, link = "WarningMsg" })
  set("KanbanCalSelected",   { link = "Visual" })
  set("KanbanCalWeekday",    { link = "Comment" })
  set("KanbanCalOtherMonth", { link = "NonText" })

  -- Status bar / footer hints
  set("KanbanHint",          { link = "Comment" })
  set("KanbanHintKey",       { link = "Special" })
end

return M
