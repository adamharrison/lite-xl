local syntax = require "core.syntax"

local tokenizer = {}

local function push_token(t, type, text)
  local prev_type = t[#t-1]
  local prev_text = t[#t]
  if prev_type and (prev_type == type or prev_text:find("^%s*$")) then
    t[#t-1] = type
    t[#t] = prev_text .. text
  else
    table.insert(t, type)
    table.insert(t, text)
  end
end


local function is_escaped(text, idx, esc)
  local byte = esc:byte()
  local count = 0
  for i = idx - 1, 1, -1 do
    if text:byte(i) ~= byte then break end
    count = count + 1
  end
  return count % 2 == 1
end


local function find_non_escaped(text, pattern, offset, esc)
  while true do
    local s, e = text:find(pattern, offset)
    if not s then break end
    if esc and is_escaped(text, s, esc) then
      offset = e + 1
    else
      return s, e
    end
  end
end

-- State is a 32-bit number that is four separate bytes, illustrating how many differnet delimiters we have open, and which subsyntaxes we have active.
-- At most, there are 3 subsyntaxes active at the same time. Beyond that, does not support further highlighting.
local function retrieve_syntax_state(incoming_syntax, state)
  local current_syntax, subsyntax_info, current_state, current_level = incoming_syntax, nil, 0, 0
  if state > 0 and (state > 255 or current_syntax.patterns[state].syntax) then
    -- If we have higher bits, then decode them, and find which syntax we're using.
    if state > 255 then
      for current_level=1,3 do
        local target = bit32.extract(state, current_level*8, 8)
        if target ~= 0 then
          if current_syntax.patterns[target].syntax then
            current_syntax = syntax.get(current_syntax.patterns[target].syntax)
            subsyntax_info = current_syntax.patterns[target]
          else
            current_state = target
            break
          end
        else      
          break
        end
      end
    else
      current_level = 1
      subsyntax_info = incoming_syntax.patterns[state]
      current_syntax = syntax.get(incoming_syntax.patterns[state].syntax)
    end
  end
  return current_syntax, subsyntax_info, current_state, current_level
end

function tokenizer.tokenize(incoming_syntax, text, state)
  local res = {}
  local i = 1

  if #incoming_syntax.patterns == 0 then
    return { "normal", text }
  end
 
  state = state or 0
  local current_syntax, subsyntax_info, current_state, current_level = retrieve_syntax_state(incoming_syntax, state)

  while i <= #text do
    -- continue trying to match the end pattern of a pair if we have a state set
    if current_state > 0 then
      local p = current_syntax.patterns[current_state]
      local s, e = find_non_escaped(text, p.pattern[2], i, p.pattern[3])

      if s then
        push_token(res, p.type, text:sub(i, e))
        current_state = 0
        state = bit32.replace(state, 0, current_level*8, 8)
        i = e + 1
      else
        push_token(res, p.type, text:sub(i))
        break
      end
    end
    if subsyntax_info then
      local s, e = find_non_escaped(text, subsyntax_info.pattern[2], i, nil)

      if s then
        push_token(res, subsyntax_info.type, text:sub(i, e))
        current_state = 0
        state = bit32.replace(state, 0, current_level*8, 8)
        current_level = current_level - 1
        if current_level == 0 then
          current_syntax = incoming_syntax
          subsyntax_info = nil
          current_state = 0
        else
          current_syntax, subsyntax_info, current_state, current_level = retrieve_syntax_state(incoming_syntax, state)
        end
        i = e + 1
      end
    end

    -- find matching pattern
    local matched = false
    for n, p in ipairs(current_syntax.patterns) do
      local pattern = (type(p.pattern) == "table") and p.pattern[1] or p.pattern
      local s, e = text:find("^" .. pattern, i)

      if s then
        -- matched pattern; make and add token
        local t = text:sub(s, e)
        
        push_token(res, current_syntax.symbols[t] or p.type, t)
        -- update state if this was a start|end pattern pair
        if type(p.pattern) == "table" then
          current_state = n
          state = bit32.replace(state, n, current_level*8, 8)
          if p.syntax then
            current_level = current_level + 1
            subsyntax_info = p
          end
        end

        -- move cursor past this token
        i = e + 1
        matched = true
        break
      end
    end

    -- consume character if we didn't match
    if not matched then
      push_token(res, "normal", text:sub(i, i))
      i = i + 1
    end
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
