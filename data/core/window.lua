local Object = require "core.object"
local RootView = require "core.rootview"
local CommandView = require "core.commandview"
local StatusView = require "core.statusview"
local NagView = require "core.nagview"
local TitleView = require "core.titleview"
local ime = require "core.ime"
local config = require "core.config"
local keymap = require "core.keymap"

local Window = Object:extend()

function Window:new(renwindow)
  self.renwindow = renwindow
  self.id = renwindow:get_id()
  self.mode = "normal"
  self.title = nil
  self.clip_rect_stack = {{ 0,0,0,0 }}
  self.active_view = nil
  self.last_active_view = nil
  ---@type core.rootview
  self.root_view = RootView(self)
  ---@type core.commandview
  self.command_view = CommandView(self)
  ---@type core.statusview
  self.status_view = StatusView(self)
  ---@type core.nagview
  self.nag_view = NagView(self)
  ---@type core.titleview
  self.title_view = TitleView(self)

  
  -- Some plugins (eg: console) require the nodes to be initialized to defaults
  local cur_node = self.root_view.root_node
  cur_node.is_primary_node = true
  cur_node:split("up", self.title_view, {y = true})
  cur_node = cur_node.b
  cur_node:split("up", self.nag_view, {y = true})
  cur_node = cur_node.b
  cur_node = cur_node:split("down", self.command_view, {y = true})
  cur_node = cur_node:split("down", self.status_view, {y = true})
end


local function get_title_filename(view)
  local doc_filename = view.get_filename and view:get_filename() or view:get_name()
  if doc_filename ~= "---" then return doc_filename end
  return ""
end


function Window:compose_window_title(title)
  return (title == "" or title == nil) and "Lite XL" or title .. " - Lite XL"
end

function Window:show_title_bar(show)
  self.title_view.visible = show
end

function Window:get_views_referencing_doc(doc)
  local res = {}
  local views = self.root_view.root_node:get_children()
  for _, view in ipairs(views) do
    if view.doc == doc then table.insert(res, view) end
  end
  return res
end


function Window:push_clip_rect(x, y, w, h)
  local x2, y2, w2, h2 = table.unpack(self.clip_rect_stack[#self.clip_rect_stack])
  local r, b, r2, b2 = x+w, y+h, x2+w2, y2+h2
  x, y = math.max(x, x2), math.max(y, y2)
  b, r = math.min(b, b2), math.min(r, r2)
  w, h = r-x, b-y
  table.insert(self.clip_rect_stack, { x, y, w, h })
  renderer.set_clip_rect(x, y, w, h)
end


function Window:pop_clip_rect()
  table.remove(self.clip_rect_stack)
  local x, y, w, h = table.unpack(self.clip_rect_stack[#self.clip_rect_stack])
  renderer.set_clip_rect(x, y, w, h)
end


function Window:set_active_view(view)
  assert(view, "Tried to set active view to nil")
  -- Reset the IME even if the focus didn't change
  ime.stop()
  if view ~= self.active_view then
    system.text_input(self.renwindow, view:supports_text_input())
    if self.active_view and self.active_view.force_focus then
      self.next_active_view = view
      return
    end
    self.next_active_view = nil
    if view.doc and view.doc.filename then
      self.set_visited(view.doc.filename)
    end
    self.last_active_view = self.active_view
    self.active_view = view
  end
end

function Window:update()
  local width, height = self.renwindow:get_size()
  -- update
  self.root_view.size.x, self.root_view.size.y = width, height
  self.root_view:update()
end

function Window:step()
  -- update window title
  local current_title = get_title_filename(self.active_view)
  if current_title ~= nil and current_title ~= self.title then
    self.renwindow:set_title(self.compose_window_title(current_title))
    self.title = current_title
  end
  -- draw
  renderer.begin_frame(self.renwindow)
  local width, height = self.renwindow:get_size()
  self.clip_rect_stack[1] = { 0, 0, width, height }
  renderer.set_clip_rect(table.unpack(self.clip_rect_stack[1]))
  self.root_view:draw()
  renderer.end_frame()
end

function Window:configure_borderless_window(borderless)
  self.renwindow:set_bordered(borderless)
  self.title_view:configure_hit_test(config.borderless)
  self.title_view.visible = config.borderless
end

function Window:on_event(type, ...)
  local did_keymap = false

  if type == "textinput" then
    self.root_view:on_text_input(...)
  elseif type == "textediting" then
    ime.on_text_editing(...)
  elseif type == "keypressed" then
    -- In some cases during IME composition input is still sent to us
    -- so we just ignore it.
    if ime.editing then return false end
    did_keymap = keymap.on_key_pressed(...)
  elseif type == "keyreleased" then
    keymap.on_key_released(...)
  elseif type == "mousemoved" then
    self.root_view:on_mouse_moved(...)
  elseif type == "mousepressed" then
    if not self.root_view:on_mouse_pressed(...) then
      did_keymap = keymap.on_mouse_pressed(...)
    end
  elseif type == "mousereleased" then
    self.root_view:on_mouse_released(...)
  elseif type == "mouseleft" then
    self.root_view:on_mouse_left()
  elseif type == "mousewheel" then
    if not self.root_view:on_mouse_wheel(...) then
      did_keymap = keymap.on_mouse_wheel(...)
    end
  elseif type == "touchpressed" then
    self.root_view:on_touch_pressed(...)
  elseif type == "touchreleased" then
    self.root_view:on_touch_released(...)
  elseif type == "touchmoved" then
    self.root_view:on_touch_moved(...)
  elseif type == "resized" then
    self.mode = self.renwindow:get_mode()
  elseif type == "minimized" or type == "maximized" or type == "restored" then
    self.mode = type == "restored" and "normal" or type
  elseif type == "filedropped" then
    self.root_view:on_file_dropped(...)
  elseif type == "focuslost" then
    self.root_view:on_focus_lost(...)
  end
  return did_keymap
end

return Window
