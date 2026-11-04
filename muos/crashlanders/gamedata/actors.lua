-- Players, modular bosses, drops, bullets and the PLAY state (update + draw + HUD)
local U = require "util"
local G = require "gfx"
local A = require "audio"
local I = require "input"
local lg = love.graphics
local rnd, clamp, lerp = U.rnd, U.clamp, U.lerp
local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt
local PI = math.pi

-- ── Palette (web build) ─────────────────────────────────────
P = {
  ship = "#8090b0", shipDark = "#404858", flame = "#ff6020",
  p1 = "#50ffc0", p1D = "#1a7050", p2 = "#ff9040", p2D = "#804010",
  gun = "#c0c0d0", bullet = "#ffff50", bulletT = "#ff8020",
  bb = "#ff5020", bbC = "#ffa060", bburst = "#ff1010", bburstC = "#ff8080",
  coin = "#ffd700", coinD = "#b08800", dmgx = "#ff40ff", dmgxD = "#800080", dmgxS = "#ffb0ff",
  para = "#40a0ff", paraD = "#204880", fire = "#ff6010", djump = "#40ff80",
  hpD = "#ffd040", hpDD = "#806010", hpG = "#20e040", hpR = "#e01010",
  white = "#ffffff", gray = "#888888", orange = "#ff8020", yellow = "#ffff40",
  gold = "#ffd700", goldD = "#8a5c00",
}
PCOLS = { { m = P.p1, d = P.p1D }, { m = P.p2, d = P.p2D } }
PW, PH, PSPD, PJMP, PHP = 10, 16, 3.6, -9.5, 100
BASE_DMG = 10
COST_WEAPON, COST_FIRE, COST_DJUMP, COST_PARA = 100, 100, 50, 200
WEAPON_NAMES = { "Pistola", "Pistola+", "Blaster", "Blaster+", "Canhao", "Canhao+", "Railgun", "Railgun+", "Devastador", "Dev.MAX" }

players, pBullets, bBullets, drops = {}, {}, {}, {}
numPlayers, levelNum = 1, 1
local function freshPersist() return { weaponLvl = 0, coins = 0, fireRate = false, doubleJump = false, parachute = false } end
persist = { freshPersist(), freshPersist() }
function resetPersist() persist = { freshPersist(), freshPersist() }; levelNum = 1 end

-- ── Players ────────────────────────────────────────────────
function initPlayers(sx, sy)
  players = {}
  for i = 1, numPlayers do
    local ps = persist[i]
    local p = newBody(sx + (i - 1) * 22, sy, PW, PH)
    p.id, p.col = i, PCOLS[i]
    p.hp, p.maxHP = PHP, PHP
    p.facing = i == 1 and 1 or -1; p.aimElev = 0; p.aimAngle = i == 1 and 0 or PI
    p.shootCD, p.iframes, p.coyote, p.jumpBuf, p.kbVx, p.airJumps = 0, 0, 0, 0, 0, 0
    p.jumpPressed = false
    p.weaponLvl, p.fireRate, p.doubleJump, p.parachute = ps.weaponLvl, ps.fireRate, ps.doubleJump, ps.parachute
    p.dmgMult, p.coins, p.reviveTimer = 1, ps.coins, 0
    p.remote = NETL ~= nil and NETL.mode == "host" and i == 2   -- LAN guest drives P2
    players[i] = p
  end
end
local function bulletDmg(p) return BASE_DMG * (1 + p.weaponLvl * .1) * p.dmgMult end
local function shootCD(p) if p.fireRate then return p.dmgMult > 1 and 6 or 9 end return p.dmgMult > 1 and 16 or 22 end

function saveToPersist()
  for i = 1, numPlayers do
    local p, ps = players[i], persist[i]
    ps.weaponLvl, ps.coins, ps.fireRate, ps.doubleJump, ps.parachute = p.weaponLvl, p.coins, p.fireRate, p.doubleJump, p.parachute
  end
  saveGame()
end

-- ── Modular boss: 7 slots × 3 parts, mirrored half-rows on a 15×16 grid ──
local BCELL, BFW, BFH = 4, 15, 16
BW, BH, BMAXHP, BURST_INTERVAL = 52, 52, 2000, 1200
local BOSS_PARTS = {
  back = { { id = "espinhos", y = 0, h = { "..w...w.", "..ow..ow", "..od..od", ".oddoodd" } },
           { id = "tubos", y = 1, h = { ".ooo....", "oaao....", "oa.oo...", "oa..oo..", "ooo..o.." } },
           { id = "nenhum", y = 0, h = {} } },
  legs = { { id = "bipede", y = 12, h = { "...oddo.", "...odmo.", "..oddmo.", "..ooooo." } },
           { id = "aranha", y = 11, h = { "..oo.o..", ".oo..o..", ".o..oo..", "oo..o...", "o...o..." } },
           { id = "jatos", y = 12, h = { "....oooo", "....odad", ".....f.f", "......f." } } },
  body = { { id = "carapaca", y = 3, h = { "....oooo", "..oodmmm", ".odmlsll", ".odmlmmm", ".odmmmmo", ".odmmmmo", ".oddmmmo", "..odddmo", "...ooooo" } },
           { id = "saco", y = 3, h = { ".....ooo", "...oommm", "..ommlsl", ".ommmmml", ".omdmmmm", "omdmmaaa", "omdmaaaa", "omddmaaa", ".oddmmmm", "..oooddd", "....oooo" } },
           { id = "blindado", y = 3, h = { "..oooooo", ".odddddd", ".omlslll", ".ommmmmm", ".ooooooo", ".odlslll", ".odmmmmm", ".ooooooo", ".odlllll", "..oddddd", "..oooooo" } } },
  arms = { { id = "garras", y = 5, h = { ".oo", "omm", "omd", "omd", "oow", "ow.w", "w..." } },
           { id = "canhoes", y = 5, h = { ".ooo", "odmm", "odlm", "odmm", "oooo", "aao.", "oo.." } },
           { id = "tentaculos", y = 6, h = { "..om", ".omm", ".om.", "om..", "om..", ".om.", "..a." } } },
  head = { { id = "chifres", y = 0, h = { ".o......", ".wo.....", "..wo....", "..ww....", "...w...." } },
           { id = "crista", y = 0, h = { ".......o", "......ol", "......om", ".....oam", ".....omm" } },
           { id = "cupula", y = 1, h = { "....oooo", "...oaaal", "..oaasaa", "..oaaaaa" } } },
  eyes = { { id = "ciclope", y = 5, h = { ".....ooo", "....oeee", "....oepp", ".....ooo" } },
           { id = "gemeos", y = 5, h = { "..oo....", "..oeeo..", "..oepeo.", "...oooo." } },
           { id = "composto", y = 5, h = { "..ee.ee.", "..ep.pe.", "........", "......ee", "......ep" } } },
  mouth = { { id = "presas", y = 9, h = { "...ooooo", "...wowow", "....w..." } },
            { id = "mandibulas", y = 9, h = { ".w...ooo", ".ww..odd", "..www.oo", "....w..." } },
            { id = "grelha", y = 9, h = { "....oooo", "....oaoa", "....oaoa", "....oooo" } } },
}
local BOSS_ORDER = { "back", "legs", "body", "arms", "head", "eyes", "mouth" }
local BOSS_BOB = { back = true, body = true, arms = true, head = true, eyes = true, mouth = true }
local BNAME_A = { carapaca = "KRA", saco = "GLO", blindado = "VOR" }
local BNAME_B = { ciclope = "MOX", gemeos = "ZIK", composto = "THUL" }
local BNAME_C = { bipede = "O ESMAGADOR", aranha = "O RASTEJANTE", jatos = "O FLUTUANTE" }

local function mirrorRow(r)
  r = (r .. "........"):sub(1, 8)
  return r .. r:sub(1, 7):reverse()
end
for _, list in pairs(BOSS_PARTS) do      -- pre-mirror every row once
  for _, p in ipairs(list) do p.full = {}; for i, r in ipairs(p.h) do p.full[i] = mirrorRow(r) end end
end

local function composeBoss(parts, bob, blink, mouthOpen, facing)
  local g = {}
  for y = 0, BFH do local r = {}; for x = 0, BFW - 1 do r[x] = "." end; g[y] = r end
  for _, s in ipairs(BOSS_ORDER) do
    local p = parts[s]
    local dy = (BOSS_BOB[s] and bob or 0) + ((s == "mouth" and mouthOpen) and 1 or 0)
    for i, f in ipairs(p.full) do
      local y = p.y + (i - 1) + dy
      if y >= 0 and y <= BFH then
        for x = 0, BFW - 1 do
          local c = f:sub(x + 1, x + 1)
          if c ~= "." then
            if s == "eyes" and blink and (c == "e" or c == "p") then c = "d" end
            g[y][x] = c
          end
        end
      end
    end
  end
  if not blink and facing ~= 0 then
    for y = 0, BFH do
      local row = g[y]; local src = {}
      for x = 0, BFW - 1 do src[x] = row[x] end
      for x = 0, BFW - 1 do
        if src[x] == "p" then
          local nx = x + facing
          if nx >= 0 and nx < BFW and src[nx] == "e" then row[nx] = "p"; if src[x - facing] ~= "p" then row[x] = "e" end end
        end
      end
    end
  end
  return g
end

local function bossPalette(mode)
  local h = lvl.bossHue
  if mode == "flash" then local w = { 1, 1, 1 }; return { o = w, d = w, m = w, l = w, s = w, a = w, e = w, p = w, w = w, f = w } end
  local k = mode == "bright" and 14 or 0
  local Pl = { o = U.hsl(h, 50, 8), d = U.hsl(h, 60, 24 + k), m = U.hsl(h, 60, 42 + k), l = U.hsl(h, 65, 62 + k), s = U.hsl(h, 40, 86),
    a = U.hsl(h + 180, 95, 60), e = U.hsl(h + 180, 90, 72), p = U.hex("#1a0008"), w = U.hsl(45, 35, 82), f = U.hex("#ffb020") }
  if mode == "burst" then Pl.d = U.hex("#600000"); Pl.m = U.hex("#d01010"); Pl.l = U.hex("#ff5040"); Pl.e = { 1, 1, 1 }; Pl.p = { 1, 0, 0 }; Pl.a = U.hex("#ff3020") end
  return Pl
end

-- EPX (Scale2x) upscale: smooth diagonals at the player's pixel density
local function epx(g, h, w)
  local o = {}
  for y = 0, h * 2 - 1 do o[y] = {} end
  local function at(y, x) if y < 0 or y >= h or x < 0 or x >= w then return "." end return g[y][x] end
  for y = 0, h - 1 do for x = 0, w - 1 do
    local Pc, Ac, Bc, Cc, Dc = g[y][x], at(y - 1, x), at(y, x + 1), at(y, x - 1), at(y + 1, x)
    local p1, p2, p3, p4 = Pc, Pc, Pc, Pc
    if Cc == Ac and Cc ~= Dc and Ac ~= Bc then p1 = Ac end
    if Ac == Bc and Ac ~= Cc and Bc ~= Dc then p2 = Bc end
    if Dc == Cc and Dc ~= Bc and Cc ~= Ac then p3 = Cc end
    if Bc == Dc and Bc ~= Ac and Dc ~= Cc then p4 = Dc end
    o[2 * y][2 * x], o[2 * y][2 * x + 1], o[2 * y + 1][2 * x], o[2 * y + 1][2 * x + 1] = p1, p2, p3, p4
  end end
  return o
end

local spriteCache, cacheN = {}, 0
local function bossSprite(g, pal, key)
  local c = spriteCache[key]
  if c then return c end
  if cacheN > 96 then spriteCache = {}; cacheN = 0 end
  local h, w = BFH + 1, BFW
  local g2 = epx(g, h, w)
  local g4 = epx(g2, h * 2, w * 2)
  local id = love.image.newImageData(w * 4, h * 4)
  for y = 0, h * 4 - 1 do for x = 0, w * 4 - 1 do
    local v = g4[y][x]
    local q = v ~= "." and pal[v]
    if q then id:setPixel(x, y, q[1], q[2], q[3], 1) end
  end end
  c = lg.newImage(id)
  c:setFilter("nearest", "nearest")
  spriteCache[key] = c; cacheN = cacheN + 1
  return c
end

boss, bossSpawned, bossCountdown, anyMoved = nil, false, 300, false
function bossPartIds() local t = {}; for i, s in ipairs(BOSS_ORDER) do t[i] = boss.parts[s].id end; return t end
function bossPartsFromIds(ids)
  local parts = {}
  for i, s in ipairs(BOSS_ORDER) do
    for _, p in ipairs(BOSS_PARTS[s]) do if p.id == ids[i] then parts[s] = p end end
    parts[s] = parts[s] or BOSS_PARTS[s][1]
  end
  return parts
end

function spawnBoss()
  A.stopMusic()
  local bx = TW * 3 + rnd(0, SW - TW * 6 - BW)
  boss = newBody(bx, MH * TH + 30, BW, BH)
  boss.hp, boss.maxHP = BMAXHP, BMAXHP
  boss.facing, boss.state, boss.stateTimer = -1, "IDLE", 90
  boss.atkCD, boss.jumpCD, boss.phaseDrops, boss.chargeDir = 0, 0, 0, 1
  boss.rising, boss.riseTarget = true, MH * TH - TH * 2 - BH - 4
  boss.hitCounter, boss.dmgDropped = 0, false
  boss.lastX, boss.stuckTimer, boss.jumpsLeft = 0, 0, 2
  boss.burstTimer, boss.burstState, boss.burstWindup = rnd(300, 600), "NONE", 0
  boss.flash, boss.laserT, boss.laserAng, boss.pendingShot, boss.mouthT, boss.slamming = 0, 0, 0, 0, 0, false
  boss.parts = {}
  for _, s in ipairs(BOSS_ORDER) do local a = BOSS_PARTS[s]; boss.parts[s] = a[rnd(1, #a + 1)] end
  boss.legs, boss.arms, boss.eyes = boss.parts.legs.id, boss.parts.arms.id, boss.parts.eyes.id
  boss.name = BNAME_A[boss.parts.body.id] .. "'" .. BNAME_B[boss.parts.eyes.id] .. " " .. BNAME_C[boss.parts.legs.id]
  bossSpawned = true
end

-- ── Drops ──────────────────────────────────────────────────
local function dropCol(t) return t == "COIN" and P.coin or t == "DMGX2" and P.dmgx or P.hpD end
local function spawnDrop(x, y, t)
  local d = newBody(x - 6, y - 6, 12, 12); d.bob = 0; d.type = t or "HP"
  drops[#drops + 1] = d
  fx(x, y, 20, dropCol(d.type), 5, 3)
end
local function applyDrop(p, t)
  if t == "HP" then p.hp = min(p.maxHP, p.hp + 40); A.play("pickup") end
  if t == "COIN" then p.coins = p.coins + 5; A.play("coin") end
  if t == "DMGX2" then p.dmgMult = 2; A.play("revive") end
end

-- ── Player update ─────────────────────────────────────────
local REVIVE_HP, REVIVE_COST, REVIVE_RANGE, REVIVE_TIME = 30, 20, 14, 90
local function bossContactMul() return boss and boss.arms == "garras" and 1.5 or 1 end

local function uPlayer(p)
  local id = p.id
  local L, R = PIN(p, "left"), PIN(p, "right")
  local shootHeld, jumpHeld, downHeld = PIN(p, "shoot"), PIN(p, "jump"), PIN(p, "down")
  p.jh, p.sh = jumpHeld, shootHeld
  p.vx = (R and PSPD or 0) - (L and PSPD or 0) + p.kbVx
  p.kbVx = p.kbVx * .82; if abs(p.kbVx) < .1 then p.kbVx = 0 end
  if not shootHeld then if L and not R then p.facing = -1 elseif R and not L then p.facing = 1 end end
  if PIN(p, "up") then p.aimElev = p.aimElev - .08 end
  if downHeld then p.aimElev = p.aimElev + .08 end
  p.aimElev = clamp(p.aimElev, -PI / 2, PI / 2)
  p.aimAngle = p.facing > 0 and p.aimElev or PI - p.aimElev

  if p.onGround then p.coyote = 6; p.airJumps = p.doubleJump and 1 or 0
  elseif p.coyote > 0 then p.coyote = p.coyote - 1 end
  local wasOnGround = p.onGround
  local freshJump = jumpHeld and not p.jumpPressed
  if freshJump then p.jumpBuf = 7 elseif p.jumpBuf > 0 then p.jumpBuf = p.jumpBuf - 1 end
  if p.jumpBuf > 0 then
    if freshJump and downHeld and p.onGround and p:standingOnOneWay() then
      p.dropT = 10; p.y = p.y + 2; p.onGround = false; p.coyote = 0; p.jumpBuf = 0
    elseif p.coyote > 0 then
      p.vy = PJMP; p.coyote = 0; p.jumpBuf = 0; A.play("jump")
    elseif freshJump and p.airJumps > 0 then
      p.vy = PJMP * .88; p.airJumps = p.airJumps - 1; p.jumpBuf = 0; fx(p.x + PW / 2, p.y + PH, 6, p.col.m, 2, 2); A.play("jumpAir")
    end
  end
  p.jumpPressed = jumpHeld
  if not jumpHeld and p.vy < -3 then p.vy = p.vy + .8 end
  if p.parachute and jumpHeld and p.vy > 1.5 and not p.onGround then
    p.vy = lerp(p.vy, 1.5, .18)
    if gFrame % 6 == id - 1 then fx(p.x + PW / 2, p.y - 2, 1, P.para, 1.5, 2); if gFrame % 24 == (id - 1) * 12 then A.play("para") end end
  end
  p:step(); checkDustLanding(p); p.x = clamp(p.x, TW + 1, SW - TW - PW - 1)
  if p.onGround and not wasOnGround and p.vy == 0 then A.play("land") end

  p.shootCD = p.shootCD - 1
  if shootHeld and p.shootCD <= 0 then
    local pcx, pcy = p.x + PW / 2, p.y + PH / 2
    local vx, vy = math.cos(p.aimAngle) * 11, math.sin(p.aimAngle) * 11
    pBullets[#pBullets + 1] = { x = pcx + vx * .5, y = pcy + vy * .5, vx = vx, vy = vy, life = 70, pid = id, dmg = bulletDmg(p) }
    p.shootCD = shootCD(p)
    fx(pcx + vx * .9, pcy + vy * .9, 2, p.dmgMult > 1 and P.dmgx or P.yellow, 2, 1)
    A.play("shoot")
  end

  if p.iframes <= 0 then
    for i = #bBullets, 1, -1 do
      local b = bBullets[i]
      if p:hits({ x = b.x - b.r, y = b.y - b.r, w = b.r * 2, h = b.r * 2 }) then
        p.hp = p.hp - (b.dmg or 12); p.iframes = 70; p.kbVx = (p.x < b.x and -1 or 1) * 4; p.vy = -3
        fx(p.x + PW / 2, p.y + PH / 2, 8, p.col.m, 3, 2); table.remove(bBullets, i); A.play("hit")
        break
      end
    end
    if boss and boss.hp > 0 and p.iframes <= 0 and p:hits(boss) then
      local ox = min(p.x + p.w - boss.x, boss.x + BW - p.x)
      local oy = min(p.y + p.h - boss.y, boss.y + BH - p.y)
      local pushLeft = p.x < boss.x + BW / 2
      if ox < oy then
        local trapped = (pushLeft and p.x <= TW + PW + 2) or ((not pushLeft) and p.x + p.w >= SW - TW - PW - 2)
        if trapped then p.y = boss.y - p.h - 1; p.vy = -4; p.onGround = false
        else p.x = pushLeft and boss.x - p.w or boss.x + BW; p.vx = 0 end
        p.hp = p.hp - 18 * bossContactMul(); p.iframes = 90; p.kbVx = (pushLeft and -1 or 1) * 5; p.vy = -4
        fx(p.x + PW / 2, p.y + PH / 2, 10, P.orange, 4, 2); shake = max(shake, 8); A.play("hit")
      else
        if p.y + p.h / 2 < boss.y + BH / 2 then p.y = boss.y - p.h; p.vy = 0; p.onGround = true
        else
          p.hp = p.hp - 12 * bossContactMul(); p.iframes = 60; p.vy = 2; fx(p.x + PW / 2, p.y, 6, P.orange, 3, 2); A.play("hit")
          p.y = boss.y + BH; p.vy = max(p.vy, 1)
        end
      end
    end
  else p.iframes = p.iframes - 1 end
end

local function uDeadPlayer(p) p.vx = 0; p.kbVx = 0; p:step(); checkDustLanding(p) end

-- ── Boss attacks & AI ───────────────────────────────────────
local function bossFire(x, y, ang, das, spd, wave)
  boss.mouthT = max(boss.mouthT, 10)
  for _, da in ipairs(das) do
    bBullets[#bBullets + 1] = { x = x, y = y, vx = math.cos(ang + da) * spd, vy = math.sin(ang + da) * spd, life = 130, r = 5, dmg = 12, wave = wave, t = 0 }
  end
end
local function bossVolley(tgt)
  local bcx, bcy = boss.x + BW / 2, boss.y + BH / 2
  local tx, ty = tgt.x + PW / 2, tgt.y + PH / 2
  if boss.eyes == "composto" then
    local tt = sqrt((tx - bcx) ^ 2 + (ty - bcy) ^ 2) / 5
    tx = tx + tgt.vx * tt; ty = ty + clamp(tgt.vy, -4, 4) * tt * .4
  end
  local ang, half = math.atan2(ty - bcy, tx - bcx), boss.hp < BMAXHP * .5
  local das
  if boss.arms == "canhoes" then das = half and { -.5, -.25, 0, .25, .5 } or { -.28, 0, .28 }
  else das = half and { -.28, 0, .28 } or { 0 } end
  bossFire(bcx, bcy, ang, das, 5, boss.arms == "tentaculos")
  A.play("bossShoot")
end

local function uBoss()
  pushDust(boss.x, BW)
  if boss.flash > 0 then boss.flash = boss.flash - 1 end
  if not boss.rising then
    boss.burstTimer = boss.burstTimer + 1
    if boss.burstTimer >= BURST_INTERVAL and boss.burstState == "NONE" then boss.burstState = "WINDUP"; boss.burstWindup = 0; boss.burstTimer = 0; A.play("burst") end
    if boss.burstState == "WINDUP" then
      boss.burstWindup = boss.burstWindup + 1; boss.vx = boss.vx * .6
      if boss.burstWindup % 6 == 0 then fx(boss.x + BW / 2, boss.y + BH / 2, 10, "#ff0000", 6, 3); shake = max(shake, 4) end
      if boss.burstWindup >= 80 then
        local bcx, bcy = boss.x + BW / 2, boss.y + BH / 2
        for i = 0, 23 do
          local a = (i / 24) * PI * 2
          bBullets[#bBullets + 1] = { x = bcx, y = bcy, vx = math.cos(a) * 1.8, vy = math.sin(a) * 1.8, life = 380, r = 8, dmg = 24, burst = true }
        end
        boss.burstState = "NONE"; shake = 30; fx(bcx, bcy, 60, "#ff2020", 10, 4)
      end
    end
  end
  if boss.rising then
    boss.y = lerp(boss.y, boss.riseTarget, .065); boss.x = lerp(boss.x, (SW - BW) / 2, .04)
    if boss.y <= boss.riseTarget + 2 then boss.rising = false; fx(boss.x + BW / 2, boss.y + BH, 25, lvl.bossAcc, 5, 3); shake = 20 end
    boss.lastX = boss.x
    return
  end
  if boss.onGround then boss.jumpsLeft = 2 end
  local tgt, best = nil, 1e9
  for _, p in ipairs(players) do
    if p.hp > 0 then local d = (p.x - boss.x) ^ 2 + (p.y - boss.y) ^ 2; if d < best then best = d; tgt = p end end
  end
  if not tgt then return end
  local pcx, pcy = tgt.x + PW / 2, tgt.y + PH / 2
  local bcx, bcy = boss.x + BW / 2, boss.y + BH / 2
  boss.facing = pcx < bcx and -1 or 1

  if boss.mouthT > 0 then boss.mouthT = boss.mouthT - 1 end
  if boss.laserT > 0 then
    boss.laserT = boss.laserT - 1; boss.vx = boss.vx * .7
    if boss.laserT == 0 then
      for k = 0, 5 do bossFire(bcx + math.cos(boss.laserAng) * k * 12, bcy + math.sin(boss.laserAng) * k * 12, boss.laserAng, { 0 }, 9, false) end
      shake = max(shake, 6); A.play("laser")
    end
  end
  if boss.pendingShot > 0 then boss.pendingShot = boss.pendingShot - 1; if boss.pendingShot == 0 then bossVolley(tgt) end end

  if boss.burstState ~= "WINDUP" then
    boss.stateTimer = boss.stateTimer - 1; boss.atkCD = boss.atkCD - 1; boss.jumpCD = boss.jumpCD - 1
    if abs(boss.x - boss.lastX) < .4 then boss.stuckTimer = boss.stuckTimer + 1 else boss.stuckTimer = 0 end
    boss.lastX = boss.x
    if boss.stuckTimer > 25 then
      boss.stuckTimer = 0
      if boss.jumpsLeft > 0 then boss.vy = PJMP * .88; boss.jumpsLeft = boss.jumpsLeft - 1; fx(boss.x + BW / 2, boss.y + BH, 10, lvl.bossAcc, 4, 2)
      else boss.chargeDir = -boss.chargeDir; boss.state = "JUMP"; boss.stateTimer = rnd(40, 80); boss.jumpCD = 0 end
    end
    if boss.stateTimer <= 0 then
      local r, rage = love.math.random(), boss.hp < BMAXHP * .4
      if r < .28 then boss.state = "WALK" elseif r < .5 then boss.state = "CHARGE"
      elseif r < (rage and .65 or .7) then boss.state = "JUMP" else boss.state = "SHOOT" end
      if boss.legs == "aranha" and boss.state == "JUMP" then boss.state = "CHARGE" end
      boss.stateTimer = rnd(50, 110); boss.chargeDir = boss.facing
      if boss.state == "SHOOT" then boss.atkCD = 0 end
    end
    if boss.state == "WALK" then boss.vx = lerp(boss.vx, boss.facing * 2.4, .1)
    elseif boss.state == "CHARGE" then
      boss.vx = lerp(boss.vx, boss.chargeDir * (boss.legs == "aranha" and 10.4 or 8), .15)
      if boss.x <= TW + 2 or boss.x + BW >= SW - TW - 2 then boss.chargeDir = -boss.chargeDir; fx(boss.x + BW / 2, boss.y + BH / 2, 8, lvl.bossAcc, 3, 2) end
    elseif boss.state == "JUMP" then
      boss.vx = lerp(boss.vx, boss.facing * 3.5, .12)
      if boss.legs == "jatos" then
        if boss.jumpCD <= 0 and not boss.slamming then boss.vy = 12; boss.jumpCD = 70; boss.slamming = true; A.play("slam") end
      elseif boss.onGround and boss.jumpCD <= 0 then
        boss.vy = boss.legs == "bipede" and -15 or -13.5; boss.jumpCD = 45; shake = max(shake, 5); A.play("bossJump")
      end
    elseif boss.state == "SHOOT" then
      boss.vx = boss.vx * .82
      if boss.atkCD <= 0 and boss.laserT <= 0 then
        if boss.eyes == "ciclope" then
          boss.laserT = 36; boss.laserAng = math.atan2(pcy - bcy, pcx - bcx); boss.mouthT = 36
          boss.atkCD = boss.hp < BMAXHP * .3 and 48 or 66; A.play("charge")
        else
          bossVolley(tgt)
          if boss.eyes == "gemeos" then boss.pendingShot = 9 end
          boss.atkCD = (boss.hp < BMAXHP * .3 and 20 or 33) + (boss.eyes == "gemeos" and 10 or 0)
        end
      end
    end
  end
  local wasGround = boss.onGround
  boss.vx = boss.vx * .87
  if boss.legs == "jatos" then
    boss.dropT = 2
    if boss.slamming then
      boss:step(.6)
      if boss.onGround then boss.slamming = false; shake = max(shake, 14); fx(bcx, boss.y + BH, 20, lvl.dust, 5, 3); A.play("land") end
    else
      local want = clamp(tgt.y - BH - 36, TH * 3, MH * TH - TH * 2 - BH)
      boss.vy = lerp(boss.vy, (want - boss.y) * .06, .12)
      boss:step(0)
      if gFrame % 3 == 0 then fx(bcx + rnd(-8, 8), boss.y + BH + 4, 1, "#ffb020", 1.5, 2) end
    end
  else
    boss:step(.5)
    if boss.legs == "bipede" and boss.onGround and not wasGround then shake = max(shake, 12); fx(bcx, boss.y + BH, 16, lvl.dust, 4, 3); A.play("land") end
  end
  boss.x = clamp(boss.x, TW + 1, SW - TW - BW - 1)

  for i = #pBullets, 1, -1 do
    local b = pBullets[i]
    if boss:hits({ x = b.x - 2, y = b.y - 2, w = 5, h = 5 }) then
      boss.hp = max(0, boss.hp - (b.dmg or 10)); table.remove(pBullets, i); boss.flash = 3
      fx(b.x, b.y, 4, P.hpR, 2, 2); shake = max(shake, 2); A.play("bossHit")
      boss.hitCounter = boss.hitCounter + 1
      if boss.hitCounter % 5 == 0 and boss.hp > 0 then spawnDrop(bcx + rnd(-22, 22), bcy - rnd(5, 20), "COIN") end
      if not boss.dmgDropped and boss.hp <= BMAXHP * .5 and boss.hp > 0 then
        boss.dmgDropped = true; spawnDrop(bcx, bcy - 25, "DMGX2"); shake = max(shake, 25); bBullets = {}
      end
      local pct = floor((BMAXHP - boss.hp) / (BMAXHP * .05))
      if pct > boss.phaseDrops and boss.hp > 0 then boss.phaseDrops = pct; spawnDrop(bcx + rnd(-15, 15), bcy, "HP"); shake = max(shake, 12) end
    end
  end
end

-- ── PLAY state ─────────────────────────────────────────────
function uPlay()
  if not bossSpawned then
    if anyMoved then bossCountdown = bossCountdown - 1 end
    if bossCountdown <= 0 then spawnBoss() end
  end
  for _, p in ipairs(players) do if p.hp > 0 then uPlayer(p) else uDeadPlayer(p) end end
  if bossSpawned and boss and boss.hp > 0 then uBoss() end

  if numPlayers == 2 then
    for _, pr in ipairs({ { players[1], players[2] }, { players[2], players[1] } }) do
      local alive, dead = pr[1], pr[2]
      if alive.hp > 0 and dead.hp <= 0 then
        local dist = abs((alive.x + PW / 2) - (dead.x + PW / 2))
        if dist < REVIVE_RANGE + PW and abs(alive.y - dead.y) < PH then
          dead.reviveTimer = dead.reviveTimer + 1
          if dead.reviveTimer >= REVIVE_TIME then
            dead.hp = REVIVE_HP; dead.iframes = 120; dead.reviveTimer = 0
            alive.hp = max(1, alive.hp - REVIVE_COST)
            fx(dead.x + PW / 2, dead.y + PH / 2, 20, dead.col.m, 5, 3); fx(dead.x + PW / 2, dead.y + PH / 2, 10, P.hpG, 3, 2)
            A.play("revive"); shake = max(shake, 8)
          end
        else dead.reviveTimer = 0 end
      end
    end
  end

  for i = #pBullets, 1, -1 do
    local b = pBullets[i]
    b.x = b.x + b.vx; b.y = b.y + b.vy; b.life = b.life - 1
    local tx, ty = floor(b.x / TW), floor(b.y / TH)
    if b.life <= 0 then fx(b.x, b.y, 3, P.bullet, 2, 1); table.remove(pBullets, i)
    elseif solid(tx, ty) then damageTile(tx, ty); fx(b.x, b.y, 3, P.bullet, 2, 1); table.remove(pBullets, i) end
  end
  for i = #bBullets, 1, -1 do
    local b = bBullets[i]
    b.x = b.x + b.vx; b.y = b.y + b.vy; b.life = b.life - 1
    if b.wave then
      b.t = b.t + 1
      local k, sp = math.cos(b.t * .18) * 1.8, sqrt(b.vx * b.vx + b.vy * b.vy)
      if sp == 0 then sp = 1 end
      b.x = b.x - b.vy / sp * k; b.y = b.y + b.vx / sp * k
    end
    if b.life <= 0 or solid(floor(b.x / TW), floor(b.y / TH)) then table.remove(bBullets, i) end
  end
  for i = #drops, 1, -1 do
    local d = drops[i]
    d.bob = d.bob + .08; d:step(.3)
    for _, p in ipairs(players) do
      if p.hp > 0 and d:hits(p) then applyDrop(p, d.type); fx(d.x + 6, d.y + 6, 14, dropCol(d.type), 4, 2); table.remove(drops, i); break end
    end
  end
  if bossSpawned and boss and boss.hp <= 0 and gState == "PLAY" then
    A.play("levelEnd"); A.play("explode")
    extractShip = { x = boss.x + BW / 2 - 28, y = boss.y - 60, vy = 2, landed = false, lifting = false }
    for _, p in ipairs(players) do p.boarded = false end
    extractTimer = 0; gState = "EXTRACT"
  end
  local allDead = #players > 0
  for _, p in ipairs(players) do if p.hp > 0 then allDead = false end end
  if allDead then A.play("death"); enterDead() end
end

-- ── Drawing ────────────────────────────────────────────────
local fonts = {}
local function F(kind, size) local k = kind .. size; if not fonts[k] then fonts[k] = G.font(kind, size) end; return fonts[k] end

function dPlayer(p)
  local x, y = floor(p.x + .5), floor(p.y + .5)
  if p.hp <= 0 then
    if floor(gFrame / 18) % 2 ~= 0 then return end
    G.rect(p.col.d, x, y + PH - 6, PW, 6, .45)
    G.rect("#333344", x + 1, y + PH - 5, PW - 2, 4, .45)
    G.rect(p.col.m, x + 2, y + PH - 12, PW - 4, 7, .45)
    G.text("x", x + PW / 2, y + PH - 6, "center", F("mono", 9), "#ff2020")
    local prog = p.reviveTimer / REVIVE_TIME
    if prog > 0 then
      local bw, bx, by2 = PW + 12, x - 6, y + PH - 18
      G.rect({ 0, 0, 0 }, bx, by2, bw, 5, .7)
      G.rect(P.hpG, bx, by2, bw * prog, 5)
      G.srect(p.col.m, bx, by2, bw, 5, 1)
      G.text("REVIVER", x + PW / 2, by2 - 2, "center", F("mono", 9), P.hpG)
    end
    return
  end
  local f, ang = p.facing, p.aimAngle
  local ghost = p.iframes > 0 and gFrame % 6 < 3
  local pcx, pcy = x + PW / 2, y + PH / 2 - 1
  local isPara = p.parachute and p.jh and p.vy > 1.5 and not p.onGround
  local ga = ghost and .35 or 1
  if p.onGround then G.rect({ 0, 0, 0 }, x + 1, y + PH, PW - 2, 2, .28 * ga) end
  G.rect(p.col.d, x + 1, y + 5, PW - 2, PH - 5, ga)
  G.rect(p.col.m, x + 2, y + 5, PW - 4, PH - 7, ga)
  G.rect(p.col.m, x + 1, y, PW - 2, 7, ga)
  G.rect("#002828", x + 2 + (f > 0 and 2 or 0), y + 1, 4, 3, ga)
  G.rect("#40ffff", x + 2 + (f > 0 and 2 or 0), y + 1, 4, 1, ga)
  G.rect(p.col.d, x + 1, y, 1, 7, ga); G.rect(p.col.d, x + PW - 2, y, 1, 7, ga)
  if p.id == 2 then G.rect(P.p2, x + PW / 2 - 1, y - 3, 3, 2, ga) end
  G.rect("#606080", f > 0 and x or x + PW - 3, y + 5, 3, 8, ga)
  if isPara then
    local pw2, ph2 = 22, 12
    local px2, py2 = x + PW / 2 - pw2 / 2, y - ph2 - 4
    G.rect(P.paraD, px2, py2, pw2, ph2, ga); G.rect(P.para, px2 + 1, py2 + 1, pw2 - 2, ph2 - 3, ga)
    G.line(P.paraD, px2 + 4, py2 + ph2, x + 2, y, 1, ga); G.line(P.paraD, px2 + pw2 - 4, py2 + ph2, x + PW - 3, y, 1, ga)
  end
  lg.push(); lg.translate(pcx, pcy + 2); lg.rotate(ang)
  G.rect(p.col.d, 0, -2, 10, 4, ga)
  G.rect(p.dmgMult > 1 and P.dmgx or P.gun, 4, -2, 8, 4, ga)
  G.rect("#505060", 10, -1, 3, 2, ga)
  G.rect((p.sh and p.shootCD < 4) and (p.dmgMult > 1 and P.dmgx or P.yellow) or "#404050", 13, -1, 2, 2, ga)
  lg.pop()
  local walk, lp = p.onGround and abs(p.vx) > .5, floor(gFrame / 7) % 2 == 1
  if walk then
    G.rect(p.col.d, x + 1, y + PH - 4 + (lp and 0 or 2), 3, 4, ga); G.rect(p.col.d, x + PW - 4, y + PH - 4 + (lp and 2 or 0), 3, 4, ga)
  else
    G.rect(p.col.d, x + 1, y + PH - 4, 3, 4, ga); G.rect(p.col.d, x + PW - 4, y + PH - 4, 3, 4, ga)
  end
  G.rect("#3a3a4a", x + (f > 0 and PW - 5 or 1), y + PH - 1, 5, 3, ga)
  if not p.onGround and p.doubleJump and p.airJumps == 0 and gFrame % 4 < 2 and not isPara then G.rect(P.flame, f > 0 and x - 1 or x + PW - 2, y + 8, 3, 5, ga) end
  -- aim ring
  local OR = 20
  G.ring(p.col.m, pcx, pcy + 2, OR, .8, ghost and .06 or .2)
  G.line(p.col.m, pcx, pcy + 2, pcx + math.cos(ang) * OR, pcy + 2 + math.sin(ang) * OR, 1.2, ghost and .08 or .55)
  G.rect(p.dmgMult > 1 and P.dmgx or p.col.m, pcx + math.cos(ang) * OR - 2, pcy + 2 + math.sin(ang) * OR - 2, 4, 4, ghost and .06 or .88)
  if p.dmgMult > 1 then G.ring(P.dmgx, pcx, pcy + 2, OR + 4, 2, (.4 + math.sin(gFrame * .2) * .3) * .28) end
  if numPlayers == 2 then
    for _, ally in ipairs(players) do
      if ally ~= p and ally.hp <= 0 and abs((p.x + PW / 2) - (ally.x + PW / 2)) < REVIVE_RANGE + PW then
        G.ring(P.hpG, pcx, pcy, OR + 6 + (ally.reviveTimer / REVIVE_TIME) * 4, 1.5, .25 + math.sin(gFrame * .2) * .15)
      end
    end
  end
  if not p.onGround and p.airJumps > 0 and not isPara then
    for j = 0, p.airJumps - 1 do G.rect(p.col.m, x + PW / 2 - p.airJumps * 3 + j * 6, y - 6, 4, 4, .75) end
  end
end

function dBoss()
  if not boss then return end
  local x, y = floor(boss.x + .5), floor(boss.y + .5)
  local f, rage = boss.facing, boss.hp < BMAXHP * .4
  local isBursting = boss.burstState == "WINDUP"
  local burstP = isBursting and (.5 + math.sin(gFrame * .4) * .5) or 0
  local blink = (rage and gFrame % 8 < 4) or (isBursting and gFrame % 4 < 2)
  local pulse = math.sin(gFrame * .1) * .5 + .5
  if boss.onGround then G.rect({ 0, 0, 0 }, x + 4, y + BH, BW - 8, 4, .35) end
  if boss.laserT > 0 then
    local bcx, bcy, k = x + BW / 2, y + BH / 2, 1 - boss.laserT / 36
    G.line(U.hsl(lvl.bossHue + 180, 95, 65), bcx, bcy, bcx + math.cos(boss.laserAng) * 900, bcy + math.sin(boss.laserAng) * 900,
      1 + k * 3, (gFrame % 4 < 2 and .35 or .7) * (.4 + k * .6))
  end
  local bob = boss.rising and 0 or floor(gFrame / 30) % 2
  local eyeBlink = not isBursting and gFrame % 150 < 8
  local mouthOpen = isBursting or boss.mouthT > 0
  local g = composeBoss(boss.parts, bob, eyeBlink, mouthOpen, f)
  local fph = floor(gFrame / 4) % 2
  for r = 0, BFH do for c = 0, BFW - 1 do if g[r][c] == "f" and (fph + c + r) % 2 == 1 then g[r][c] = "." end end end
  local mode = boss.flash > 0 and "flash" or (isBursting and gFrame % 4 < 2) and "burst" or blink and "bright" or "normal"
  local base = ""
  for _, s in ipairs(BOSS_ORDER) do base = base .. boss.parts[s].id .. "," end
  base = base .. "|" .. bob .. (eyeBlink and 1 or 0) .. (mouthOpen and 1 or 0) .. f .. fph .. "|" .. lvl.bossHue
  local spr = bossSprite(g, bossPalette(mode), base .. "|" .. mode)
  local jit = isBursting and floor((love.math.random() - .5) * 2 + .5) or 0
  local ox, oy = x - BCELL + jit, y + BH - BFH * BCELL
  G.set({ 1, 1, 1 }); lg.draw(spr, ox, oy)
  if rage or isBursting then
    local gc = isBursting and { 1, 0, 0 } or lvl.bossAcc
    local gp = {}
    for k in ("odmlsaepwf"):gmatch(".") do gp[k] = gc end
    local key = base .. "|glow" .. (isBursting and "r" or "a")
    G.set({ 1, 1, 1 }, (isBursting and burstP * .35 or .10) + pulse * .08)
    lg.draw(bossSprite(g, gp, key), ox, oy)
  end
  if boss.rising then
    G.rect({ 0, 0, 0 }, x, y + BH, BW, SH - y - BH, .15)
    for r = 0, 3 do local ry = y + BH + r * 14 + (gFrame % 14); if ry < SH then G.rect(lvl.bossAcc, x + 4, ry, BW - 8, 5) end end
  end
  if not boss.rising and not isBursting then
    local prog = (boss.hitCounter % 5) / 5
    if prog > 0 then G.arc({ 1, .78, 0 }, x + BW / 2, y - 26, 8, -PI / 2, -PI / 2 + prog * PI * 2, 2, .45) end
    G.text((boss.hitCounter % 5) .. "/5", x + BW / 2, y - 22, "center", F("mono", 9), { 1, .84, 0 }, .75)
  end
  if not boss.rising and boss.burstState == "NONE" and boss.burstTimer > BURST_INTERVAL * .7 then
    local bp = boss.burstTimer / BURST_INTERVAL
    G.arc({ 1, 0, 0 }, x + BW / 2, y - 26, 12, -PI / 2, -PI / 2 + bp * PI * 2, 2, .3 + (bp - .7) / .3 * .5)
  end
end

local function dPBullet(b)
  local o = players[b.pid]
  G.rect((o and (o.dmgMult > 1 or o.weaponLvl > 2)) and P.dmgx or P.bullet, b.x - 2, b.y - 2, 5, 5)
  G.rect(P.bulletT, b.x - b.vx * .4 - 1, b.y - b.vy * .4 - 1, 3, 3, .3)
end
local function dBBullet(b)
  if b.burst then
    local pulse = .7 + math.sin(gFrame * .2 + b.x * .1) * .3
    G.circle(P.bburst, b.x, b.y, b.r, pulse); G.circle(P.bburstC, b.x - 1, b.y - 1, b.r - 3, pulse)
    G.circle(P.bburst, b.x, b.y, b.r + 6, pulse * .25)
  else
    G.circle(P.bb, b.x, b.y, b.r); G.circle(P.bbC, b.x - 1, b.y - 1, b.r - 2)
    G.circle(P.bb, b.x, b.y, b.r + 4, .18)
  end
end
local function dDrop(d)
  local x, y = floor(d.x + .5), floor(d.y + math.sin(d.bob) * 3 + .5)
  if d.type == "COIN" then
    local spin = abs(math.cos(gFrame * .12)) * 10 + 2
    G.rect(P.coinD, x, y, 12, 12); G.rect(P.coin, x + 1, y + 1, 10, 10); G.rect(P.coinD, x + 5 - spin / 2, y + 2, spin, 8)
    G.text("$", x + 6, y + 9, "center", F("mono", 9), P.white)
  elseif d.type == "DMGX2" then
    local a = .7 + math.sin(gFrame * .18) * .3
    G.rect(P.dmgxD, x - 1, y - 1, 14, 14, a); G.rect(P.dmgx, x + 1, y + 1, 10, 10, a)
    G.text("x2", x + 6, y + 9, "center", F("mono", 9), P.dmgxS, a)
  else
    G.rect(P.hpDD, x, y, 12, 12); G.rect(P.hpD, x + 1, y + 1, 10, 10)
    G.rect("#ffffff", x + 4, y + 3, 4, 6); G.rect("#ffffff", x + 2, y + 5, 8, 2)
  end
end

function dHUD()
  local fs = F("mono", 10)
  for i, p in ipairs(players) do
    local hx, hy, hw, hh = i == 1 and 10 or SW - 134, 10, 120, 10
    G.rect({ 0, 0, 0 }, hx - 2, hy - 2, hw + 4, hh + 4, .7)
    G.rect("#100808", hx, hy, hw, hh)
    local hf = max(0, hw * p.hp / p.maxHP)
    G.rect(i == 1 and "#40e038" or "#e06028", hx, hy, hf, hh)
    G.text("P" .. i .. "  " .. math.ceil(p.hp) .. "/" .. p.maxHP, hx + 3, hy + 8, "left", fs, P.white)
    G.text("$ " .. p.coins, hx, hy + 22, "left", fs, P.gold)
    local row = 34
    if p.weaponLvl > 0 then G.text("W" .. p.weaponLvl .. " +" .. (p.weaponLvl * 10) .. "%", hx, hy + row, "left", fs, P.goldD); row = row + 12 end
    if p.fireRate then G.text(">> CADENCIA", hx, hy + row, "left", fs, P.fire); row = row + 12 end
    if p.doubleJump then G.text("SALTO x2", hx, hy + row, "left", fs, P.djump); row = row + 12 end
    if p.parachute then G.text("PARAQUEDAS", hx, hy + row, "left", fs, P.para); row = row + 12 end
    if p.dmgMult > 1 then G.text("DMG x2", hx, hy + row, "left", F("mono", 11), P.dmgx, .7 + math.sin(gFrame * .2) * .3) end
  end
  if bossSpawned and boss and boss.hp > 0 then
    local bw, bh = 320, 14
    local bx, by = (SW - bw) / 2, 8
    G.rect({ 0, 0, 0 }, bx - 2, by - 2, bw + 4, bh + 4, .7)
    G.rect(lvl.bossDark, bx, by, bw, bh)
    local bf = max(0, (bw - 2) * boss.hp / BMAXHP)
    G.rect(lvl.bossAcc, bx + 1, by + 1, bf, bh - 2)
    for t = 1, 19 do G.rect({ 0, 0, 0 }, bx + bw * t / 20 - 1, by, 2, bh, .35) end
    if not boss.dmgDropped then G.rect(P.dmgx, bx + bw / 2 - 1, by - 3, 2, bh + 6) end
    local fb = F("mono", 11)
    if boss.burstState == "WINDUP" then
      local a = .5 + math.sin(gFrame * .3) * .5
      G.rect({ 1, 0, 0 }, bx, by, bw, bh, .4 * a)
      G.text("!  BURST  !", SW / 2, by + 11, "center", fb, "#ff4040", a)
    else
      G.text(boss.name .. "  " .. math.ceil(boss.hp) .. " / " .. BMAXHP .. "  [NIV." .. levelNum .. "]", SW / 2, by + 11, "center", fb, P.white)
    end
  end
  if gFrame < 260 then
    local a = max(0, min(1, (260 - gFrame) / 110))
    G.rect({ 0, 0, 0 }, 0, SH - 46, SW, 46, .6 * a)
    local ft = F("mono", 11)
    G.text("D-pad mover / mirar  -  A saltar  -  B disparar  -  Baixo+A desce plataforma", SW / 2, SH - 26, "center", ft, P.white, a)
    if numPlayers > 1 then G.text("P2: segundo comando USB (ou teclado A D W S, 1 salta, Q dispara)", SW / 2, SH - 11, "center", ft, P.white, a) end
  end
end

function drawPlay()
  dMap(); dDustPiles()
  for _, d in ipairs(drops) do dDrop(d) end
  for _, b in ipairs(bBullets) do dBBullet(b) end
  for _, b in ipairs(pBullets) do dPBullet(b) end
  if bossSpawned and boss then dBoss() end
  for _, p in ipairs(players) do dPlayer(p) end
end
