-- Minimal JSON encode/decode (no code execution — safe for data from the network).
-- Same wire format as the web build, so a future relay can bridge browser ↔ LÖVE.
local J = {}

local function isArray(t)
  local n = #t
  if n == 0 then return next(t) == nil end
  for k in pairs(t) do if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end end
  return true
end

local esc = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function encode(v, out)
  local t = type(v)
  if t == "nil" then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "0"
    elseif v % 1 == 0 and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.4g", v) end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c) return esc[c] or string.format("\\u%04x", c:byte()) end) .. '"'
  elseif t == "table" then
    if isArray(v) then
      out[#out + 1] = "["
      for i = 1, #v do if i > 1 then out[#out + 1] = "," end; encode(v[i], out) end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local first = true
      for k, val in pairs(v) do
        if type(val) ~= "function" then
          if not first then out[#out + 1] = "," end
          first = false
          encode(tostring(k), out); out[#out + 1] = ":"; encode(val, out)
        end
      end
      out[#out + 1] = "}"
    end
  else out[#out + 1] = "null" end
end
function J.encode(v) local out = {}; encode(v, out); return table.concat(out) end

-- Decoder ---------------------------------------------------------------------
local decode
local function ws(s, i) return s:find("[^ \t\r\n]", i) or #s + 1 end
local function str(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == "" then error("unterminated string") end
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local n = s:sub(j + 1, j + 1)
      local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
      if n == "u" then
        local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
        out[#out + 1] = require("utf8").char(cp); j = j + 6
      else out[#out + 1] = map[n] or n; j = j + 2 end
    else
      local k = s:find('[\\"]', j) or #s + 1
      out[#out + 1] = s:sub(j, k - 1); j = k
    end
  end
end
function decode(s, i)
  i = ws(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local t = {}
    i = ws(s, i + 1)
    if s:sub(i, i) == "}" then return t, i + 1 end
    while true do
      local k; k, i = str(s, ws(s, i))
      i = ws(s, i); i = i + 1                  -- ':'
      t[k], i = decode(s, i)
      i = ws(s, i)
      local d = s:sub(i, i); i = i + 1
      if d == "}" then return t, i end
    end
  elseif c == "[" then
    local t = {}
    i = ws(s, i + 1)
    if s:sub(i, i) == "]" then return t, i + 1 end
    while true do
      local v; v, i = decode(s, i)
      t[#t + 1] = v
      i = ws(s, i)
      local d = s:sub(i, i); i = i + 1
      if d == "]" then return t, i end
    end
  elseif c == '"' then return str(s, i)
  elseif s:sub(i, i + 3) == "true" then return true, i + 4
  elseif s:sub(i, i + 4) == "false" then return false, i + 5
  elseif s:sub(i, i + 3) == "null" then return nil, i + 4
  else
    local num = s:match("^-?[%d%.eE+%-]+", i)
    if not num then error("bad json at " .. i) end
    return tonumber(num), i + #num
  end
end
function J.decode(s)
  local ok, v = pcall(decode, s, 1)
  if ok then return v end
  return nil
end

return J
