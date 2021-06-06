local core = require "core"
local config = require "core.config"
local tokenizer = require "core.tokenizer"
local common = require "core.common"
local Object = require "core.object"


local Highlighter = Object:extend()


function Highlighter:new(doc)
  self.doc = doc
  self:reset()

  -- init incremental syntax highlighting
  core.add_thread(function()
    while true do
      if self.first_invalid_line > self.max_wanted_line then
        self.max_wanted_line = 0
        coroutine.yield(1 / config.fps)

      else
        print("ABS", self.doc.abs_filename)
        local max = math.min(self.first_invalid_line + 40, self.max_wanted_line)

        local lines = {}
        for i = self.first_invalid_line, max do
          local state = (i > 1) and self.lines[i - 1].state
          local line = self.lines[i]
          if not (line and line.init_state == state) then
            self.lines[i] = self:tokenize_line(i, state)
            table.insert(lines, i)
          end
          if not line or line.state ~= self.lines[i].state then
            self.max_wanted_line = math.min(i + 1, #self.doc.lines)
            max = math.min(self.first_invalid_line + 40, self.max_wanted_line)
          end
        end

        self.first_invalid_line = max + 1
        -- core.redraw = true
        for i,v in ipairs(core.get_visible_docviews()) do
          if v.doc == self.doc then
            print("LINES", unpack(lines))
            core.queue_redraw(v, { ["lines"] = lines })
          end
        end
        coroutine.yield()
      end
    end
  end, self)
end


function Highlighter:reset()
  self.lines = {}
  self.first_invalid_line = 1
  self.max_wanted_line = 0
end


function Highlighter:invalidate(idx)
  self.first_invalid_line = math.min(self.first_invalid_line, idx)
  self.max_wanted_line = math.min(self.max_wanted_line, #self.doc.lines)
end


function Highlighter:tokenize_line(idx, state)
  local res = {}
  res.init_state = state
  res.text = self.doc.lines[idx]
  res.tokens, res.state = tokenizer.tokenize(self.doc.syntax, res.text, state)
  return res
end


function Highlighter:get_line(idx)
  local line = self.lines[idx]
  if not line or line.text ~= self.doc.lines[idx] then
    local prev = self.lines[idx - 1]
    local newline = self:tokenize_line(idx, prev and prev.state)
    self.lines[idx] = newline
    if not line or newline.state ~= line.state then
      self.max_wanted_line = common.clamp(idx + 40, self.max_wanted_line, #self.doc.lines)
    end
    line = newline
  end
  self.max_wanted_line = math.max(self.max_wanted_line, idx)
  return line
end


function Highlighter:each_token(idx)
  return tokenizer.each_token(self:get_line(idx).tokens)
end


return Highlighter
