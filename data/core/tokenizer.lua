local syntax = require "core.syntax"
local common = require "core.common"
local Tokenizer = require "tokenizer"

local tokenizer = {
  syntaxes = {}
}

function tokenizer.tokenize(syntax, text, state)
  local native = tokenizer.syntaxes[syntax]
  if not native then 
    native = Tokenizer.new(syntax)
    tokenizer.syntaxes[syntax] = native
  end
  local res, state = native:tokenize(text, state or 0)
  local start = 1
  for i = 2, #res, 2 do
    local len = res[i]
    res[i] = text:sub(start, len + start - 1)
    start = len + start
  end
  return res, state
end


local function iter(t, i)
  i = i + 2
  local type, text = t[i], t[i+1]
  if type then
    return i, type, text
  end
end

function tokenizer.each_token(t)
  return iter, t, -1
end


return tokenizer
