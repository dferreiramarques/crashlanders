-- Small helpers shared by every module (mirrors the JS helpers of the web build)
local U = {}

function U.rnd(a, b) return math.floor(love.math.random() * (b - a)) + a end
function U.clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.sign(v) return v < 0 and -1 or 1 end

-- hsl(h, s%, l%) → {r,g,b} in 0..1 (same maths as the web build)
function U.hsl(h, s, l)
  h = ((h % 360) + 360) % 360; s = s / 100; l = l / 100
  local a = s * math.min(l, 1 - l)
  local function f(n)
    local k = (n + h / 30) % 12
    return l - a * math.max(math.min(k - 3, 9 - k, 1), -1)
  end
  return { f(0), f(8), f(4) }
end

local hexCache = {}
function U.hex(h)
  local c = hexCache[h]
  if c then return c end
  c = { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 }
  hexCache[h] = c
  return c
end

-- rgba(r,g,b,a) with 0..255 channels, like CSS
function U.rgba(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end

-- UTF-8 aware length / prefix (captions are typed out letter by letter)
local utf8 = require "utf8"
function U.ulen(s) return utf8.len(s) or #s end
function U.usub(s, n)
  if n <= 0 then return "" end
  local b = utf8.offset(s, n + 1)
  if not b then return s end
  return s:sub(1, b - 1)
end

-- Tiny serializer for save files (numbers, strings, booleans, nested tables)
local function ser(v)
  local t = type(v)
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "table" then
    local parts = {}
    for k, val in pairs(v) do
      local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      parts[#parts + 1] = key .. "=" .. ser(val)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end
U.ser = ser

function U.deser(s)
  if not s then return nil end
  local loader = loadstring or load
  local f = loader("return " .. s)
  if not f then return nil end
  if setfenv then setfenv(f, {}) end
  local ok, res = pcall(f)
  if ok then return res end
  return nil
end

return U
