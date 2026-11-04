-- Thin drawing layer that mimics the canvas-2D calls used by the web build,
-- so the port of every draw function stays close to the original.
local U = require "util"
local lg = love.graphics
local G = { alpha = 1 }

local function rgb(c)
  if type(c) == "string" then return U.hex(c) end
  return c
end
G.rgb = rgb

function G.set(c, a)
  c = rgb(c)
  lg.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1) * G.alpha)
end

function G.rect(c, x, y, w, h, a) G.set(c, a); lg.rectangle("fill", x, y, w, h) end
function G.srect(c, x, y, w, h, lw, a) G.set(c, a); lg.setLineWidth(lw or 1); lg.rectangle("line", x, y, w, h) end
function G.circle(c, x, y, r, a) G.set(c, a); lg.circle("fill", x, y, r, math.max(16, math.floor(r))) end
function G.ring(c, x, y, r, lw, a) G.set(c, a); lg.setLineWidth(lw or 1); lg.circle("line", x, y, r, math.max(24, math.floor(r))) end
function G.arc(c, x, y, r, a1, a2, lw, a) G.set(c, a); lg.setLineWidth(lw or 1); lg.arc("line", "open", x, y, r, a1, a2, 32) end
function G.pie(c, x, y, r, a1, a2, a) G.set(c, a); lg.arc("fill", "pie", x, y, r, a1, a2, 48) end
function G.line(c, x0, y0, x1, y1, lw, a) G.set(c, a); lg.setLineWidth(lw or 1); lg.line(x0, y0, x1, y1) end
function G.poly(c, pts, a) G.set(c, a); lg.polygon("fill", pts) end        -- convex only
function G.spoly(c, pts, lw, a) G.set(c, a); lg.setLineWidth(lw or 1); lg.polygon("line", pts) end

-- ── Fonts: use the web build's Google Fonts if the TTFs were dropped in assets/fonts,
--    otherwise LÖVE's built-in font (works out of the box).
local FONT_FILES = {
  orb = "assets/fonts/Orbitron-Black.ttf",
  vt = "assets/fonts/VT323-Regular.ttf",
  script = "assets/fonts/MrDafoe-Regular.ttf",
  mono = "assets/fonts/ShareTechMono-Regular.ttf",
}
local fonts = {}
function G.font(kind, size)
  local key = kind .. size
  local f = fonts[key]
  if f then return f end
  local path = FONT_FILES[kind]
  if path and love.filesystem.getInfo(path) then
    f = lg.newFont(path, size)
  else
    -- built-in font is wider than VT323/Orbitron: shrink a little so layouts still fit
    local k = (kind == "vt") and 0.72 or (kind == "orb") and 0.8 or (kind == "script") and 0.75 or 0.9
    f = lg.newFont(math.max(8, math.floor(size * k + .5)))
  end
  f:setFilter("linear", "linear")
  fonts[key] = f
  return f
end

-- Text drawn on its baseline at (x, y), like ctx.fillText
function G.text(s, x, y, align, font, c, a)
  lg.setFont(font); G.set(c, a)
  local w = font:getWidth(s)
  local ox = (align == "center" and w / 2) or (align == "right" and w) or 0
  lg.print(s, math.floor(x - ox + .5), math.floor(y - font:getBaseline() + .5))
end
function G.textW(s, font) return font:getWidth(s) end

-- Fake strokeText: draw the text around the position in a ring
function G.textStroke(s, x, y, align, font, c, width, a)
  local r = width / 2
  for i = 0, 7 do
    local ang = i * math.pi / 4
    G.text(s, x + math.cos(ang) * r, y + math.sin(ang) * r, align, font, c, a)
  end
end

-- ── Vertical gradient shader (by render-target pixel y). Up to 6 stops.
local gradShader
local function shader()
  if gradShader then return gradShader end
  gradShader = lg.newShader([[
    extern vec4 cols[6];
    extern float pos[6];
    extern float n;
    extern float y0;
    extern float y1;
    vec4 effect(vec4 col, Image tex, vec2 tc, vec2 sc){
      float t = clamp((sc.y - y0) / max(1.0, (y1 - y0)), 0.0, 1.0);
      vec4 c = cols[0];
      for (int i = 1; i < 6; i++) {
        if (float(i) < n && t >= pos[i-1]) {
          float k = clamp((t - pos[i-1]) / max(0.0001, pos[i] - pos[i-1]), 0.0, 1.0);
          c = mix(cols[i-1], cols[i], k);
        }
      }
      vec4 tx = Texel(tex, tc);
      return vec4(c.rgb, c.a * tx.a * col.a);
    }
  ]])
  return gradShader
end

-- stops = { {pos, color}, ... } ; y0..y1 in render-target pixels
function G.gradBegin(stops, y0, y1)
  local s = shader()
  local cols, pos = {}, {}
  for i = 1, 6 do
    local st = stops[math.min(i, #stops)]
    local c = rgb(st[2])
    cols[i] = { c[1], c[2], c[3], c[4] or 1 }
    pos[i] = st[1]
  end
  s:send("cols", unpack(cols))
  s:send("pos", unpack(pos))
  s:send("n", #stops)
  s:send("y0", y0)
  s:send("y1", y1)
  lg.setShader(s)
  lg.setColor(1, 1, 1, G.alpha)
end
function G.gradEnd() lg.setShader() end

-- Convenience: gradient-filled rectangle
function G.vgrad(x, y, w, h, stops)
  G.gradBegin(stops, y, y + h)
  lg.rectangle("fill", x, y, w, h)
  G.gradEnd()
end

return G
