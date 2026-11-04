-- Map, destructible tiles, dust, particles and the shared Body physics.
-- Coordinates are in the 800×450 game space of the web build; map arrays are 0-indexed.
local U = require "util"
local G = require "gfx"
local A = require "audio"
local rnd, clamp = U.rnd, U.clamp
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

TW, TH, MW, MH = 16, 16, 50, 28
TILE_MAX_HP = 3
DUST_MAX = TH * 5
function FLOOR_PX() return (MH - 2) * TH end

map, tileHP, tileKind, dustPiles, pendingPlatforms = nil, nil, nil, nil, {}
particles = {}

-- ── Level palette ───────────────────────────────────────────
lvl = {}
function setLvlPalette(gh, bh)
  lvl.groundHue, lvl.bossHue = gh, bh
  lvl.ground = U.hsl(gh, 40, 12); lvl.groundTop = U.hsl(gh, 60, 32); lvl.groundAcc = U.hsl(gh, 70, 48)
  lvl.dust = U.hsl(gh, 32, 28); lvl.dustT = U.hsl(gh, 40, 42)
  lvl.crack1 = U.hsl(gh + 20, 50, 52); lvl.crack2 = U.hsl(gh + 30, 60, 68)
  lvl.bossMain = U.hsl(bh, 70, 38); lvl.bossDark = U.hsl(bh, 80, 16)
  lvl.bossAcc = U.hsl(bh, 80, 54); lvl.bossEye = U.hsl((bh + 180) % 360, 80, 64)
end
function randomLvlPalette()
  local gh = rnd(0, 360)
  setLvlPalette(gh, (gh + rnd(120, 240)) % 360)
end
setLvlPalette(260, 0)

-- ── Particles ───────────────────────────────────────────────
function fx(x, y, n, col, spd, sz)
  spd, sz = spd or 3, sz or 2
  for _ = 1, n do
    local a, s = love.math.random() * math.pi * 2, love.math.random() * spd + .5
    particles[#particles + 1] = { x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s, life = rnd(8, 25), col = col, size = rnd(1, sz) }
  end
end
function updateParticles()
  local n = #particles
  local j = 1
  for i = 1, n do
    local p = particles[i]
    p.x = p.x + p.vx; p.y = p.y + p.vy; p.vy = p.vy + .12; p.life = p.life - 1
    if p.life > 0 then particles[j] = p; j = j + 1 end
  end
  for i = j, n do particles[i] = nil end
end
function drawParticles()
  for _, p in ipairs(particles) do
    G.rect(p.col, p.x - p.size / 2, p.y - p.size / 2, p.size, p.size, max(0, p.life / 22) * .9)
  end
end

-- ── Map ─────────────────────────────────────────────────────
local function grid() local g = {}; for y = 0, MH - 1 do local r = {}; for x = 0, MW - 1 do r[x] = 0 end; g[y] = r end; return g end

-- Plan where the wreckage will land; tiles appear when each piece hits (see cinematics)
function genRandomPlatforms()
  pendingPlatforms = {}
  local function add(tx, ty, tw)
    tw = min(tw, MW - 1 - tx)
    if tw >= 2 then pendingPlatforms[#pendingPlatforms + 1] = { tx = tx, ty = ty, tw = tw } end
  end
  for _ = 1, 10 + rnd(0, 6) do add(rnd(2, MW - 8), rnd(5, MH - 5), rnd(3, 9)) end
  for _, ab in ipairs({ { 2, 8 }, { MW - 10, MW - 2 } }) do
    for _ = 1, 3 do add(rnd(ab[1], ab[2]), rnd(6, MH - 4), rnd(3, 6)) end
  end
end

function initBaseMap()
  map, tileHP, tileKind = grid(), grid(), grid()
  dustPiles = {}
  for x = 0, MW - 1 do dustPiles[x] = 0 end
  for x = 0, MW - 1 do map[MH - 1][x] = 1; map[MH - 2][x] = 1; map[0][x] = 1 end
  for y = 0, MH - 1 do map[y][0] = 1; map[y][MW - 1] = 1 end
  genRandomPlatforms()
  for y = 0, MH - 1 do for x = 0, MW - 1 do if map[y][x] == 1 then tileHP[y][x] = TILE_MAX_HP end end end
end

function setTile(tx, ty, v, kind)
  if tx < 0 or tx >= MW or ty < 0 or ty >= MH then return end
  mapDirty = true
  map[ty][tx] = v; tileHP[ty][tx] = v == 1 and TILE_MAX_HP or 0; tileKind[ty][tx] = v == 1 and (kind or 0) or 0
end

function damageTile(tx, ty)
  if tx <= 0 or tx >= MW - 1 or ty <= 0 or ty >= MH - 2 then return end
  if map[ty][tx] ~= 1 then return end
  tileHP[ty][tx] = tileHP[ty][tx] - 1
  mapDirty = true
  local px, py = tx * TW + TW / 2, ty * TH + TH / 2
  if tileHP[ty][tx] <= 0 then
    map[ty][tx] = 0; tileHP[ty][tx] = 0; tileKind[ty][tx] = 0
    for d = -2, 2 do
      local dtx = tx + d
      if dtx >= 0 and dtx < MW then dustPiles[dtx] = min(DUST_MAX, dustPiles[dtx] + TH * (1.1 - math.abs(d) * .3)) end
    end
    for _ = 1, 18 do
      local a, s = love.math.random() * math.pi * 2, love.math.random() * 4 + .5
      particles[#particles + 1] = { x = px + rnd(-6, 6), y = py + rnd(-4, 4), vx = math.cos(a) * s, vy = math.sin(a) * s - 1.5,
        life = rnd(18, 45), col = love.math.random() < .5 and lvl.dust or lvl.dustT, size = rnd(1, 4) }
    end
  else
    for _ = 1, 4 do
      local a, s = love.math.random() * math.pi * 2, love.math.random() * 2
      particles[#particles + 1] = { x = px, y = py, vx = math.cos(a) * s, vy = math.sin(a) * s, life = rnd(6, 16), col = lvl.crack2, size = 1 }
    end
  end
end

function pushDust(bx, bw)
  local tx0, tx1 = floor(bx / TW), floor((bx + bw) / TW)
  for tx = tx0, tx1 do
    if tx >= 0 and tx < MW then
      local push = min(dustPiles[tx], TH * .18)
      dustPiles[tx] = dustPiles[tx] - push
      if tx > 0 then dustPiles[tx - 1] = min(DUST_MAX, dustPiles[tx - 1] + push * .4) end
      if tx < MW - 1 then dustPiles[tx + 1] = min(DUST_MAX, dustPiles[tx + 1] + push * .4) end
    end
  end
end

function dustSurfaceUnder(bx, bw)
  local fy = FLOOR_PX()
  local tx0, tx1 = max(0, floor(bx / TW)), min(MW - 1, floor((bx + bw - 1) / TW))
  local m = fy
  for tx = tx0, tx1 do if dustPiles[tx] > 2 then m = min(m, fy - dustPiles[tx]) end end
  return m
end

function solid(tx, ty)
  if tx < 0 or tx >= MW or ty < 0 or ty >= MH then return true end
  return map[ty][tx] == 1
end
local function isHardSolid(tx, ty) return tx <= 0 or tx >= MW - 1 or ty >= MH - 2 or ty <= 0 end
function solidFull(tx, ty)
  if tx < 0 or tx >= MW or ty < 0 or ty >= MH then return true end
  if map[ty][tx] ~= 1 then return false end
  return isHardSolid(tx, ty)
end
function solidOneWayTop(tx, ty)
  if tx < 0 or tx >= MW or ty < 0 or ty >= MH then return false end
  return map[ty][tx] == 1 and not isHardSolid(tx, ty)
end

-- ── Body physics (one-way platforms, swept landing) ─────────
Body = {}
Body.__index = Body
function newBody(x, y, w, h)
  return setmetatable({ x = x, y = y, w = w, h = h, vx = 0, vy = 0, onGround = false, dropT = 0 }, Body)
end
function Body:step(grav)
  grav = grav or .45
  self.vy = min(self.vy + grav, TH - 1)
  self.x = self.x + self.vx; self:_rx()
  local prevB = self.y + self.h
  self.y = self.y + self.vy; self.onGround = false; self:_ry(prevB)
  if self.dropT > 0 then self.dropT = self.dropT - 1 end
end
local function hd(px, py) return solidFull(floor(px / TW), floor(py / TH)) end
function Body:_rx()
  local l, r, t, b = self.x, self.x + self.w - 1, self.y + 4, self.y + self.h - 5
  if hd(l, t) or hd(l, b) then self.x = (floor(l / TW) + 1) * TW; self.vx = 0 end
  if hd(r, t) or hd(r, b) then self.x = floor(r / TW) * TW - self.w; self.vx = 0 end
end
function Body:_ry(prevB)
  local l, r = self.x + 2, self.x + self.w - 3
  if hd(l, self.y) or hd(r, self.y) then self.y = (floor(self.y / TH) + 1) * TH; if self.vy < 0 then self.vy = 0 end end
  if self.vy < 0 then return end
  local tl, tr = floor(l / TW), floor(r / TW)
  local B = self.y + self.h
  for ty = ceil((prevB - .01) / TH), floor(B / TH) do
    local hard = solidFull(tl, ty) or solidFull(tr, ty)
    local oneWay = self.dropT <= 0 and (solidOneWayTop(tl, ty) or solidOneWayTop(tr, ty))
    if hard or oneWay then self.y = ty * TH - self.h; self.onGround = true; self.vy = 0; return end
  end
  local bot = self.y + self.h - 1
  if hd(l, bot) or hd(r, bot) then self.y = floor(bot / TH) * TH - self.h; self.onGround = true; self.vy = 0 end
end
function Body:hits(o) return self.x < o.x + o.w and self.x + self.w > o.x and self.y < o.y + o.h and self.y + self.h > o.y end
function Body:standingOnOneWay()
  local ty = floor((self.y + self.h) / TH)
  return solidOneWayTop(floor((self.x + 2) / TW), ty) or solidOneWayTop(floor((self.x + self.w - 3) / TW), ty)
end
function checkDustLanding(p)
  if p.vy < 0 then return end
  local surf = dustSurfaceUnder(p.x, p.w)
  if p.y + p.h > surf and p.y + p.h - p.vy <= surf + 10 then p.y = surf - p.h; p.vy = 0; p.onGround = true end
end

-- ── Map drawing ─────────────────────────────────────────────
local CSEGS = { { { 2, 4, 7, 9 }, { 5, 2, 9, 8 }, { 8, 4, 4, 9 }, { 3, 6, 9, 4 } },
                { { 1, 3, 6, 8 }, { 4, 1, 10, 6 }, { 7, 3, 3, 8 }, { 2, 5, 8, 3 }, { 1, 7, 6, 12 }, { 5, 9, 11, 5 } } }
local BLACK = { 0, 0, 0 }

local function dHullTile(px, py, x, y)
  local top = y == 0 or map[y - 1][x] ~= 1
  local endL, endR = tileKind[y][x - 1] ~= 1, tileKind[y][x + 1] ~= 1
  G.rect("#2a3240", px, py, TW, TH)
  G.rect("#3c4658", px, py + 2, TW, TH - 6)
  G.rect("#1a2028", px, py + TH - 4, TW, 4)
  if top then G.rect("#8a98b0", px, py, TW, 2); G.rect("#5a6880", px, py + 2, TW, 1) end
  G.rect("#202834", px + TW - 1, py + 2, 1, TH - 6)
  G.rect("#9aa8c0", px + 3, py + 6, 1, 1); G.rect("#9aa8c0", px + 12, py + 6, 1, 1)
  if endL or endR then
    local ex = endL and px or px + TW - 5
    for k = 0, 2 do G.rect(k % 2 == 1 and "#14161c" or "#e0b020", ex, py + 3 + k * 3, 5, 3) end
  end
  if (x * 7 + y * 3) % 5 == 0 then G.rect(BLACK, px + 5, py + 4, 6, 5, .35) end
end

function dMap()
  for y = 0, MH - 1 do
    for x = 0, MW - 1 do
      if map[y][x] == 1 then
        local px, py = x * TW, y * TH
        if tileKind[y][x] == 1 then dHullTile(px, py, x, y)
        else
          G.rect(lvl.ground, px, py, TW, TH)
          if y == 0 or map[y - 1][x] ~= 1 then
            G.rect(lvl.groundTop, px, py, TW, 3); G.rect(lvl.groundAcc, px, py, TW, 1)
            if (x * 3 + y * 7) % 5 == 0 then G.rect(lvl.groundAcc, px + 3, py + 4, 2, 1) end
          end
          G.rect(BLACK, px + TW - 1, py, 1, TH, .18); G.rect(BLACK, px, py + TH - 1, TW, 1, .18)
        end
        local hp = tileHP[y][x]
        if hp > 0 and hp < TILE_MAX_HP then
          local seed, nc = (x * 31 + y * 17) % 4, hp == 1 and 2 or 1
          local arr = CSEGS[hp == 1 and 2 or 1]
          for c = 0, nc - 1 do
            local s = arr[((seed + c) % #arr) + 1]
            G.line(hp == 1 and lvl.crack2 or lvl.crack1, px + s[1], py + s[2], px + s[3], py + s[4], 1, hp == 1 and .85 or .5)
          end
          if hp == 1 then G.rect(BLACK, px, py, TW, TH, .3) end
        end
      end
    end
  end
end

function dDustPiles()
  local fy = FLOOR_PX()
  for tx = 0, MW - 1 do
    local h = dustPiles[tx]
    if h >= 1 then
      G.vgrad(tx * TW, fy - h, TW, h, { { 0, lvl.dustT }, { 1, lvl.dust } })
      G.rect({ 1, 1, 1 }, tx * TW, fy - h, TW, 2, .08)
    end
  end
end
