-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local common = require "core.common"
local DocView = require "core.docview"
local Doc = require "core.doc"
local style = require "core.style"
local config = require "core.config"
local command = require "core.command"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"

config.plugins.linewrapping = {
	-- The type of wrapping to perform. Can be "letter" or "word".
  mode = "letter",
	-- If nil, uses the DocView's size, otherwise, uses this exact width.
  width_override = nil,
	-- Whether or not to draw a guide
  guide = true,
  -- Whether or not to enable wrapping by default when opening files.
  enable_by_default = false
}

local LineWrapping = {}

-- Computes the breaks for a given line, width and mode. Returns a list of columns
-- at which the line should be broken.
function LineWrapping.compute_line_breaks(doc, default_font, line, width, mode)
  local xoffset, last_i, i = 0, 1, 1
  local splits = { 1 }
  for _, type, text in doc.highlighter:each_token(line) do
    local font = style.syntax_fonts[type] or default_font
    local w = font:get_width(text)
    if xoffset + w > width then
      for char in common.utf8_chars(text) do
        w = font:get_width(char)
        xoffset = xoffset + w
        if xoffset > width then
          table.insert(splits, i)
          xoffset = w
        end
        i = i + #char
      end
    else
      xoffset = xoffset + w
      i = i + #text
    end
  end
  return splits
end

-- breaks are held in a single table that contains n*2 elements, where n is the amount of line breaks.
-- each element represents line and column of the break. line_offset will check from the specified line
-- if the first line has not changed breaks, it will stop there.
function LineWrapping.reconstruct_breaks(docview, default_font, width, line_offset)
  if width ~= math.huge then
    local doc = docview.doc
    docview.wrapped_lines = { }
    docview.wrapped_line_to_idx = { }
    docview.wrapped_settings = { ["width"] = width, ["font"] = default_font }
    for i = line_offset or 1, #doc.lines do
      for k, col in ipairs(LineWrapping.compute_line_breaks(doc, default_font, i, width, config.plugins.linewrapping.mode)) do
        table.insert(docview.wrapped_lines, i)
        table.insert(docview.wrapped_lines, col)
      end
    end
    -- list of indices for wrapped_lines, that are based on original line number
    -- holds the index to the first in the wrapped_lines list
    local last_wrap = nil
    for i = 1, #docview.wrapped_lines, 2 do
      if not last_wrap or last_wrap ~= docview.wrapped_lines[i] then
        table.insert(docview.wrapped_line_to_idx, (i + 1) / 2)
        last_wrap = docview.wrapped_lines[i]
      end
    end
  else
    docview.wrapped_lines = nil
    docview.wrapped_line_to_idx = nil
    docview.wrapped_settings = nil
  end
end

-- Updates the breaks for the various lines; with no extra new lines added.
function LineWrapping.update_breaks(docview, line)
  local idx = docview.wrapped_line_to_idx[line]
  local offset = (idx - 1) * 2 + 1
  local breaks = LineWrapping.compute_line_breaks(docview.doc, docview.wrapped_settings.font, line, docview.wrapped_settings.width, config.plugins.linewrapping.mode)
  local change = 0
  for i,b in ipairs(breaks) do
    if docview.wrapped_lines[offset] == line then
      docview.wrapped_lines[offset + 1] = b
    else
      table.insert(docview.wrapped_lines, offset, b)
      table.insert(docview.wrapped_lines, offset, line)
      change = change + 1
    end
    offset = offset + 2
  end
  while docview.wrapped_lines[offset] == line do
    table.remove(docview.wrapped_lines, offset)
    table.remove(docview.wrapped_lines, offset)
    change = change - 1
  end
  for i = line + 1, #docview.wrapped_line_to_idx do
    docview.wrapped_line_to_idx[i] = docview.wrapped_line_to_idx[i] + change
  end
end

-- Removes lines from the document, and thus breaks.
function LineWrapping.remove_lines(docview, line1, line2)
  local total_lines = line2 - line1 + 1
  local offset = (docview.wrapped_line_to_idx[line1] - 1) * 2 + 1
  for i=line1,line2 do
    table.remove(docview.wrapped_lines, offset)
    table.remove(docview.wrapped_lines, offset)
  end
  for i = line2 + 1, #docview.wrapped_line_to_idx do
    docview.wrapped_line_to_idx[i] = docview.wrapped_line_to_idx[i] - total_lines
  end
  for i=line1, line2 do
    table.remove(docview.wrapped_line_to_idx, line1)
  end
end

-- Adds lines to the document, and thus breaks.
function LineWrapping.add_lines(docview, line, line_count) 
  local offset = (docview.wrapped_line_to_idx[line] - 1) * 2 + 1
  for i = line, line + line_count - 1 do
    table.insert(docview.wrapped_lines, offset, 1)
    table.insert(docview.wrapped_lines, offset, i)
    table.insert(docview.wrapped_line_to_idx, line, ((offset - 1) / 2) + 1)
    offset = offset + 2
  end
  for i = line + line_count, #docview.wrapped_line_to_idx do
    docview.wrapped_line_to_idx[i] = docview.wrapped_line_to_idx[i] + line_count
  end
  for i = offset, #docview.wrapped_lines, 2 do
    docview.wrapped_lines[i] = docview.wrapped_lines[i] + line_count
  end
end

-- Draws a guide if applicable to show where wrapping is occurring.
function LineWrapping.draw_guide(docview)
  if config.plugins.linewrapping.guide and docview.wrapped_settings.width ~= math.huge then
    local x, y = docview:get_content_offset()
    local gw = docview:get_gutter_width()
    renderer.draw_rect(x + gw + docview.wrapped_settings.width, y, 1, core.root_view.size.y, style.selection)
  end
end

function LineWrapping.update_docview_breaks(docview)
  local width = config.plugins.linewrapping.width_override or (docview.size.x - docview:get_gutter_width())
  if (not docview.wrapped_settings or docview.wrapped_settings.width == nil or width ~= docview.wrapped_settings.width) then
    docview.scroll.to.x = 0
    LineWrapping.reconstruct_breaks(docview, docview:get_font(), width)
  end
end

local function get_idx_line_col(docview, idx)
  local doc = docview.doc
  if not docview.wrapped_settings then 
    if idx > #doc.lines then return #doc.lines, #doc.lines[#doc.lines] + 1 end
    return idx, 1 
  end
  local offset = (idx - 1) * 2 + 1
  if offset > #docview.wrapped_lines then return #doc.lines, #doc.lines[#doc.lines] + 1 end
  return docview.wrapped_lines[offset], docview.wrapped_lines[offset + 1]
end

local function get_idx_line_length(docview, idx)
  local doc = docview.doc
  if not docview.wrapped_settings then 
    if idx > #doc.lines then return #doc.lines[#doc.lines] + 1 end
    return #doc.lines[idx]
  end
  local offset = (idx - 1) * 2 + 1
  local start = docview.wrapped_lines[offset + 1]
  if docview.wrapped_lines[offset + 2] and docview.wrapped_lines[offset + 2] == docview.wrapped_lines[offset] then
    return docview.wrapped_lines[offset + 3] - docview.wrapped_lines[offset + 1]
  else
    return #doc.lines[docview.wrapped_lines[offset]] - docview.wrapped_lines[offset + 1] + 1
  end
end

local function get_total_wrapped_lines(docview)
  if not docview.wrapped_settings then return docview.doc and #docview.doc.lines end
  return #docview.wrapped_lines / 2
end

-- If line end, gives the end of an index line, rather than the first character of the next line.
local function get_line_idx_col_count(docview, line, col, line_end, ndoc)
  local doc = docview.doc
  if not docview.wrapped_settings then return common.clamp(line, 1, #doc.lines), col, 1, 1 end
  if line > #doc.lines then return get_line_idx_col_count(docview, #doc.lines, #doc.lines[#doc.lines] + 1) end
  line = math.max(line, 1)
  local idx = docview.wrapped_line_to_idx[line] or 1
  local ncol, scol = 1, 1
  if col then
    local i = idx + 1
    while line == docview.wrapped_lines[(i - 1) * 2 + 1] and col >= docview.wrapped_lines[(i - 1) * 2 + 2] do
      local nscol = docview.wrapped_lines[(i - 1) * 2 + 2]
      if line_end and col == nscol then
        break
      end
      scol = nscol
      i = i + 1
      idx = idx + 1
    end
    ncol = (col - scol) + 1
  end
  local count = (docview.wrapped_line_to_idx[line + 1] or (get_total_wrapped_lines(docview) + 1)) - (docview.wrapped_line_to_idx[line] or get_total_wrapped_lines(docview))
  return idx, ncol, count, scol
end


local function get_line_col_from_index_and_x(docview, idx, x)
  local doc = docview.doc
  local line, col = get_idx_line_col(docview, idx)
  local xoffset, last_i, i = 0, 1, 1
  local default_font = docview:get_font()
  for _, type, text in docview.doc.highlighter:each_token(line) do
    local font = style.syntax_fonts[type] or default_font
    for char in common.utf8_chars(text) do
      if i > col then
        local w = font:get_width(char)
        if xoffset + w >= x then
          return line, ((xoffset - x > w / 2) and last_i or i)
        end
        xoffset = xoffset + w
      end
      last_i = i
      i = i + #char
    end
  end
  return line, #doc.lines[line]
end


local open_files = {}

local old_doc_insert = Doc.raw_insert
function Doc:raw_insert(line, col, text, undo_stack, time)
  local old_lines = #self.lines
  old_doc_insert(self, line, col, text, undo_stack, time)
  if open_files[self] then
    for i,docview in ipairs(open_files[self]) do
      if docview.wrapped_settings then
        local lines = #self.lines - old_lines
        if lines > 0 then LineWrapping.add_lines(docview, line, lines) end
        LineWrapping.update_breaks(docview, line)
      end
    end
  end
end

local old_doc_remove = Doc.raw_remove
function Doc:raw_remove(line1, col1, line2, col2, undo_stack, time)
  local start_line = line1 + 1
  local end_line = col2 == #self.lines[line2] and line2 or (line2 - 1)
  old_doc_remove(self, line1, col1, line2, col2, undo_stack, time)
  if open_files[self] then
    for i,docview in ipairs(open_files[self]) do
      if docview.wrapped_settings then
        if start_line <= end_line then
          LineWrapping.remove_lines(start_line, end_line)
        end
        LineWrapping.update_breaks(docview, line1)
      end
    end
  end
end

local old_doc_update = DocView.update
function DocView:update()
  old_doc_update(self)
  if self.wrapped_settings and self.size.x > 0 then
    LineWrapping.update_docview_breaks(self)
  end
end

function DocView:get_scrollable_size()
  if not config.scroll_past_end then
    return self:get_line_height() * get_total_wrapped_lines(self) + style.padding.y * 2
  end
  return self:get_line_height() * (get_total_wrapped_lines(self) - 1) + self.size.y
end

local old_new = DocView.new
function DocView:new(doc)
  old_new(self, doc)
  if not open_files[doc] then open_files[doc] = {} end
  table.insert(open_files[doc], self)
  if config.plugins.linewrapping.enable_by_default then
    LineWrapping.update_docview_breaks(self)
  end
end

local old_scroll_to_make_visible = DocView.scroll_to_make_visible
function DocView:scroll_to_make_visible(line, col)
  old_scroll_to_make_visible(self, line, col)
  if self.wrapped_settings then self.scroll.to.x = 0 end
end

local old_get_visible_line_range = DocView.get_visible_line_range
function DocView:get_visible_line_range()
  if not self.wrapped_settings then return old_get_visible_line_range(self) end
  local x, y, x2, y2 = self:get_content_bounds()
  local lh = self:get_line_height()
  local minline = get_idx_line_col(self, math.max(1, math.floor(y / lh)))
  local maxline = get_idx_line_col(self, math.min(get_total_wrapped_lines(self), math.floor(y2 / lh) + 1))
  return minline, maxline
end

local old_get_x_offset_col = DocView.get_x_offset_col
function DocView:get_x_offset_col(line, x)
  if not self.wrapped_settings then return old_get_x_offset_col(self, line, x) end
  local idx = get_line_idx_col_count(self, line)
  return get_line_col_from_index_and_x(self, idx, x)
end

-- If line end is true, returns the end of the previous line, in a multi-line break.
local old_get_col_x_offset = DocView.get_col_x_offset
function DocView:get_col_x_offset(line, col, line_end)
  if not self.wrapped_settings then return old_get_col_x_offset(self, line, col) end
  local idx, ncol, count, scol = get_line_idx_col_count(self, line, col, line_end)
  local xoffset, i = 0, 1
  local default_font = self:get_font()
  for _, type, text in self.doc.highlighter:each_token(line) do
    if i + #text >= scol then   
      if i < scol then 
        text = text:sub(scol - i + 1)
        i = scol
      end
      local font = style.syntax_fonts[type] or default_font
      for char in common.utf8_chars(text) do
        if i >= col then
          return xoffset
        end
        xoffset = xoffset + font:get_width(char)
        i = i + #char
      end
    else
     i = i + #text
    end
  end
  return xoffset
end

local old_get_line_screen_position = DocView.get_line_screen_position
function DocView:get_line_screen_position(line, col)
  if not self.wrapped_settings then return old_get_line_screen_position(self, line, col) end
  local idx, ncol, count = get_line_idx_col_count(self, line, col)
  local x, y = self:get_content_offset()
  local lh = self:get_line_height()
  local gw = self:get_gutter_width()
  return x + gw + (col and self:get_col_x_offset(line, col) or 0), y + (idx-1) * lh + style.padding.y
end

local old_resolve_screen_position = DocView.resolve_screen_position
function DocView:resolve_screen_position(x, y)
  if not self.wrapped_settings then return old_resolve_screen_position(self, x, y) end
  local ox, oy = self:get_line_screen_position(1)
  local idx = common.clamp(math.floor((y - oy) / self:get_line_height()) + 1, 1, get_total_wrapped_lines(self))
  return get_line_col_from_index_and_x(self, idx, x - ox)
end

local old_draw_line_text = DocView.draw_line_text
function DocView:draw_line_text(line, x, y)
  if not self.wrapped_settings then return old_draw_line_text(self, line, x, y) end
  local default_font = self:get_font()
  local tx, ty = x, y + self:get_line_text_y_offset()
  local lh = self:get_line_height()
  local idx, _, count = get_line_idx_col_count(self, line)
  local total_offset = 1
  for _, type, text in self.doc.highlighter:each_token(line) do
    local color = style.syntax[type]
    local font = style.syntax_fonts[type] or default_font
    local token_offset = 1
    -- Split tokens if we're at the end of the document.
    while token_offset <= #text do
      local next_line, next_line_start_col = get_idx_line_col(self, idx + 1)
      if next_line ~= line then
        next_line_start_col = #self.doc.lines[line] 
      end
      local max_length = next_line_start_col - total_offset
      local rendered_text = text:sub(token_offset, token_offset + max_length - 1)
      tx = renderer.draw_text(font, rendered_text, tx, ty, color)
      total_offset = total_offset + #rendered_text
      if total_offset ~= next_line_start_col or max_length == 0 then break end
      token_offset = token_offset + #rendered_text
      idx = idx + 1
      tx, ty = x, ty + lh
    end
  end
  return lh * count
end

local old_draw_line_body = DocView.draw_line_body
function DocView:draw_line_body(line, x, y)
  if not self.wrapped_settings then return old_draw_line_body(self, line, x, y) end
  local lh = self:get_line_height()
  local idx0 = get_line_idx_col_count(self, line)
  for lidx, line1, col1, line2, col2 in self.doc:get_selections(true) do
    if line >= line1 and line <= line2 then
      if line1 ~= line then col1 = 1 end
      if line2 ~= line then col2 = #self.doc.lines[line] + 1 end
      if col1 ~= col2 then
        local idx1, ncol1 = get_line_idx_col_count(self, line, col1)
        local idx2, ncol2 = get_line_idx_col_count(self, line, col2)
        for i = idx1, idx2 do
          local x1, x2 = x + (idx1 == i and self:get_col_x_offset(line1, col1) or 0)
          if idx2 == i then
            x2 = x + self:get_col_x_offset(line, col2)
          else
            x2 = x + self:get_col_x_offset(line, get_idx_line_length(self, i, line) + 1, true)
          end
          renderer.draw_rect(x1, y + (i - idx0) * lh, x2 - x1, lh, style.selection)
        end
      end
    end
  end
  local draw_highlight = nil
  for lidx, line1, col1, line2, col2 in self.doc:get_selections(true) do
    -- draw line highlight if caret is on this line
    if draw_highlight ~= false and config.highlight_current_line
    and line1 == line and core.active_view == self then
      draw_highlight = (line1 == line2 and col1 == col2)
    end
  end
  if draw_highlight then 
    local _, _, count = get_line_idx_col_count(self, line)
    for i=1,count do 
      self:draw_line_highlight(x + self.scroll.x, y + lh * (i - 1))
    end
  end
  -- draw line's text
  return self:draw_line_text(line, x, y)
end

local old_draw = DocView.draw
function DocView:draw()
  old_draw(self)
  if self.wrapped_settings then
    LineWrapping.draw_guide(self) 
  end
end 

local old_draw_line_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(line, x, y, width)
  local lh = self:get_line_height()
  local _, _, count = get_line_idx_col_count(self, line)
  return (old_draw_line_gutter(self, line, x, y, width) or lh) * count
end

local old_translate_end_of_line = translate.end_of_line
function translate.end_of_line(doc, line, col)
  if not core.active_view or core.active_view.doc ~= doc or not core.active_view.wrapped_settings then old_translate_end_of_line(doc, line, col) end
  local idx, ncol = get_line_idx_col_count(core.active_view, line, col)
  local nline, ncol2 = get_idx_line_col(core.active_view, idx + 1)
  if nline ~= line then return line, math.huge end
  return line, ncol2 - 1
end

local old_translate_start_of_line = translate.start_of_line
function translate.start_of_line(doc, line, col)
  if not core.active_view or core.active_view.doc ~= doc or not core.active_view.wrapped_settings then old_translate_start_of_line(doc, line, col) end
  local idx, ncol = get_line_idx_col_count(core.active_view, line, col)
  local nline, ncol2 = get_idx_line_col(core.active_view, idx - 1)
  if nline ~= line then return line, 1 end
  return line, ncol2 + 1
end

local old_previous_line = DocView.translate.previous_line
function DocView.translate.previous_line(doc, line, col, dv)
  if not dv.wrapped_settings then return old_previous_line(doc, line, col, dv) end
  local idx, ncol = get_line_idx_col_count(dv, line, col)
  return get_line_col_from_index_and_x(dv, idx - 1, dv:get_col_x_offset(line, col))
end

local old_next_line = DocView.translate.next_line
function DocView.translate.next_line(doc, line, col, dv)
  if not dv.wrapped_settings then return old_next_line(doc, line, col, dv) end
  local idx, ncol = get_line_idx_col_count(dv, line, col)
  return get_line_col_from_index_and_x(dv, idx + 1, dv:get_col_x_offset(line, col))
end

command.add(nil, {
  ["line-wrapping:enable"] = function() 
    if core.active_view and core.active_view.doc then 
      LineWrapping.update_docview_breaks(core.active_view)
    end
  end,
  ["line-wrapping:disable"] = function() 
    if core.active_view and core.active_view.doc then 
      LineWrapping.reconstruct_breaks(core.active_view, core.active_view:get_font(), math.huge)
    end
  end,
  ["line-wrapping:toggle"] = function() 
    if core.active_view and core.active_view.doc and core.active_view.wrapped_settings then 
      command.perform("line-wrapping:disable")
    else
      command.perform("line-wrapping:enable")
    end
  end
})

keymap.add {
  ["f10"] = "line-wrapping:toggle",
}

return LineWrapping
