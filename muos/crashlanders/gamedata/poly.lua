-- Early-90s flat-shaded polygon renderer + models (menu and cinematics)
local U = require "util"
local G = require "gfx"
local lg = love.graphics
local Pm = {}

local PL = { x = -.45, y = -.65, z = -.6 }
do local m = math.sqrt(PL.x ^ 2 + PL.y ^ 2 + PL.z ^ 2); PL.x, PL.y, PL.z = PL.x / m, PL.y / m, PL.z / m end

local function mkIco()
  local f = (1 + math.sqrt(5)) / 2
  local v = {}
  for _, a in ipairs({ -1, 1 }) do for _, b in ipairs({ -1, 1 }) do
    v[#v + 1] = { 0, a, b * f }; v[#v + 1] = { a, b * f, 0 }; v[#v + 1] = { b * f, 0, a }
  end end
  local function d2(p, q) return (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2 end
  local F = {}
  for i = 1, 12 do for j = i + 1, 12 do for k = j + 1, 12 do
    if math.abs(d2(v[i], v[j]) - 4) < .01 and math.abs(d2(v[j], v[k]) - 4) < .01 and math.abs(d2(v[i], v[k]) - 4) < .01 then
      F[#F + 1] = { i, j, k }
    end
  end end end
  return { v = v, f = F, convex = true }
end

local function mkBox(x0, y0, z0, x1, y1, z1)
  return { convex = true,
    v = { { x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 }, { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 } },
    f = { { 1, 2, 3 }, { 1, 3, 4 }, { 5, 7, 6 }, { 5, 8, 7 }, { 1, 5, 6 }, { 1, 6, 2 }, { 4, 3, 7 }, { 4, 7, 8 }, { 1, 4, 8 }, { 1, 8, 5 }, { 2, 6, 7 }, { 2, 7, 3 } } }
end

local function planetNoise(x, y, z)
  return math.sin(x * 4.1 + z * 2.3) + math.sin(y * 5.3 - x * 1.7) + math.cos(z * 3.7 + y * 2.9) + .5 * math.sin(x * 9.1 + y * 7.3 + z * 5.7)
end

local function subdivSphere(m, levels)
  local v = {}
  for i, p in ipairs(m.v) do local l = math.sqrt(p[1] ^ 2 + p[2] ^ 2 + p[3] ^ 2); v[i] = { p[1] / l, p[2] / l, p[3] / l } end
  local f = m.f
  for _ = 1, levels do
    local cache, nf = {}, {}
    local function mid(a, b)
      local k = a < b and (a .. "_" .. b) or (b .. "_" .. a)
      if cache[k] then return cache[k] end
      local p = { (v[a][1] + v[b][1]) / 2, (v[a][2] + v[b][2]) / 2, (v[a][3] + v[b][3]) / 2 }
      local l = math.sqrt(p[1] ^ 2 + p[2] ^ 2 + p[3] ^ 2)
      v[#v + 1] = { p[1] / l, p[2] / l, p[3] / l }
      cache[k] = #v
      return #v
    end
    for _, t in ipairs(f) do
      local a, b, c = t[1], t[2], t[3]
      local ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
      nf[#nf + 1] = { a, ab, ca }; nf[#nf + 1] = { b, bc, ab }; nf[#nf + 1] = { c, ca, bc }; nf[#nf + 1] = { ab, bc, ca }
    end
    f = nf
  end
  local vn = {}
  for i, p in ipairs(v) do vn[i] = planetNoise(p[1], p[2], p[3]) end
  for i, p in ipairs(v) do local r = 1 + math.max(0, vn[i] - .2) * .035; v[i] = { p[1] * r, p[2] * r, p[3] * r } end
  local tone = {}
  for i, t in ipairs(f) do
    local n = (vn[t[1]] + vn[t[2]] + vn[t[3]]) / 3
    local y = (v[t[1]][2] + v[t[2]][2] + v[t[3]][2]) / 3
    if math.abs(y) > .86 then tone[i] = 5
    elseif n < -.5 then tone[i] = 1 elseif n < .2 then tone[i] = 2 elseif n < .9 then tone[i] = 3 else tone[i] = 4 end
  end
  return { v = v, f = f, convex = true, tone = tone }
end

Pm.MOON = mkIco()
Pm.PLANET = subdivSphere(mkIco(), 3)           -- 1280 faces
Pm.SHIP = { convex = false,
  v = { { 30, 0, 0 }, { -12, -7, 0 }, { -14, 3, 16 }, { -14, 3, -16 }, { -18, 4, 0 }, { -20, -14, 0 }, { -8, -7, 0 }, { -22, 0, 5 }, { -22, 0, -5 } },
  f = { { 1, 2, 3 }, { 1, 4, 2 }, { 1, 3, 5 }, { 1, 5, 4 }, { 2, 5, 3 }, { 2, 4, 5 }, { 2, 7, 6 }, { 2, 6, 7 }, { 5, 8, 3 }, { 5, 4, 9 } } }
Pm.CRUISER = { convex = true,
  v = { { -70, 0, 0 }, { -30, -14, -24 }, { -30, -14, 24 }, { -30, 14, 24 }, { -30, 14, -24 }, { 60, -18, -30 }, { 60, -18, 30 }, { 60, 16, 30 }, { 60, 16, -30 } },
  f = { { 1, 2, 3 }, { 1, 3, 4 }, { 1, 4, 5 }, { 1, 5, 2 }, { 2, 6, 7 }, { 2, 7, 3 }, { 3, 7, 8 }, { 3, 8, 4 }, { 4, 8, 9 }, { 4, 9, 5 }, { 5, 9, 6 }, { 5, 6, 2 }, { 6, 9, 8 }, { 6, 8, 7 } } }
Pm.TOWER = mkBox(10, -34, -10, 40, -14, 10)

-- sea-deep, sea, land, highland, ice  (h, s, base lightness)
function Pm.planetTones(groundHue, bossHue)
  local sea = bossHue or (groundHue + 190) % 360      -- seas take the boss's colour
  return { { sea, 55, 5 }, { sea, 50, 11 }, { groundHue, 45, 13 }, { (groundHue + 20) % 360, 35, 20 }, { groundHue, 8, 40 } }
end

local cos, sin, sqrt, max, floor = math.cos, math.sin, math.sqrt, math.max, math.floor

-- Draw a model; returns projected points (1-based, matching model.v)
function Pm.draw(model, cx, cy, scale, rx, ry, rz, hue, sat, opt)
  opt = opt or {}
  local cX, sX, cY, sY, cZ, sZ = cos(rx), sin(rx), cos(ry), sin(ry), cos(rz), sin(rz)
  local R, P = {}, {}
  local D, zs = opt.dist or 6, opt.zs or 1
  local mcx, mcy, mcz = 0, 0, 0
  for i, p in ipairs(model.v) do
    local x, y, z = p[1], p[2], p[3]
    local y1, z1 = y * cX - z * sX, y * sX + z * cX
    local x2, z2 = x * cY + z1 * sY, -x * sY + z1 * cY
    local x3, y3 = x2 * cZ - y1 * sZ, x2 * sZ + y1 * cZ
    R[i] = { x3, y3, z2 }
    local k = D / (D + z2 / zs)
    P[i] = { cx + x3 * scale * k, cy + y3 * scale * k }
    mcx, mcy, mcz = mcx + x3, mcy + y3, mcz + z2
  end
  local nv = #model.v
  mcx, mcy, mcz = mcx / nv, mcy / nv, mcz / nv
  local Lt, nb = opt.light or PL, opt.bands or 4
  local faces = {}
  for fi, fc in ipairs(model.f) do
    local a, b, c = R[fc[1]], R[fc[2]], R[fc[3]]
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local nm = sqrt(nx * nx + ny * ny + nz * nz); if nm == 0 then nm = 1 end
    nx, ny, nz = nx / nm, ny / nm, nz / nm
    local skip = false
    if model.convex then
      local mx = (a[1] + b[1] + c[1]) / 3 - mcx
      local my = (a[2] + b[2] + c[2]) / 3 - mcy
      local mz = (a[3] + b[3] + c[3]) / 3 - mcz
      if nx * mx + ny * my + nz * mz < 0 then nx, ny, nz = -nx, -ny, -nz end
      if nz > 0 then skip = true end
    elseif nz > 0 then nx, ny, nz = -nx, -ny, -nz end
    if not skip then
      local lit = max(0, nx * Lt.x + ny * Lt.y + nz * Lt.z)
      faces[#faces + 1] = { fc = fc, fi = fi, z = (a[3] + b[3] + c[3]) / 3, band = floor(lit * nb + .5) / nb }
    end
  end
  table.sort(faces, function(p, q) return p.z > q.z end)
  local edge = opt.edge and G.rgb(opt.edge) or (not opt.noEdge and G.rgb("#12031f")) or nil
  local lspan = opt.lspan or 48
  lg.setLineWidth(opt.lw or 1)
  lg.setLineJoin("bevel")
  for _, f in ipairs(faces) do
    local h, sa, l0 = hue, sat, 14
    if opt.tones and model.tone then local tn = opt.tones[model.tone[f.fi]]; h, sa, l0 = tn[1], tn[2], tn[3] end
    local col = U.hsl(h + (f.band < .3 and -15 or 0), sa, l0 + f.band * lspan)
    local p1, p2, p3 = P[f.fc[1]], P[f.fc[2]], P[f.fc[3]]
    lg.setColor(col[1], col[2], col[3], G.alpha)
    lg.polygon("fill", p1[1], p1[2], p2[1], p2[2], p3[1], p3[2])
    if edge then
      lg.setColor(edge[1], edge[2], edge[3], G.alpha)
      lg.polygon("line", p1[1], p1[2], p2[1], p2[2], p3[1], p3[2])
    end
  end
  return P
end

return Pm
