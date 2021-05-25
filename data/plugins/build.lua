-- mod-version:1 -- lite-xl 1.16
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local config = require "core.config"
local common = require "core.common"
local process = require "core.process"
local style = require "core.style"
local View = require "core.view"
local DocView = require "core.docview"
local StatusView = require "core.statusview"

local build = {
  targets = { },
  current_target = 1,
  threads = 8,
  error_pattern = "^%s*([^:]+):(%d+):(%d+): (%w+): (.+)",
  running_program = nil,
  -- Config variables
  interval = 0.1,
  drawer_size = 100
}

style.error_line = { common.color "#8c2a2b" }


local function jump_to_file(file, line, col)
  if not core.active_view or not core.active_view.doc or core.active_view.doc.abs_filename ~= file then
    -- Check to see if the file is in the project. If it is, open it, and go to the line.
    for i = 1, #core.project_directories do
      if common.path_belongs_to(file, core.project_dir) then
        local view = core.root_view:open_doc(core.open_doc(file))
        if line then
          view:scroll_to_line(math.max(1, line - 20), true)
          view.doc:set_selection(line, col or 1, line, col or 1)
        end
        break
      end
    end
  end
end

local function run_command(cmd, on_line, on_done)
  core.add_thread(function()
    build.running_program = process.popen(unpack(cmd))
    local result = ""
    while result ~= nil do
      result = build.running_program:read()
      if result ~= nil then
        local offset = 1
        while offset < #result do
          local newline = result:find("\n", offset) or #result
          if on_line then
            on_line(result:sub(offset, newline-1))
          end
          offset = newline + 1
        end
        coroutine.yield(build.interval)
      end
    end
    if on_done then
      on_done()
    end
  end)
end

function build.set_targets(targets)
  build.targets = targets
  config.target_binary = build.targets[1].binary
end

function build.output(line)
  core.log(line)
end

function build.build(target)
  build.message_view:clear_messages()
  build.message_view.visible = true
  local target = build.current_target
  run_command({ "make", build.targets[target].name, "-j", build.threads, "--quiet" }, function(line)
    local _, _, file, line_number, column, type, message = line:find(build.error_pattern)
    if file and (type == "warning" or type == "error") then
      build.message_view:add_message({ type, file, line_number, column, message })
    end
  end, function()
    build.message_view.visible = #build.message_view.messages > 0
    build.output("Completed building " .. (build.targets[target].binary or "target") .. ". " .. #build.message_view.messages .. " Errors/Warnings.")
  end)
end

function build.clean()
  build.message_view.clear_messages()
  run_command({ "make", "clean" })
end


------------------ UI Elements
local status_view_get_items = StatusView.get_items
function StatusView:get_items()
  local left, right = status_view_get_items(self)
  if #build.targets > 0 then
    table.insert(right, 1, self.separator2)
    table.insert(right, 1, "target: " .. build.targets[build.current_target].name)
  end
  return left, right
end

local doc_view_draw_line_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(idx, x, y)
  if self.doc.abs_filename == build.message_view.active_file 
    and build.message_view.active_message
    and idx == build.message_view.active_line
  then
    renderer.draw_rect(x, y, self:get_gutter_width(), self:get_line_height(), style.error_line)  
  end
  doc_view_draw_line_gutter(self, idx, x, y)
end

local BuildMessageView = View:extend()
function BuildMessageView:new()
  BuildMessageView.super.new(self)
  self.messages = { }
  self.target_size = build.drawer_size
  self.scrollable = true
  self.init_size = true
  self.hovered_message = nil
  self.visible = false
  self.active_message = nil
  self.active_file = nil
  self.active_line = nil
end
function BuildMessageView:update()
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.y = dest
    self.init_size = false
  else
    self:move_towards(self.size, "y", dest)
  end
  BuildMessageView.super.update(self)
end
function BuildMessageView:set_target_size(axis, value)
  if axis == "y" then
    self.target_size = value
    return true
  end
end
function BuildMessageView:clear_messages()
  self.messages = {}
  self.hovered_message = nil
  self.active_message = nil
  self.active_file = nil
  self.active_line = nil
end
function BuildMessageView:add_message(message)
  table.insert(self.messages, message)
end
function BuildMessageView:get_item_height()
  return style.code_font:get_height() + style.padding.y*2
end
function BuildMessageView:get_scrollable_size()
  return #self.messages and self:get_item_height() * (#self.messages + 1)
end
function BuildMessageView:on_mouse_moved(px, py, ...)
  BuildMessageView.super.on_mouse_moved(self, px, py, ...)
  if self.dragging_scrollbar then return end
  local ox, oy = self:get_content_offset()
  local offset = math.floor((py - oy) / self:get_item_height())
  self.hovered_message = offset >= 1 and offset <= #self.messages and offset
end
function BuildMessageView:on_mouse_pressed(button, x, y, clicks)
  if BuildMessageView.super.on_mouse_pressed(self, button, x, y, clicks) then
    return
  elseif self.hovered_message then
    self.active_message = self.hovered_message
    self.active_file = system.absolute_path(common.home_expand(self.messages[self.hovered_message][2]))
    self.active_line = tonumber(self.messages[self.hovered_message][3])
    jump_to_file(self.active_file, tonumber(self.messages[self.hovered_message][3]), tonumber(self.messages[self.hovered_message][4]))
  end
end
function BuildMessageView:draw()
  self:draw_background(style.background3)
  local h = style.code_font:get_height()
  local item_height = self:get_item_height()
  local ox, oy = self:get_content_offset()
  common.draw_text(style.font, style.text, "Build Messages", "left", ox + style.padding.x, oy, 0, h)
  for i,v in ipairs(self.messages) do
    local yoffset = style.padding.y + (i - 1)*item_height + style.padding.y + h
    if self.hovered_message == i or self.active_message == i then
      renderer.draw_rect(ox, oy + yoffset - style.padding.y, self.size.x, h + style.padding.y*2, style.line_highlight)
    end
    common.draw_text(style.code_font, style.text, v[2] .. ":" .. v[3] .. " [" .. v[1] .. "]: " .. v[5], "left", ox + style.padding.x, oy + yoffset, 0, h)
  end
  self:draw_scrollbar()
end

build.message_view = BuildMessageView()
local node = core.root_view:get_active_node()
local message_view_node = node:split("down", build.message_view, { y = true }, true)

command.add(nil, {
  ["build:build"] = function()
    if #build.targets > 0 then 
      build.build(build.targets[build.current_target].name)
    end
  end,
  ["build:clean"] = function() 
    build.clean()
  end,
  ["build:next-target"] = function() 
    if #build.targets > 0 then
      build.current_target = (build.current_target + 1) % #build.targets
    end
  end,
  ["build:next-target"] = function() 
    if #build.targets > 0 then
      build.current_target = (build.current_target + 1) % #build.targets
      config.target_binary = build.targets[build.current_target].binary
    end
  end,
  ["build:toggle-drawer"] = function() 
    build.message_view.visible = not build.message_view.visible
  end
})

keymap.add { 
  ["ctrl+b"]             = "build:build",
  ["ctrl+t"]             = "build:next-target",
  ["ctrl+shift+b"]       = "build:clean",
  ["f6"]                 = "build:toggle-drawer"
}

return build

