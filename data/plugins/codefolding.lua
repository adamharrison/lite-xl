-- mod-version:3
local core = require "core"
local config = require "core.config"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"
local Node = require "core.node"
local common = require "core.common"


function DocView:is_folded(doc_line)
  return self.folded[doc_line+1]
end

local old_docview_new = DocView.new
function DocView:new(...)
  self.folded = {}
  self.foldable = {}
  return old_docview_new(self, ...)
end

function DocView:compute_fold(doc_line)
  local start_of_computation = doc_line
  for i = doc_line - 1, 1, -1 do
    if self.foldable[i] then break end
    start_of_computation = i
  end
  for i = start_of_computation, doc_line do
    if i > 1 then
      local origin = self.foldable[i - 1]
      if self.doc.lines[i-1]:find("{%s*$") then
        origin = origin + 1
      elseif self.doc.lines[i-1]:find("}%s*$") and not self.doc.lines[i-1]:find("^%s* }%s*$") then
        origin = origin - 1
      end
      if self.doc.lines[i]:find("^%s*}") then
        origin = origin - 1
      end
      self.foldable[i] = origin
    else
      self.foldable[i] = 0
    end
  end
end

local old_tokenize = DocView.tokenize
function DocView:tokenize(line)
  local tokens = old_tokenize(self, line)
  if not self.foldable then return tokens end
  self:compute_fold(line)
  if self.folded[line] then return {} end
  if self:is_foldable(line) and self.folded[line+1] then
    -- remove the newline from the end of the tokens
    local type, line, e = tokens[#tokens - 4], tokens[#tokens - 3], tokens[#tokens - 1]
    if type == "doc" and self.doc.lines[line]:sub(e, e) == "\n" then tokens[#tokens - 1] = tokens[#tokens - 1] - 1 end
    table.insert(tokens, "virtual")
    table.insert(tokens, line)
    table.insert(tokens, " ... ")
    table.insert(tokens, false)
    table.insert(tokens, { color = style.dim })
    table.insert(tokens, "virtual")
    table.insert(tokens, line)
    table.insert(tokens, "}\n")
    table.insert(tokens, false)
    table.insert(tokens, {  })
  end
  return tokens
end

function DocView:is_foldable(line)
  if line < #self.doc.lines then
    if not self.foldable[line] or not self.foldable[line+1] then self:compute_fold(line+1) end
    return self.foldable[line] and self.foldable[line+1] > self.foldable[line]
  end
  return false
end

function DocView:toggle_fold(start_doc_line, value)
  if self:is_foldable(start_doc_line) then
    if value == nil then value = not self:is_folded(start_doc_line) end
    local starting_fold = self.foldable[start_doc_line]
    local end_doc_line = start_doc_line + 1
    while end_doc_line <= #self.doc.lines do
      self:compute_fold(end_doc_line+1) 
      if self.foldable[end_doc_line] <= starting_fold then
        if self.doc.lines[end_doc_line]:find("}%s*$") then self.folded[end_doc_line] = value end
        break
      end
      self.folded[end_doc_line] = value
      end_doc_line = end_doc_line + 1
    end
    self:invalidate_cache(start_doc_line, end_doc_line)
  end
end


local old_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local x,y = old_get_gutter_width(self)
  return x + style.padding.x, y
end

local old_draw_line_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(line, x, y, width)
  local lh = old_draw_line_gutter(self, line, x, y, width)
  local size = lh - 4
  local startx = x + 4
  local starty = y + (lh - size) / 2
  if self:is_foldable(line) then
    renderer.draw_rect(startx, starty, size, size, style.accent)
    renderer.draw_rect(startx + 1, starty + 1, size - 2, size - 2, self.hovering_foldable == line and style.dim or style.background)
    common.draw_text(self:get_font(), style.accent, self:is_folded(line) and "+" or "-", "center", startx, starty, size, size)
  end
  -- common.draw_text(self:get_font(), style.accent, self.foldable[line] or "nil", "center", startx, starty, size, size)
  return lh
end

local old_mouse_moved = DocView.on_mouse_moved
function DocView:on_mouse_moved(x, y, ...)
  old_mouse_moved(self, x, y, ...)
  self.hovering_foldable = false
  if self.hovering_gutter then
    local line = self:resolve_screen_position(x, y)
    if self:is_foldable(line) then
      self.hovering_foldable = line
      self.cursor = "hand"
    end
  end
end

local old_mouse_pressed = DocView.on_mouse_pressed
function DocView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" and self.hovering_foldable then
    self:toggle_fold(self.hovering_foldable)
  end
  return old_mouse_pressed(button, x, y, clicks)
end
