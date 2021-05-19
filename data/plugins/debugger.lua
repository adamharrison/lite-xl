-- lite-xl 1.16

local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local DocView = require "core.docview"
local Doc = require "core.doc"
local common = require "core.common"
local style  = require "core.style"
local config  = require "core.config"

style.debugger_breakpoint = { common.color "#ca3434" }
style.debugger_execution_point = { common.color "#3434ca" }

local draw_line_gutter = DocView.draw_line_gutter
local on_mouse_moved = DocView.on_mouse_moved
local on_mouse_pressed = DocView.on_mouse_pressed

-- Hash of absolute filenames, and line numbers.
local breakpoints = { }
-- 2 member table, absolute filename, line number.
local execution_point = nil
local running_program = nil
local running_program_state = nil

local command_queue = { }
local waiting_on_result = false

local function has_breakpoint(file, line)
  return breakpoints[file] and breakpoints[file][line]
end

local function add_breakpoint(file, line, force)
  if not breakpoints[file] then
    breakpoints[file] = { }
  end
  breakpoints[file][line] = true
  if force or running_program then
    run_gdb_command("b " .. file .. ":" .. line, function(type, category, attributes)
      if attributes["bkpt"] then
        breakpoints[file][line] = attributes["bkpt"]["number"]
      end
    end)
  end
end

local function remove_breakpoint(file, line)
  if running_program and type(breakpoints[file][line]) == "number" then
    run_gdb_command("d " .. breakpoints[file][line])
  end
  if breakpoints[file] then
    breakpoints[file][line] = nil
  end
end

local function toggle_breakpoint(file, line)
  return has_breakpoint(file, line) and remove_breakpoint(file, line) or add_breakpoint(file, line)
end

local function set_execution_point(file, line)
  execution_point = file and { file, line } or nil
end

local function run_gdb_command(command, on_finish)
  command_queue.insert({ command, on_finish })
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
    toggle_breakpoint(self.doc.abs_filename, minline + math.floor((y - docy) / self:get_line_height()))
  end
end

function DocView:draw_line_gutter(idx, x, y)  
   if has_breakpoint(self.doc.abs_filename, idx) then
     renderer.draw_rect(x, y, self:get_gutter_width(), self:get_line_height(), style.debugger_breakpoint)
   end
   if execution_point and execution_point[1] == self.doc and idx == execution_point[2] then
     renderer.draw_rect(x, y, self:get_gutter_width(), self:get_line_height(), style.debugger_execution_point)
   end
  draw_line_gutter(self, idx, x, y)
end



local function parse_gdb_string(str) 
  local offset = 1
  while offset ~= nil do
    offset = str:find("\"", offset)
    if offset and str:sub(offset - 1, offset - 1) ~= "\\" then
      return str:sub(1, offset - 1), offset + 1
    end
  end
end

local function parse_gdb_status_value(value)
  if value:sub(1, 1) == "{" then
    return parse_gdb_status_attributes(value:sub(2))
  elseif value:sub(1,1) == "[" then
    return parse_gdb_status_array(value:sub(2))
  elseif value:sub(1,1) == "\"" then
    return parse_gdb_string(value:sub(2))
  end
  return nil
end

local function parse_gdb_status_array(values)
  local array = { }
  local offset = 1
  while true do
    local value, length = parse_gdb_status_value(values:sub(offset))
    table.insert(array, value)
    offset = offset + length
    if values:sub(offset, offset) == "," then
      offset = offset + 1
    elseif values:sub(offset, offset) == "]" then
      return array, offset+1
    else
      print("wtf")
    end
  end
end


local function parse_gdb_status_attributes(attributes)
  local obj = { }
  local equal_idx = attributes:find("=")
  local attr_name = attributes:sub(1, equal_idx-1)
  local offset = 1
  while true do
    local attr_value
    attr_value, length = parse_gdb_status_value(attributes:sub(equal_idx+1))
    obj[attr_name] = attr_value
    offset = offset + length
    if attributes:sub(offset, offset) == "," then
      offset = offset + 1
    else
      return obj, offset+1
    end
  end
  return offset
end

local function parse_gdb_status_line(line)
  local idx = line:find(",")
  return line:sub(1, 1), line:sub(1, idx - 1), parse_gdb_status_attributes(line:sub(idx+1))
end


local function run_program(program)
  core.add_thread(function()
    running_program = system.popen("gdb -q -nx --interpreter=mi --args " .. program)
    running_program_state = "init"
    for file, v in pairs(breakpoints) do
      for line, v in pairs(breakpoints[file]) do
        add_breakpoint(file, line, true)
      end
    end
    local result = ""
    waiting_on_result = function(type, category, attributes)
      running_program_state = "stopped"
      print("SETTING TO STOP")
      table.insert(command_queue, { "start", nil })
    end
    while result ~= nil do
      print("K")
      result = running_program:read()
      print("RESULT" .. type(result))
      print(result)
      if result ~= nil and #result > 0 then
        local offset = 1
        while offset < #result do
          local newline = result:find("\n") or #result
          print("KA: " .. result:sub(offset, newline-1))
          local type, category, attributes = parse_gdb_status_line(result:sub(offset, newline-1))
          print("TYPE" .. type)
          print("CATEGORY" .. category)
          if type == "*" then
            running_program_state = category
          end
          if type == "=" and waiting_on_result then
            waiting_on_result(type, category, attributes)
            waiting_on_result = nil
          elseif type == "*" and category == "stopped" and attributes["frame"] then
            set_execution_point(attributes["frame"]["fullname"], attributes["frame"]["line"])
          end
        end
      end
      if not waiting_on_result and #command_queue > 0 then
        if running_program_state == "running" then
          running_program:signal("SIGINT")
          running_program_state = "interrupting"
        elseif running_program_state == "stopped" then
          print("WATA " .. command_queue[1][1])
          if running_program:write(command_queue[1][1]) then
            print("WRITTEN")
            if command_queue[1][2] then
              waiting_on_results = command_queue[1][2]
            end
            table.remove(command_queue, 1)
          else
            print("NOT WRITTEN")
          end
        end
      end
      coroutine.yield(config.debugger_interval or 0.2)
    end
    print("DONE")
  end)
end

command.add(nil, {
  ["debugger:step-over"] = function()
    run_gdb_command("next")
  end,
  ["debugger:step-into"] = function()
    run_gdb_command("step")
  end,
  ["debugger:step-out"] = function()
    run_gdb_command("finish")
  end,
  ["debugger:start-or-continue"] = function()
    if running_program then    
      run_gdb_command("cont")
    else
      run_program("./lite")
    end
  end,
  ["debugger:run"] = function()
    core.command_view:enter("Program to Debug", function(text)
      run_program(text)
    end)
  end,
  ["debugger:quit"] = function()    
    if running_program then
      running_program:signal("SIGTERM")
    end
  end
})

keymap.add { 
  ["f7"]                 = "debugger:step-over",
  ["shift+f7"]           = "debugger:step-into",
  ["ctrl+f7"]            = "debugger:step-out",
  ["f8"]                 = "debugger:start-or-continue", 
  ["shift+f8"]           = "debugger:quit"
}
