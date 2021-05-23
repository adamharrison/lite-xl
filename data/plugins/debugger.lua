-- lite-xl 1.16

local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local DocView = require "core.docview"
local Doc = require "core.doc"
local common = require "core.common"
local style  = require "core.style"
local config  = require "core.config"
local process  = require "core.process"
local View = require "core.view"

local draw_line_gutter = DocView.draw_line_gutter
local on_mouse_moved = DocView.on_mouse_moved
local on_mouse_pressed = DocView.on_mouse_pressed

-- General debugger framework.
local debugger = {}
style.debugger_breakpoint = { common.color "#ca3434" }
style.debugger_execution_point = { common.color "#3434ca" }

-- Hash of absolute filenames, and line numbers.
debugger.breakpoints = { }
-- 2 member table, absolute filename, line number.
debugger.execution_point = nil
-- Backends are proper debuggers, like gdb or whatever clang's got.
debugger.backends = { }
debugger.output = function(line)
  core.log(line)
  print(line)
end
debugger.active_debugger = nil
setmetatable(debugger, { 
  __index = function(self, key)
    local active = rawget(debugger, "active_debugger")
    local loc = rawget(debugger, key)
    if loc or not active then
      return loc
    end
    local val = active[key]
    if type(val) == "function" then
      return function(...)
        return val(active, ...)
      end
    end
    return val
  end
})

function debugger.run(path)
  for k,v in pairs(debugger.backends) do
    if v.should_engage(path) then
      debugger.active_debugger = v
      v:run(path)
      break
    end
  end
end

function debugger.has_breakpoint(file, line)
  return debugger.breakpoints[file] and debugger.breakpoints[file][line] ~= nil
end

function debugger.add_breakpoint(file, line)
  if not debugger.breakpoints[file] then
    debugger.breakpoints[file] = { }
  end
  debugger.breakpoints[file][line] = true
  if debugger.active_debugger then
    debugger.active_debugger:add_breakpoint(file, line)
  end
end

function debugger.remove_breakpoint(file, line)
  if debugger.active_debugger then
    debugger.active_debugger:remove_breakpoint(file, line)
  end
  if debugger.breakpoints[file] ~= nil then
    debugger.breakpoints[file][line] = nil
  end
end

function debugger.toggle_breakpoint(file, line)
  if debugger.has_breakpoint(file, line) then
    debugger.remove_breakpoint(file, line)
  else
    debugger.add_breakpoint(file, line)
  end
end

local function jump_to_file(file, line)
  if not core.active_view or not core.active_view.doc or core.active_view.doc.abs_filename ~= file then
    -- Check to see if the file is in the project. If it is, open it, and go to the line.
    for i = 1, #core.project_directories do
      if common.path_belongs_to(file, core.project_dir) then
        local view = core.root_view:open_doc(core.open_doc(file))
        view:scroll_to_line(math.max(1, line - 20), true)
        view.doc:set_selection(line, 1, line, 1)
        break
      end
    end
  end
end

function debugger.set_execution_point(file, line)
  if file then
    debugger.execution_point = { file, line }
    jump_to_file(file, line)
  else
    debugger.execution_point = nil
  end
end


function DocView:on_mouse_moved(x, y, ...)
  on_mouse_moved(self, x, y, ...)
  local minline, maxline = self:get_visible_line_range()
  local _, docy = self:get_line_screen_position(minline)
  if x > self.position.x and x < self.position.x + self:get_gutter_width() then
    self.cursor = "arrow"
  end
end

function DocView:on_mouse_pressed(button, x, y, clicks)
  on_mouse_pressed(self, button, x, y, clicks)
  local minline, maxline = self:get_visible_line_range()
  local _, docy = self:get_line_screen_position(minline)
  if self.doc and x > self.position.x and x < self.position.x + self:get_gutter_width() and y > docy then
    debugger.toggle_breakpoint(self.doc.abs_filename, minline + math.floor((y - docy) / self:get_line_height()))
  end
end

function DocView:draw_line_gutter(idx, x, y)  
   if debugger.has_breakpoint(self.doc.abs_filename, idx) then
     renderer.draw_rect(x, y, self:get_gutter_width(), self:get_line_height(), style.debugger_breakpoint)
   end
   if debugger.execution_point and debugger.execution_point[1] == self.doc.abs_filename and idx == debugger.execution_point[2] then
     renderer.draw_rect(x, y+1, self:get_gutter_width(), self:get_line_height()-2, style.debugger_execution_point)
   end
  draw_line_gutter(self, idx, x, y)
end

local StackView = View:extend()

function StackView:new()
  StackView.super.new(self)
  self.stack = { }
  self.visible = false
  self.target_size = 50
  self.scrollable = true
  self.init_size = true
  self.hovered_frame = nil
end

function StackView:update()
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.y = dest
    self.init_size = false
  else
    self:move_towards(self.size, "y", dest)
  end
  StackView.super.update(self)
end

function StackView:set_target_size(axis, value)
  if axis == "y" then
    self.target_size = value
    return true
  end
end

function StackView:set_stack(stack)
  self.stack = stack
  self.hovered_frame = nil
  core.redraw = true
end

function StackView:get_item_height()
  return style.font:get_height() + style.padding.y*2
end

function StackView:get_scrollable_size()
  return #self.stack and self:get_item_height() * #self.stack
end

function StackView:on_mouse_moved(px, py, ...)
  StackView.super.on_mouse_moved(self, px, py, ...)
  if self.dragging_scrollbar then return end
  local ox, oy = self:get_content_offset()
  local offset = math.floor((py - oy) / self:get_item_height()) + 1
  self.hovered_frame = offset >= 1 and offset <= #self.stack and offset
end

function StackView:on_mouse_pressed(button, x, y, clicks)
  local caught = StackView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then
    return
  end
  if self.hovered_frame then
    jump_to_file(self.stack[self.hovered_frame][2], self.stack[self.hovered_frame][3])
  end
end

function StackView:draw()
  self:draw_background(style.background2)
  local h = style.font:get_height()
  local ox, oy = self:get_content_offset()
  for i,v in ipairs(self.stack) do
    local yoffset = style.padding.y + (i-1) * (style.font:get_height() + style.padding.y * 2)
    if self.hovered_frame == i then
      renderer.draw_rect(ox, oy + yoffset - style.padding.y, self.size.x, h + style.padding.y*2, style.line_highlight)
    end
    common.draw_text(style.code_font, style.text, "#" .. i .. " " .. v[1] .. " " .. v[2] .. (v[3] and (" line " .. v[3]) or ""), "left", ox + style.padding.x, oy + yoffset, 0, h)
  end
  self:draw_scrollbar()
end

local stack_view = StackView()
local node = core.root_view:get_active_node()
local stack_view_node = node:split("down", stack_view, { y = true }, true)

-- GDB Specific Stuff
local function gdb_parse_string(str) 
  local offset = 0
  while offset ~= nil do
    offset = str:find('"', offset+1)
    if offset and str:sub(offset - 1, offset - 1) ~= "\\" then
      return str:sub(1, offset - 1), offset + 1
    end
  end
end

local gdb_parse_status_attributes
local gdb_parse_status_array

local function gdb_parse_status_value(value)
  if value:sub(1, 1) == "{" then
    return gdb_parse_status_attributes(value:sub(2))
  elseif value:sub(1,1) == "[" then
    return gdb_parse_status_array(value:sub(2))
  elseif value:sub(1,1) == "\"" then
    return gdb_parse_string(value:sub(2))
  end
  return nil
end

gdb_parse_status_array = function(values)
  local array = { }
  local offset = 1
  if values:sub(offset, offset) == "]" then
    return array
  end
  while true do
    local value, length = gdb_parse_status_value(values:sub(offset))
    table.insert(array, value)
    offset = offset + length
    if values:sub(offset, offset) == "," then
      offset = offset + 1
    elseif values:sub(offset, offset) == "]" then
      return array, offset+1
    end
  end
end


gdb_parse_status_attributes = function(attributes)
  local obj = { }
  local offset = 1
  while true do
    local equal_idx = attributes:find("=", offset)
    local attr_name = attributes:sub(offset, equal_idx-1)
    local attr_value, length = gdb_parse_status_value(attributes:sub(equal_idx+1))
    if not length then
      return obj, offset + 1
    end
    obj[attr_name] = attr_value
    offset = length + equal_idx + 1
    if attributes:sub(offset, offset) == "," then
      offset = offset + 1
    else
      return obj, offset+1
    end
  end
  return offset
end

local function gdb_parse_status_line(line)
  print(line)
  local idx = line:find(",")
  local type = line:sub(1, 1)
  if idx and type == "*" or type == "=" then
    return type, line:sub(2, idx - 1), gdb_parse_status_attributes(line:sub(idx+1))
  elseif type == "~" then
    return type, gdb_parse_string(line:sub(3))
  elseif type == "^" then
    return type, line:sub(2)
  else
    return type
  end
end

debugger.backends.gdb = { 
  running_program = nil,
  command_queue = { },
  breakpoints = { }
}
function debugger.backends.gdb:should_engage(path)
  return true
end
function debugger.backends.gdb:cmd(command, on_finish)
  debugger.output("Running GDB command " .. command .. ".")
  table.insert(self.command_queue, { command, on_finish })
end
function debugger.backends.gdb:step_into()
  self:cmd("step")
end
function debugger.backends.gdb:step_over()
  self:cmd("next")
end
function debugger.backends.gdb:step_out()
  self:cmd("finish")
end
function debugger.backends.gdb:continue()
  self:cmd("cont")
end
function debugger.backends.gdb:attach(pid)
  
end
function debugger.backends.gdb:is_running()
  return self.running_program ~= nil
end
function debugger.backends.gdb:terminate()
  self:cmd("quit")
  stack_view.visible = false
  debugger.set_execution_point(nil)
end
function debugger.backends.gdb:halt()
  self.running_program:signal("SIGINT")
end
function debugger.backends.gdb:add_breakpoint(file, line)
  if self.running_program then
    self:cmd("b " .. file .. ":" .. line, function(type, category, attributes)
      if attributes["bkpt"] then
        if not self.breakpoints[file] then
          self.breakpoints[file] = { }
        end
        self.breakpoints[file][line] = tonumber(attributes["bkpt"]["number"])
      end
    end)
  end
end

function debugger.backends.gdb:remove_breakpoint(file, line)
  if self.running_program and self.breakpoints[file] and type(self.breakpoints[file][line]) == "number" then
    self:cmd("d " .. self.breakpoints[file][line])
  end
end

function debugger.backends.gdb:run(program)
  debugger.output("Running GDB on " .. program .. ".")
  stack_view.set_stack({ })
  stack_view.visible = true
  core.add_thread(function()
    self.running_program = process.popen("gdb", "-q", "-nx", "--interpreter=mi", "--args", program)
    local result = ""
    local accumulator = {}
    local running_program_state = "init"
    local resume_on_pause = false
    local waiting_on_result = function(type, category, attributes)
      running_program_state = "stopped"
      self:cmd("start")
      for file, v in pairs(debugger.breakpoints) do
        for line, v in pairs(debugger.breakpoints[file]) do
          self:add_breakpoint(file, line)
        end
      end
      self:cmd("set filename-display absolute")
      self:cmd("cont")
    end
    while result ~= nil do
      result = self.running_program:read()
      if result ~= nil and #result > 0 then
        local offset = 1
        while offset < #result do
          local newline = result:find("\n", offset) or #result
          local line = result:sub(offset, newline-1)
          --debugger.output(line)
          local type, category, attributes = gdb_parse_status_line(line)
          offset = newline + 1 
          if type == "*" then
            running_program_state = category
          end
          if type == "^" and category == "done" then
            if waiting_on_result then
              waiting_on_result(type, category, accumulator)
            end
            waiting_on_result = nil
            accumulator = {}
          end
          if type == "~" then
            table.insert(accumulator, category)
          end
          if type == "=" and waiting_on_result then
            waiting_on_result(type, category, attributes)
            waiting_on_result = nil
          elseif type == "*" and category == "stopped" and attributes["frame"] and attributes["bkptno"] ~= "1" and not resume_on_pause then
            debugger.set_execution_point(attributes["frame"]["fullname"], tonumber(attributes["frame"]["line"]))
            accumulator = {}
            self:cmd("backtrace", function(type, category, frames)
              local stack = { }
              for i,v in ipairs(frames) do
                local s,e = string.find(v, " at ")
                if s then
                  local _, _, n, details = string.find(v:sub(1, s-1), "#(%d+)%s+(.+)")
                  local _, _, file, line = string.find(v:sub(e+1), "([^:]+):(%d+)")
                  table.insert(stack, {  details, file, tonumber(line) })
                else
                  local s,e = string.find(v, " in ")
                  local _, _, n, details = string.find(v:sub(1, s-1), "#(%d+)%s+(.+)")
                  local file = v:sub(e + 1)
                  table.insert(stack, {  details, file, nil })
                end
              end
              stack_view:set_stack(stack)
            end)
          elseif type == "*" and category == "stopped" and attributes["reason"] == "exited-normally" then
            self:cmd("quit")
          elseif type == "*" and category == "running" then
            debugger.set_execution_point(nil)
          end
        end
      end
      if not waiting_on_result and #self.command_queue > 0 then
        if running_program_state == "running" then
          self.running_program:signal("SIGINT")
          resume_on_pause = true
          running_program_state = "interrupting"
        elseif running_program_state == "stopped" then
          if self.running_program:write(self.command_queue[1][1] .. "\n") then
            if self.command_queue[1][2] then
              waiting_on_result = self.command_queue[1][2]
            end
            table.remove(self.command_queue, 1)
            if #self.command_queue == 0 and resume_on_pause then
              self:cmd("cont")
              resume_on_pause = false
            end
          end
        end
      end
      coroutine.yield(config.debugger_interval or 0.1)
    end
    debugger.output("GDB finished running " .. program .. ".")
    self.running_program = nil
    stack_view.visible = false
  end)
  return true
end

command.add(nil, {
  ["debugger:step-over"] = function()
    debugger.step_over()
  end,
  ["debugger:step-into"] = function()
    debugger.step_into()
  end,
  ["debugger:step-out"] = function()
    debugger.step_out()
  end,
  ["debugger:toggle-breakpoint"] = function()
    if core.active_view and core.active_view.doc then
      local line1, col1, line2, col2, swap = core.active_view.doc:get_selection(true)
      if line1 then
        debugger.toggle_breakpoint(core.active_view.doc.abs_filename, line1);
      end
    end
  end,
  ["debugger:start-or-continue"] = function()
    if debugger.active_debugger and debugger.is_running() then    
      debugger.continue()
    elseif config.target_binary then
      debugger.run(config.target_binary)
    else
      core.command_view:enter("Program to Debug", function(text)
        debugger.run(text)
      end)
    end
  end,
  ["debugger:break"] = function()    
    debugger.halt()
  end,
  ["debugger:quit"] = function()    
    debugger.terminate()
  end,
  ["debugger:toggle-stackview"] = function()    
    stack_view.visible = not stack_view.visible
  end
})


keymap.add { 
  ["f7"]                 = "debugger:step-over",
  ["shift+f7"]           = "debugger:step-into",
  ["ctrl+f7"]            = "debugger:step-out",
  ["f8"]                 = "debugger:start-or-continue", 
  ["ctrl+f8"]            = "debugger:break", 
  ["shift+f8"]           = "debugger:quit",
  ["f9"]                 = "debugger:toggle-breakpoint"
}
