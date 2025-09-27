--mod-version:4 --priority:-3
local core = require "core"
local command = require "core.command"

function core.push_clip_rect(...)
  core.active_window():push_clip_rect(...)
end

function core.pop_clip_rect(...)
  core.active_window():pop_clip_rect(...)
end

local old_command_perform = command.perform
function command.perform(name, ...)
  if select('#', ...) == 0 then
    return old_command_perform(name, core.active_window().root_view, ...)
  end
  return old_command_perform(name, ...)
end

setmetatable(core, {
  __index = function(self, key)
    local root_view = core.active_window() and core.active_window().root_view
    if key == "root_view" then
      return root_view
    elseif root_view and root_view[key] then
      core.deprecation_log("core." .. key)
      return root_view[key]
    end
    return nil
  end
});
