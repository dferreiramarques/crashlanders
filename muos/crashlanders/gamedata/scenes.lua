-- Menu, intro cinematics, crash, extraction, warp + shop, game over, saves
local U = require "util"
local G = require "gfx"
local A = require "audio"
local I = require "input"
local Pm = require "poly"
local lg = love.graphics
local rnd, clamp, lerp = U.rnd, U.clamp, U.lerp
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local PI = math.pi

local fonts = {}
local function F(kind, size) local k = kind .. size; if not fonts[k] then fonts[k] = G.font(kind, size) end; return fonts[k] end
local function neonLine(c, x0, y0, x1, y1, lw, a) G.line(c, x0, y0, x1, y1, lw, a) end

gState, gFrame, shake, cinT, menuSel = "MENU", 0, 0, 0, 0
cs, cShots, planet = {}, {}, { x = 400, y = 650, r = 340 }
debris, crashX, crashY, crashDone = {}, 0, 0, false
extractShip, extractTimer = nil, 0
warpStars, warpTimer, storeTimer = {}, 0, 0
hasSaveGame = false
stars = {}

-- ── Saves (love.filesystem → conf/love/crashlanders under PortMaster) ──
function saveGame()
  if NETL.mode then return end               -- LAN runs never touch the local save
  love.filesystem.write("save.lua", U.ser({ persist = persist, levelNum = levelNum, numPlayers = numPlayers }))
end
local function loadGame()
  local s = love.filesystem.getInfo("save.lua") and love.filesystem.read("save.lua")
  local d = U.deser(s)
  if not d then return false end
  persist = d.persist or persist; levelNum = d.levelNum or 1; numPlayers = d.numPlayers or 1
  return true
end
local function clearSave() love.filesystem.remove("save.lua") end
local scores = {}
local function loadScores() scores = U.deser(love.filesystem.getInfo("scores.lua") and love.filesystem.read("scores.lua")) or {} end
local function saveScore(name, mode, level, coins)
  scores[#scores + 1] = { name = name, mode = mode, level = level, coins = coins }
  table.sort(scores, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.coins > b.coins end)
  while #scores > 10 do table.remove(scores) end
  love.filesystem.write("scores.lua", U.ser(scores))
end

function genStars()
  stars = {}
  for i = 1, 200 do stars[i] = { x = love.math.random() * SW, y = love.math.random() * SH, s = love.math.random() < .04 and 2 or 1, b = love.math.random() } end
end
local function newWarpStars()
  warpStars = {}
  for i = 1, 120 do warpStars[i] = { x = love.math.random() * SW, y = love.math.random() * SH, len = rnd(4, 30), spd = rnd(8, 24) } end
end

-- ── Level setup ─────────────────────────────────────────────
function initLevel(firstTime)
  initBaseMap()
  if not firstTime then randomLvlPalette() end
  nextBossParts = rollBossParts()
  if firstTime then genStars() end
  pBullets, bBullets, drops, particles = {}, {}, {}, {}
  debris, crashDone, crashX, crashY = {}, false, 0, 0
  boss, bossSpawned, bossCountdown, anyMoved, players = nil, false, 300, false, {}
  extractShip, extractTimer = nil, 0
  warpTimer = 0; newWarpStars()
  if firstTime then
    gState, gFrame, shake, cinT, menuSel = "MENU", 0, 0, 0, 0
    cs = {}; cShots = {}
  else
    gFrame, shake = 0, 0
    cs = { x = SW * .5 - 28, y = -90, vx = .8, vy = 1.8, angle = -.15, av = .018, scale = 1, exploding = false, explodeT = 0, crashed = false }
    gState, cinT = "CIN_CRASH", 0
  end
end

function initGame()
  hasSaveGame = loadGame() and levelNum > 1
  local keep = { persist = persist, levelNum = levelNum, numPlayers = numPlayers }
  resetPersist(); clearSave()
  initLevel(true)
  if hasSaveGame then persist, levelNum, numPlayers = keep.persist, keep.levelNum, keep.numPlayers; saveGame() end
  loadScores()
end

function startCin()
  cinT = 0; cShots = {}
  cs = { x = -80, y = SH * .44, vx = 3.5, vy = 0, angle = 0, av = 0, scale = .7, exploding = false, explodeT = 0, crashed = false, tumbleAv = 0, tumbleAngle = 0 }
  gState = "CIN_SPACE"
end

-- ═══ MENU ════════════════════════════════════════════════════
local function menuOptions()
  if hasSaveGame then return { "CONTINUAR  ·  NÍV." .. levelNum .. "  ·  " .. numPlayers .. "P", "NOVO JOGO  ·  1 JOGADOR", "NOVO JOGO  ·  2 JOGADORES", "LAN  ·  CO-OP" } end
  return { "1 JOGADOR", "2 JOGADORES", "LAN  ·  CO-OP" }
end

function uMenu()
  A.startMusic()
  local n = #menuOptions()
  if I.anyPress("up") then menuSel = max(0, menuSel - 1); A.play("menuMove") end
  if I.anyPress("down") then menuSel = min(n - 1, menuSel + 1); A.play("menuMove") end
  if I.anyPress("start") or I.anyPress("jump") then
    A.play("menuConfirm")
    if menuSel == n - 1 then NETL.lobby = "choose"; NETL.sel = 0; gState = "LOBBY"; return end
    if hasSaveGame and menuSel == 0 then
      initLevel(false)
    else
      resetPersist()
      numPlayers = hasSaveGame and menuSel or menuSel + 1
      saveGame(); startCin()
    end
  end
end

local MENU_HZ = 176
local function hudBrackets(m, top, bot, col)
  col = col or { .16, .95, 1 }
  for _, c in ipairs({ { m, top, 1, 1 }, { SW - m, top, -1, 1 }, { m, bot, 1, -1 }, { SW - m, bot, -1, -1 } }) do
    neonLine(col, c[1], c[2], c[1] + c[3] * 22, c[2], 2, .7); neonLine(col, c[1], c[2], c[1], c[2] + c[4] * 22, 2, .7)
  end
end

function dMenu()
  local t, HZ, sx = gFrame, MENU_HZ, SW / 2
  -- deep space
  G.vgrad(0, 0, SW, SH, { { 0, "#04010f" }, { .55, "#170533" }, { 1, "#3a0b4e" } })
  for _, n in ipairs({ { 180, 120, 260, 70, "#ff2f8e", .06 }, { 620, 90, 220, 60, "#29f3ff", .05 }, { 420, 200, 320, 80, "#8a2be2", .07 } }) do
    G.set(n[5], n[6]); lg.ellipse("fill", n[1] + math.sin(t * .002 + n[1]) * 10, n[2], n[3], n[4], 48)
  end
  for _, s in ipairs(stars) do G.rect({ 1, 1, 1 }, s.x, s.y, s.s, s.s, .25 + s.b * .65 * (.7 + .3 * math.sin(t * .05 + s.x))) end
  -- neon star behind the planet
  local sr, sy = 104, HZ + 60
  G.circle("#ff2f8e", sx, sy, sr + 24, .16); G.circle("#ff2f8e", sx, sy, sr + 50, .09)
  G.gradBegin({ { 0, "#fff46a" }, { .42, "#ff9b3a" }, { .75, "#ff3d7f" }, { 1, "#d4148f" } }, sy - sr, sy + sr * .3)
  lg.circle("fill", sx, sy, sr, 64)
  G.gradEnd()
  local ph = (t * .25) % 14
  for i = 0, 8 do G.rect("#170533", sx - sr - 2, sy - sr * .55 + i * 14 + ph, sr * 2 + 4, 1 + i * .9) end
  -- huge backlit planet
  local PR = 620
  local PX, PY = sx, HZ + 70 + PR
  for _, r in ipairs({ { 22, .07 }, { 11, .14 }, { 4, .4 } }) do G.ring("#ff2f8e", PX, PY, PR + 4, r[1], r[2]) end
  Pm.draw(Pm.PLANET, PX, PY, PR, .55, t * .0012, .08, 0, 0,
    { dist = 12, tones = Pm.planetTones(lvl.groundHue, lvl.bossHue), noEdge = true, bands = 8, lspan = 30, light = { x = 0, y = -.62, z = .78 } })
  G.arc("#29f3ff", PX, PY, PR + 1, PI * 1.25, PI * 1.75, 1.5, .55)
  -- low-poly moon
  Pm.draw(Pm.MOON, 112, 70, 24, t * .004, t * .007, .3, 22, 55, { dist = 8 })

  local glitch = t % 260 < 7
  local gx = glitch and (love.math.random() - .5) * 8 or 0
  -- title: extrusion, neon rim, chromatic split, chrome gradient
  local ft = F("orb", 54)
  for _, row in ipairs({ { "CRASH", 82 }, { "LANDERS", 138 } }) do
    local txt, by = row[1], row[2]
    local x = SW / 2 + gx
    for i = 7, 1, -1 do G.text(txt, x + i * .6, by + i, "center", ft, i > 4 and "#12002a" or "#3c0d6b") end
    G.textStroke(txt, x, by, "center", ft, "#ff2f8e", 7, .35)
    G.textStroke(txt, x, by, "center", ft, "#ff2f8e", 3)
    G.text(txt, x - 1.5, by, "center", ft, "#ff2050", .6); G.text(txt, x + 1.5, by, "center", ft, "#20e8ff", .6)
    G.gradBegin({ { 0, "#ffffff" }, { .38, "#9df4ff" }, { .5, "#2a1a6a" }, { .53, "#ff6ad5" }, { .8, "#ffd0f2" }, { 1, "#ffffff" } }, by - 44, by + 2)
    G.text(txt, x, by, "center", ft, { 1, 1, 1 })
    G.gradEnd()
  end
  lg.push(); lg.translate(SW / 2 + 118 + gx, 160); lg.rotate(-.09)
  local fsx = F("script", 34)
  G.textStroke("a survival story", 0, 0, "center", fsx, "#2a0040", 5)
  G.textStroke("a survival story", 0, 0, "center", fsx, "#ff2f8e", 2)
  G.text("a survival story", 0, 0, "center", fsx, "#ffe95a")
  lg.pop()

  -- our lander with a target lock
  local shx, shy = 680 + math.sin(t * .012) * 26, 92 + math.sin(t * .021) * 10
  local SP = Pm.draw(Pm.SHIP, shx, shy, 1.5, -.9 + math.sin(t * .02) * .2, PI * .82 + math.sin(t * .008) * .45, math.sin(t * .017) * .12, 200, 35, { dist = 60 })
  if t % 4 < 2 then G.rect("#ff9b3a", SP[5][1] - 2, SP[5][2] - 2, 4, 4); G.rect("#fff46a", SP[5][1] - 1, SP[5][2] - 1, 2, 2) end
  local lk = (t % 240) / 240
  local rs, locked = 46 - min(1, lk * 3) * 16, lk > .33
  local rc = (locked and t % 20 < 12) and "#ffe95a" or "#29f3ff"
  for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    local x0, y0 = shx + d[1] * rs, shy + d[2] * rs * .75
    neonLine(rc, x0, y0, x0 - d[1] * 8, y0, 1.5); neonLine(rc, x0, y0, x0, y0 - d[2] * 8, 1.5)
  end
  local fv = F("vt", 14)
  G.text(locked and "LOCK" or "TRACK", shx + rs + 4, shy - rs * .75 + 8, "left", fv, rc)
  G.text(floor(1200 + math.sin(t * .01) * 300) .. "m", shx + rs + 4, shy - rs * .75 + 20, "left", fv, rc)

  -- buttons
  local opts = menuOptions()
  menuSel = min(menuSel, #opts - 1)
  local bw, bh, sk = 300, 28, 10
  local top = hasSaveGame and 192 or 204
  local fb = F("vt", 22)
  for i = 0, #opts - 1 do
    local sel, bx, by = menuSel == i, SW / 2 - bw / 2, top + i * 36
    local slab = { bx + sk, by, bx + bw + sk, by, bx + bw - sk, by + bh, bx - sk, by + bh }
    if sel then
      G.rect("#29f3ff", bx - sk - 6, by - 4, bw + sk * 2 + 12, bh + 8, .18)
      G.gradBegin({ { 0, "#ff5aa8" }, { 1, "#c0127a" } }, by, by + bh)
      G.alpha = t % 90 < 3 and .5 or 1
      lg.setColor(1, 1, 1, G.alpha); lg.polygon("fill", slab)
      G.gradEnd()
      G.spoly("#29f3ff", slab, 2)
      G.alpha = 1
      local ax = math.sin(t * .2) * 3
      local fa = F("vt", 20)
      G.text(">", bx - sk - 14 + ax, by + bh / 2 + 6, "center", fa, "#ffe95a")
      G.text("<", bx + bw + sk + 14 - ax, by + bh / 2 + 6, "center", fa, "#ffe95a")
      G.text(opts[i + 1], SW / 2 + 1, by + bh / 2 + 8, "center", fb, "#3a0030")
    else
      G.poly("#08001a", slab, .78); G.spoly("#29f3ff", slab, 1, .55)
    end
    G.text(opts[i + 1], SW / 2, by + bh / 2 + 7, "center", fb, sel and "#ffffff" or ((hasSaveGame and i == 0) and "#ffe95a" or "#7fe9ff"))
  end

  -- controls panel (gamepad first: this build targets handhelds)
  local rows = {
    { "#7fe9ff", "D-pad  mover e mirar   ·   A  saltar   ·   B  disparar" },
    { "#c9a0ff", "Segurar B fixa a direção   ·   Baixo + A  desce plataforma" },
    { "#7dffb0", "Loja:  X arma   Y cadência   L1 salto x2   R1 paraquedas" },
    { "#ffb35a", "P2: segundo comando USB   ·   Start confirmar" },
  }
  local lh, tw = 17, 480
  local th = #rows * lh + 14
  local free = top + #opts * 36
  local ty = free + max(6, (SH - free - th) / 2)
  G.rect("#050012", SW / 2 - tw / 2, ty, tw, th, .84)
  G.srect("#ff2f8e", SW / 2 - tw / 2 + .5, ty + .5, tw - 1, th - 1, 1, .6)
  G.rect("#ff2f8e", SW / 2 - tw / 2, ty, tw, 2)
  local fr = F("vt", 16)
  for i, r in ipairs(rows) do G.text(r[2], SW / 2, ty + 8 + lh * (i - .25), "center", fr, r[1]) end

  -- cockpit corners + sector + best local score
  hudBrackets(12, 12, SH - 12)
  G.text("SECT 07 · KETH-9", 22, 28, "left", fv, "#29f3ff")
  local best = scores[1]
  G.text(best and ("TOP " .. best.name .. " · NV" .. best.level) or "TOP ---", SW - 22, 28, "right", fv, "#ffe95a")

  if glitch then
    local gy = rnd(0, SH - 10)
    G.rect({ 1, 1, 1 }, 0, gy, SW, rnd(2, 8), .12); G.rect("#29f3ff", 0, gy + 10, SW, 2, .08)
  end
end

-- ═══ CINEMATICS ══════════════════════════════════════════════
local function dSpaceBG()
  G.rect("#030010", 0, 0, SW, SH)
  for _, s in ipairs(stars) do if s.b >= .4 then G.rect({ 1, 1, 1 }, s.x, s.y, s.s, s.s, s.b * .6) end end
end
local function hudTarget(x, y, r, label, col)
  for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    local x0, y0 = x + d[1] * r, y + d[2] * r * .7
    neonLine(col, x0, y0, x0 - d[1] * 9, y0, 1.5); neonLine(col, x0, y0, x0, y0 - d[2] * 9, 1.5)
  end
  G.text(label, x - r, y - r * .7 - 5, "left", F("vt", 14), col)
end
local function hudGauge(x, y, label, v, col, warn)
  G.text(label, x, y, "left", F("vt", 14), col)
  local blink = warn and gFrame % 30 < 15
  for k = 0, 13 do G.rect(col, x + k * 8, y + 4, 6, 7, k / 14 < v and (blink and .4 or 1) or .16) end
end
local function shipPlume(x, y, ang, len, heat)
  local bx, by = -math.cos(ang), -math.sin(ang)
  local px, py = -by, bx
  for _, c in ipairs({ { "#ff2f8e", 1, 1 }, { "#ff9b3a", .75, .7 }, { "#fff46a", .5, .4 } }) do
    local L, w = len * c[2] * (.85 + love.math.random() * .3), 12 * c[3]
    G.poly(c[1], { x - bx * 10 + px * w, y - by * 10 + py * w, x + bx * L, y + by * L, x - bx * 10 - px * w, y - by * 10 - py * w }, heat * .85)
  end
end
function dCinBars(top, bot)
  G.rect({ 0, 0, 0 }, 0, 0, SW, 30); G.rect({ 0, 0, 0 }, 0, SH - 30, SW, 30)
  G.rect("#ff2f8e", 0, 30, SW, 1); G.rect("#ff2f8e", 0, SH - 31, SW, 1)
  local f = F("vt", 16)
  local n = floor(cinT * .9)
  local cur = gFrame % 10 < 5 and "_" or ""
  if top ~= "" then
    local tt = U.usub(top, n)
    G.text(tt .. (U.ulen(tt) < U.ulen(top) and cur or ""), 16, 20, "left", f, "#29f3ff")
  end
  if bot ~= "" then
    local m = max(0, n - 24)
    local bt = U.usub(bot, m)
    if m > 0 then G.text(bt .. (U.ulen(bt) < U.ulen(bot) and cur or ""), 16, SH - 10, "left", f, gFrame % 40 < 28 and "#ffe95a" or "#ff2f8e") end
  end
  G.text(string.format("T+00:%02d", floor(cinT / 60)), SW - 16, 20, "right", f, "#29f3ff", .6)
end

function uCinSpace()
  cinT = cinT + 1
  if not cs.exploding then
    if cinT <= 80 then cs.x = lerp(cs.x, SW * .24, .045) end
    if cinT == 90 then cShots[#cShots + 1] = { id = 1, x = SW * .78, y = SH * .44, vx = -32, alive = true }; A.play("laser") end
    if cinT > 90 and cinT < 140 then cs.y = lerp(cs.y, SH * .28, .14); cs.angle = lerp(cs.angle, -.28, .1) end
    if cinT > 140 and cinT < 180 then cs.y = lerp(cs.y, SH * .44, .1); cs.angle = lerp(cs.angle, 0, .1) end
    if cinT == 190 then cShots[#cShots + 1] = { id = 2, x = SW * .78, y = SH * .3, vx = -38, alive = true }; A.play("laser") end
    if cinT > 190 and cinT < 240 then cs.y = lerp(cs.y, SH * .58, .16); cs.angle = lerp(cs.angle, .22, .1) end
    if cinT > 240 and cinT < 270 then cs.y = lerp(cs.y, SH * .44, .1); cs.angle = lerp(cs.angle, 0, .1) end
    if cinT == 280 then cShots[#cShots + 1] = { id = 3, x = SW * .78, y = SH * .46, vx = -44, alive = true }; A.play("laser") end
    for _, s in ipairs(cShots) do
      if s.alive then
        s.x = s.x + s.vx
        if s.id == 3 and s.x < cs.x + 52 and s.x > cs.x - 10 and abs(s.y - (cs.y + 18)) < 20 then
          s.alive = false; cs.exploding = true; cs.explodeT = 0
          cs.vx, cs.vy = -.5, .8; cs.tumbleAv = .08 + love.math.random() * .04; cs.tumbleAngle = cs.angle
          fx(cs.x + 30, cs.y + 18, 35, P.flame, 7, 4); fx(cs.x + 30, cs.y + 18, 18, P.ship, 4, 3); fx(cs.x + 30, cs.y + 18, 12, "#ffffff", 6, 2)
          A.play("explode"); shake = 30
        end
        if s.x < -60 then s.alive = false end
      end
    end
  end
  if cs.exploding then
    cs.explodeT = cs.explodeT + 1
    cs.x = cs.x + cs.vx; cs.y = cs.y + cs.vy; cs.vy = cs.vy + .012
    cs.tumbleAngle = cs.tumbleAngle + cs.tumbleAv; cs.tumbleAv = cs.tumbleAv * .995
    if cs.explodeT % 3 == 0 then fx(cs.x + 30 + rnd(-8, 8), cs.y + 18 + rnd(-6, 6), 2, P.flame, 2, 2); fx(cs.x + 30, cs.y + 18, 1, P.gray, 1.5, 2) end
    if cs.explodeT > 120 or cs.y > SH + 40 then
      gState = "CIN_ORBIT"; cinT = 0
      planet = { x = SW * .5, y = SH + 320, r = 220 }
      cs.x, cs.y, cs.scale, cs.angle = SW * .75, SH * .12, .5, .1
      cs.exploding = false; cs.tumbleAngle = 0
    end
  end
  if I.anyPress("start") then gState = "CIN_CRASH"; cinT = 0; initCrashEntry() end   -- skip intro
end

function dCinSpace()
  dSpaceBG()
  Pm.draw(Pm.PLANET, SW * .15, SH * .74, 60, .2, cinT * .004, .35, 0, 0, { dist = 8, tones = Pm.planetTones(lvl.groundHue, lvl.bossHue), noEdge = true, bands = 6 })
  local crx, cry = max(SW - 200, SW - 60 - cinT * 1.1) + 100, SH * .4
  local cang = -.35 + math.sin(cinT * .01) * .05
  local copt = { dist = 220, edge = "#06000c" }
  local CP = Pm.draw(Pm.CRUISER, crx, cry, 1.6, .3, cang, 0, 345, 22, copt)
  Pm.draw(Pm.TOWER, crx, cry, 1.6, .3, cang, 0, 345, 22, copt)
  local ex = (CP[6][1] + CP[7][1] + CP[8][1] + CP[9][1]) / 4
  local ey = (CP[6][2] + CP[7][2] + CP[8][2] + CP[9][2]) / 4
  G.rect(gFrame % 8 < 4 and "#ff2f8e" or "#a0105a", ex - 4, ey - 4, 8, 8)
  hudTarget(crx - 10, cry, 92, "HOSTIL · CLASSE VII", gFrame % 30 < 20 and "#ffe95a" or "#ff2f8e")
  for _, s in ipairs(cShots) do
    if s.alive then
      G.rect("#ff2f8e", s.x - 70, s.y - 4, 140, 8, .25); G.rect("#ff6ad5", s.x - 60, s.y - 2, 120, 4); G.rect("#ffffff", s.x - 46, s.y - 1, 92, 2)
    end
  end
  local shx, shy = cs.x + 28 * cs.scale, cs.y + 18 * cs.scale
  if not cs.exploding then
    local SP = Pm.draw(Pm.SHIP, shx, shy, 1.7, -.8 + math.sin(cinT * .05) * .1, -.35, cs.angle, 200, 35, { dist = 60 })
    if gFrame % 4 < 2 then G.rect("#ff9b3a", SP[5][1] - 3, SP[5][2] - 3, 6, 6); G.rect("#fff46a", SP[5][1] - 1, SP[5][2] - 1, 3, 3) end
  else
    local ta = cs.tumbleAngle
    Pm.draw(Pm.SHIP, shx, shy, 1.7, ta * 1.3, -.35 + ta * .4, ta, 20, 30, { dist = 60 })
    if cs.explodeT < 12 then G.rect({ 1, 1, 1 }, 0, 0, SW, SH, max(0, (12 - cs.explodeT) / 12) * .9) end
  end
  hudBrackets(14, 40, SH - 40)
  local shield = cs.exploding and 0 or (cinT > 200 and .5 or cinT > 100 and .8 or 1)
  hudGauge(24, SH - 64, cs.exploding and "CASCO CRÍTICO" or "ESCUDO", cs.exploding and .15 or shield, cs.exploding and "#ff2f8e" or "#29f3ff", cs.exploding)
  if cinT > 80 and not cs.exploding and gFrame % 40 < 26 then G.text("! BLOQUEIO DE MÍSSIL", SW - 24, SH - 52, "right", F("vt", 16), "#ff2f8e") end
  dCinBars("SECTOR 7 — INTERCEPÇÃO", "PROPULSÃO CRÍTICA — EVASÃO DE EMERGÊNCIA")
end

function uCinOrbit()
  cinT = cinT + 1
  if cinT > 30 then planet.y = lerp(planet.y, SH * .82, .055); planet.r = lerp(planet.r, 240, .04) end
  if cinT > 60 then
    local tt = (cinT - 60) / 180
    local oa = -PI * .6 + tt * PI * .5
    local orR = planet.r * .8
    cs.x = lerp(cs.x, planet.x + math.cos(oa) * orR - 20, .04); cs.y = lerp(cs.y, planet.y + math.sin(oa) * orR - 15, .04)
    cs.angle = oa + PI * .5
    if gFrame % 5 == 0 then fx(cs.x + 16, cs.y + 18, 1, P.gray, 1, 2) end
    if cinT % 30 == 0 then A.play("thruster") end
  end
  if cinT > 300 or I.anyPress("start") then gState = "CIN_CRASH"; cinT = 0; initCrashEntry() end
end

-- ── Foreshadowing: what waits on this planet ──
local SCAN_TRAITS = { legs = { bipede = "SALTOS PESADOS", aranha = "INVESTIDA RÁPIDA", jatos = "VOO E MERGULHO" },
                      arms = { garras = "GARRAS", canhoes = "CANHÕES", tentaculos = "TENTÁCULOS" },
                      eyes = { ciclope = "LASER", gemeos = "RAJADA DUPLA", composto = "MIRA PREDITIVA" } }
local SCAN_GLYPHS = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&?"
-- A pair of eyes in the boss's eye colour, glinting on the planet's night side
function dPlanetEyes()
  if cinT < 70 then return end
  local blink = cinT % 140 < 8
  local a = clamp((cinT - 70) / 60, 0, 1) * (.75 + math.sin(cinT * .09) * .25)
  local ex, ey, gap = planet.x - planet.r * .28, planet.y - planet.r * .6, planet.r * .035 + 3
  local col = U.hsl(lvl.bossHue + 180, 90, 72)
  for _, dx in ipairs({ -gap, gap }) do
    G.circle(col, ex + dx, ey, 6, a * .25)
    G.rect(col, ex + dx - 2, ey - (blink and 0 or 1.5), 4, blink and 1 or 3, a)
  end
end
-- HUD panel: long-range bio-scan of the level's boss
function dBossScan(x, y, w, h, t)
  local parts = nextBossParts
  if not parts then return end
  local bh = lvl.bossHue
  local acc = U.hsl(bh + 180, 95, 60)
  G.alpha = clamp(t / 12, 0, 1)
  G.rect("#050012", x, y, w, h, .86)
  G.srect(acc, x + .5, y + .5, w - 1, h - 1, 1, .7)
  G.rect(acc, x, y, w, 2)
  local f14 = F("vt", 14)
  G.text("SINAL BIOLÓGICO · SUPERFÍCIE", x + 8, y + 15, "left", f14, t % 40 < 28 and acc or "#ff2f8e")
  local blink = t % 120 < 6
  local spr = bossScanSprite(parts, blink)
  local sx, sy, sw, sh = x + 10, y + 22, spr:getWidth(), spr:getHeight()
  local rev = floor(clamp((t - 8) / 90, 0, 1) * sh)
  G.rect("#0b0418", sx - 2, sy - 2, sw + 4, sh + 4)
  if rev > 0 then
    G.set({ 1, 1, 1 })
    lg.draw(spr, lg.newQuad(0, 0, sw, rev, sw, sh), sx, sy)
  end
  for _ = 1, 14 do
    local ny = sy + rev + love.math.random() * (sh - rev)
    if ny < sy + sh then G.rect(love.math.random() < .5 and { 1, 1, 1, .18 } or U.hsl(bh + 180, 60, 40), sx + love.math.random() * sw, ny, rnd(2, 8), 1) end
  end
  if rev < sh then G.rect(acc, sx - 2, sy + rev, sw + 4, 1) end
  -- name decoding, letter by letter
  local name = bossName(parts)
  local n = floor(clamp((t - 30) / 80, 0, 1) * #name)
  local shown = name:sub(1, n)
  for i = n + 1, #name do
    local c = name:sub(i, i)
    if c == " " then shown = shown .. " " else local k = rnd(1, #SCAN_GLYPHS + 1); shown = shown .. SCAN_GLYPHS:sub(k, k) end
  end
  local tx = sx + sw + 12
  local sp = shown:find(" ")
  local f17 = F("vt", 17)
  local nc = n >= #name and "#ffffff" or "#bba8d8"
  G.text(sp and shown:sub(1, sp - 1) or shown, tx, y + 38, "left", f17, nc)
  if sp then G.text(shown:sub(sp + 1), tx, y + 54, "left", f17, nc) end
  local rows = { { "MOBILIDADE", SCAN_TRAITS.legs[parts.legs.id] }, { "ARMAS", SCAN_TRAITS.arms[parts.arms.id] }, { "SENSORES", SCAN_TRAITS.eyes[parts.eyes.id] } }
  for i, r in ipairs(rows) do
    if t >= 115 + (i - 1) * 18 then
      G.text(r[1], tx, y + 74 + (i - 1) * 14, "left", f14, "#6a6890")
      G.text(r[2], tx + 70, y + 74 + (i - 1) * 14, "left", f14, "#7fe9ff")
    end
  end
  if t > 175 and t % 30 < 20 then G.text("AMEAÇA: EXTREMA", tx, y + h - 8, "left", f14, "#ff4040") end
  G.alpha = 1
end

function dCinOrbit()
  dSpaceBG()
  if cinT < 30 then G.rect({ 0, 0, 0 }, 0, 0, SW, SH); dCinBars("", ""); return end
  for _, r in ipairs({ { 18, .08 }, { 9, .16 }, { 3, .45 } }) do G.ring(lvl.bossAcc, planet.x, planet.y, planet.r + 3, r[1], r[2]) end
  Pm.draw(Pm.PLANET, planet.x, planet.y, planet.r, .35, cinT * .003, .15, 0, 0, { dist = 9, tones = Pm.planetTones(lvl.groundHue, lvl.bossHue), noEdge = true, bands = 8, lspan = 42 })
  dPlanetEyes()
  local heat = clamp((cinT - 110) / 150, 0, 1)
  local shx, shy = cs.x + 20, cs.y + 15
  if heat > 0 then shipPlume(shx, shy, cs.angle, 30 + heat * 60, heat) end
  Pm.draw(Pm.SHIP, shx, shy, 1.2, -.8 + math.sin(cinT * .09) * .25, 0, cs.angle, heat > .5 and 20 or 200, heat > .5 and 40 or 12, { dist = 60 })
  hudBrackets(14, 40, SH - 40)
  local fv = F("vt", 16)
  G.text(string.format("ALT %03d KM", max(0, floor(140 - cinT * .45))), 24, 58, "left", fv, "#29f3ff")
  G.text(string.format("VEL %.1f KM/S", 7.4 + cinT * .01), 24, 74, "left", fv, "#29f3ff")
  hudGauge(24, SH - 64, "TEMP. CASCO", heat, heat > .7 and "#ff2f8e" or "#ffe95a", heat > .7)
  if cinT > 100 then dBossScan(SW - 292, 42, 276, 128, cinT - 100) end
  dCinBars("PLANETA KETH-" .. (levelNum + 8) .. "  ·  CLASSE HOSTIL", "PROPULSÃO DESTRUÍDA — ENTRADA NA ATMOSFERA")
end

function initCrashEntry()
  cs = { x = SW / 2 - 28, y = -70, vx = 0, vy = 2.2, angle = .04, av = .005, scale = 1, exploding = false, explodeT = 0, crashed = false }
  crashDone = false; debris = {}
end

function uCinCrash()
  cinT = cinT + 1
  if not crashDone then
    cs.vy = cs.vy + .09; cs.y = cs.y + cs.vy; cs.x = cs.x + cs.vx; cs.angle = cs.angle + cs.av
    if cinT % 2 == 0 then fx(cs.x + 28 + rnd(-6, 6), cs.y + 10, 1, P.gray, 1, 2); fx(cs.x + 28, cs.y + 30, 1, P.flame, 2, 2) end
    local sx, sy = cs.x + 28, cs.y + 40
    local floorY = MH * TH - TH * 2
    if sy >= floorY - 8 then
      crashDone = true; crashX = sx; crashY = floorY
      cs.crashed = true
      fx(sx, crashY, 70, P.flame, 10, 4); fx(sx, crashY, 40, P.ship, 6, 3); fx(sx, crashY, 30, P.yellow, 8, 3)
      A.play("explode"); shake = 50
      -- one hull fragment per planned platform, flung on an exact arc to its spot
      local sx0, sy0, g = crashX, crashY - 24, .38
      local plan = {}
      for i, p in ipairs(pendingPlatforms) do plan[i] = p end
      table.sort(plan, function(p, q) return abs(p.tx * TW - sx0) + abs(p.ty * TH - sy0) < abs(q.tx * TW - sx0) + abs(q.ty * TH - sy0) end)
      for i, p in ipairs(plan) do
        local w = p.tw * TW
        local tx, ty = p.tx * TW + w / 2, p.ty * TH + TH / 2
        local T = floor(clamp(30 + math.sqrt((tx - sx0) ^ 2 + (ty - sy0) ^ 2) / 8, 34, 72) + .5)
        local k = ({ -2, -1, 1, 2 })[rnd(1, 5)]
        debris[#debris + 1] = { plan = p, w = w, h = TH, T = T, t = -(i - 1) * 3, x = sx0, y = sy0,
          vx = (tx - sx0) / T, vy = (ty - sy0 - g * T * (T + 1) / 2) / T, angle = 0, av = k * PI / T, landed = false }
      end
      pendingPlatforms = {}
    end
  end
  for _, d in ipairs(debris) do
    if not d.landed then
      if d.t < 0 then d.t = d.t + 1
      else
        d.t = d.t + 1; d.vy = d.vy + .38; d.x = d.x + d.vx; d.y = d.y + d.vy; d.angle = d.angle + d.av
        if d.t % 3 == 0 then fx(d.x, d.y, 1, P.gray, 1, 2); if love.math.random() < .5 then fx(d.x, d.y, 1, P.flame, 1.5, 2) end end
        if d.t >= d.T then
          d.landed = true
          for x = d.plan.tx, d.plan.tx + d.plan.tw - 1 do setTile(x, d.plan.ty, 1, 1) end
          fx(d.x, d.y, 14, P.yellow, 4, 2); fx(d.x, d.y, 10, P.ship, 3, 2)
          shake = max(shake, 5); A.play("land")
        end
      end
    end
  end
  if crashDone and cinT > 100 and #players == 0 then
    initPlayers(clamp(crashX - 40, TW + 4, SW - TW - PW * 3 - 10), MH * TH - TH * 2 - PH - 4)
  end
  for x = 1, MW - 2 do map[MH - 1][x] = 1; map[MH - 2][x] = 1; tileHP[MH - 1][x] = TILE_MAX_HP; tileHP[MH - 2][x] = TILE_MAX_HP end
  local allLanded = true
  for _, d in ipairs(debris) do if not d.landed then allLanded = false end end
  if crashDone and cinT > 180 and allLanded then gState = "PLAY"; cinT = 0; gFrame = 0 end
end

function dCrash()
  if not cs.crashed then
    local shx, shy, a = cs.x + 28, cs.y + 22, PI / 2 + cs.angle
    shipPlume(shx, shy, a, 46, 1)
    Pm.draw(Pm.SHIP, shx, shy, 1.3, -.5 + math.sin(cinT * .12) * .35, 0, a, 20, 40, { dist = 60 })
  end
  for _, d in ipairs(debris) do
    if not d.landed and d.t > 0 then
      lg.push(); lg.translate(d.x, d.y); lg.rotate(d.angle)
      G.rect("#2a3240", -d.w / 2, -d.h / 2, d.w, d.h)
      G.rect("#3c4658", -d.w / 2, -d.h / 2 + 2, d.w, d.h - 6)
      G.rect("#8a98b0", -d.w / 2, -d.h / 2, d.w, 2)
      if gFrame % 4 < 2 then G.rect("#ff9b3a", -d.w / 2 - 2, -2, 3, 4) end
      lg.pop()
    end
  end
end

-- ═══ EXTRACTION ══════════════════════════════════════════════
function uExtract()
  extractTimer = extractTimer + 1
  local es = extractShip
  if not es then return end
  if not es.landed then
    es.vy = es.vy + .25; es.y = es.y + es.vy
    local flr = MH * TH - TH * 2 - 30
    if es.y >= flr then es.y = flr; es.vy = 0; es.landed = true; fx(es.x + 28, es.y + 22, 20, P.flame, 4, 3); shake = 12 end
    return
  end
  local targetX = es.x + 28
  local allBoarded = true
  for _, p in ipairs(players) do
    if not p.boarded then
      allBoarded = false
      local dir = targetX > p.x + PW / 2 and 1 or -1
      p.vx = dir * 2.5
      if p.onGround and abs(p.x + PW / 2 - targetX) > 30 and extractTimer % 50 == 0 then p.vy = PJMP * .8 end
      p:step(.45); checkDustLanding(p)
      p.x = clamp(p.x, TW + 1, SW - TW - PW - 1)
      local close = abs(p.x + PW / 2 - targetX) < 30
      if close or extractTimer > 300 then p.boarded = true; if close then fx(p.x + PW / 2, p.y, 10, p.col.m, 3, 2) end end
    end
  end
  if allBoarded and extractTimer > 60 then es.lifting = true end
  if es.lifting then
    es.vy = lerp(es.vy, -8, .06); es.y = es.y + es.vy
    if gFrame % 3 == 0 then fx(es.x + rnd(10, 46), es.y + 45, 2, P.flame, 3, 2) end
    if es.y < -100 then
      for _, p in ipairs(players) do p.coins = p.coins + 20 end
      levelNum = levelNum + 1
      saveToPersist()
      randomLvlPalette()
      warpTimer = 0; storeTimer = 0; newWarpStars()
      gState = "WARP"
    end
  end
end

function dExtract()
  local es = extractShip
  if not es then return end
  lg.push(); lg.translate(es.x + 28, es.y + 22)
  G.rect("#304860", -26, -13, 52, 26); G.rect("#4070a0", -22, -10, 44, 20)
  G.rect("#2060c0", -9, -16, 18, 10); G.rect("#40a0e0", -6, -14, 8, 6)
  G.rect("#304860", -36, -6, 14, 20); G.rect("#304860", 22, -6, 14, 20)
  G.rect("#4070a0", -32, -4, 10, 14); G.rect("#4070a0", 22, -4, 10, 14)
  G.rect("#00ffff", -24, 9, 4, 3); G.rect("#00ffff", 20, 9, 4, 3)
  if es.lifting and gFrame % 4 < 2 then G.rect(P.flame, -10, 13, 20, 10); G.rect(P.yellow, -6, 15, 12, 8); G.rect("#ffffff", -2, 17, 4, 6) end
  lg.pop()
  local f = F("vt", 16)
  if not es.lifting and es.landed then
    local a = .6 + math.sin(gFrame * .15) * .4
    G.text("A EMBARCAR...", es.x + 28, es.y - 12, "center", f, "#00ffff", a)
    G.rect({ 0, 0, 0 }, es.x - 10, es.y - 24, 76, 6, .6 * a)
    G.rect("#00ffcc", es.x - 10, es.y - 24, 76 * min(1, extractTimer / 120), 6, a)
  end
  if es.lifting then
    G.rect({ 0, .78, 1 }, es.x, es.y + 44, 56, SH - es.y - 44, .15)
    G.text("EXTRACÇÃO BEM-SUCEDIDA", SW / 2, SH / 2, "center", F("vt", 22), "#00ccff", .7 + math.sin(gFrame * .1) * .3)
  end
end

-- ═══ WARP + SHOP ═════════════════════════════════════════════
local function buy(p, slot)
  local ps = persist[p.id]
  if slot == "b1" and p.coins >= COST_WEAPON and p.weaponLvl < 9 then p.coins = p.coins - COST_WEAPON; p.weaponLvl = p.weaponLvl + 1; fx(SW / 2, SH / 2, 30, P.gold, 6, 3)
  elseif slot == "b2" and p.coins >= COST_FIRE and not p.fireRate then p.coins = p.coins - COST_FIRE; p.fireRate = true; fx(SW / 2, SH / 2, 30, P.fire, 6, 3)
  elseif slot == "b3" and p.coins >= COST_DJUMP and not p.doubleJump then p.coins = p.coins - COST_DJUMP; p.doubleJump = true; fx(SW / 2, SH / 2, 30, P.djump, 6, 3)
  elseif slot == "b4" and p.coins >= COST_PARA and not p.parachute then p.coins = p.coins - COST_PARA; p.parachute = true; fx(SW / 2, SH / 2, 30, P.para, 6, 3)
  else return end
  A.play("coin")
  ps.weaponLvl, ps.coins, ps.fireRate, ps.doubleJump, ps.parachute = p.weaponLvl, p.coins, p.fireRate, p.doubleJump, p.parachute
  saveGame()
end

function uWarp()
  warpTimer = warpTimer + 1
  if warpTimer > 60 then storeTimer = storeTimer + 1 end
  local speed = min(1, warpTimer / 40)
  for _, s in ipairs(warpStars) do s.x = s.x - s.spd * speed; if s.x < -s.len * speed then s.x = SW + 4 end end
  if storeTimer > 60 then
    for _, p in ipairs(players) do for _, b in ipairs({ "b1", "b2", "b3", "b4" }) do if PPRESS(p, b) then buy(p, b) end end end
    if I.anyPress("start") then saveGame(); initLevel(false) end
  end
end

function dWarp()
  G.rect("#000008", 0, 0, SW, SH)
  local speed = min(1, warpTimer / 40)
  for _, s in ipairs(warpStars) do
    local len = s.len * speed + 2
    G.line({ 1, 1, 1 }, s.x, s.y, s.x + len, s.y, 1, .2 + speed * .7)
    if speed > .6 then G.line("#a0c0ff", s.x - 2, s.y - 1, s.x + len * .6, s.y - 1, .5, .2 + speed * .7) end
  end
  if storeTimer > 0 then dStore() end
end

function dStore()
  G.rect("#040210", 0, 0, SW, SH, .94)
  G.text("ARMERIA", SW / 2, 40, "center", F("orb", 22), "#ffe95a")
  G.text("NÍVEL " .. (levelNum - 1) .. " COMPLETO  ·  +20 MOEDAS BÓNUS", SW / 2, 60, "center", F("vt", 16), "#7fe9ff")
  local panelW = numPlayers == 1 and 560 or 374
  for pi = 1, numPlayers do
    local p = players[pi]
    local px = numPlayers == 1 and (SW - panelW) / 2 or 8 + (pi - 1) * (panelW + 36)
    local py = 74
    G.rect("#0a0420", px, py, panelW, 300, .9); G.srect(p.col.m, px + .5, py + .5, panelW - 1, 299, 1, .7)
    G.text("P" .. pi, px + 14, py + 22, "left", F("vt", 20), p.col.m)
    G.text("$ " .. p.coins, px + 46, py + 22, "left", F("vt", 20), P.gold)
    local items = {
      { "b1", "X", "ARMA", WEAPON_NAMES[min(p.weaponLvl + 2, 10)], "+10% dano", COST_WEAPON, P.gold, p.weaponLvl >= 9 },
      { "b2", "Y", "CADÊNCIA", "Tiro rápido", "dispara 2x mais", COST_FIRE, P.fire, p.fireRate },
      { "b3", "L1", "SALTO x2", "Duplo salto", "salto extra no ar", COST_DJUMP, P.djump, p.doubleJump },
      { "b4", "R1", "PARAQUEDAS", "Queda lenta", "segura A a cair", COST_PARA, P.para, p.parachute },
    }
    local cw = (panelW - 30) / 2
    for i, it in ipairs(items) do
      local col, row = (i - 1) % 2, floor((i - 1) / 2)
      local cx, cy = px + 10 + col * (cw + 10), py + 40 + row * 126
      local owned, can = it[8], (not it[8]) and p.coins >= it[6]
      local edge = owned and "#30ff60" or can and it[7] or "#3a2040"
      G.rect(owned and "#0a2412" or can and "#160a2a" or "#0c0814", cx, cy, cw, 116)
      G.srect(edge, cx + .5, cy + .5, cw - 1, 115, can and 2 or 1)
      G.text(it[3], cx + 10, cy + 22, "left", F("vt", 20), owned and "#50ff70" or can and it[7] or "#664455")
      G.text(it[4], cx + 10, cy + 42, "left", F("vt", 16), owned and "#aaeebb" or "#ccccee")
      G.text(it[5], cx + 10, cy + 60, "left", F("vt", 16), "#8a7aa8")
      local label = owned and "COMPRADO" or (can and ("[" .. it[2] .. "]  COMPRAR  " .. it[6] .. "$") or (it[6] .. "$  —  sem moedas"))
      local a = can and (.75 + math.sin(gFrame * .18) * .25) or 1
      G.rect(owned and "#0a2a10" or can and "#401030" or "#120a1c", cx + 6, cy + 86, cw - 12, 22, a)
      G.text(label, cx + cw / 2, cy + 102, "center", F("vt", 16), owned and "#40ff60" or can and it[7] or "#665566", a)
    end
  end
  local cont = storeTimer > 60
  G.text(cont and "[ START ]  PRÓXIMO NÍVEL" or "aguarda...", SW / 2, SH - 26, "center", F("vt", 22), cont and "#ffffff" or "#445566", cont and (.7 + math.sin(gFrame * .1) * .3) or .5)
end

-- ═══ GAME OVER + local high scores (arcade initials) ══════════
local deadT, initials, initPos, scoreSaved = 0, { 1, 1, 1 }, 1, false
local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
function enterDead() gState = "DEAD"; deadT = 0; initials = { 1, 1, 1 }; initPos = 1; scoreSaved = false end
local function totalCoins() local s = 0; for _, p in ipairs(players) do s = s + p.coins end; return s end

function uDead()
  deadT = deadT + 1
  if deadT < 40 then return end
  if not scoreSaved then
    if I.anyPress("up") then initials[initPos] = (initials[initPos] - 2) % #ALPHA + 1; A.play("menuMove") end
    if I.anyPress("down") then initials[initPos] = initials[initPos] % #ALPHA + 1; A.play("menuMove") end
    if I.anyPress("left") then initPos = max(1, initPos - 1) end
    if I.anyPress("right") then initPos = min(3, initPos + 1) end
    if I.anyPress("jump") or I.anyPress("start") then
      if initPos < 3 and I.anyPress("jump") then initPos = initPos + 1; A.play("menuConfirm")
      else
        local name = ""
        for i = 1, 3 do name = name .. ALPHA:sub(initials[i], initials[i]) end
        saveScore(name, numPlayers == 1 and "solo" or "duo", levelNum, totalCoins())
        scoreSaved = true; A.play("menuConfirm")
      end
    end
    if I.anyPress("shoot") then scoreSaved = true end      -- skip
    return
  end
  if I.anyPress("start") or I.anyPress("jump") then local np = numPlayers; resetPersist(); numPlayers = np; clearSave(); saveGame(); initLevel(false)
  elseif I.anyPress("back") or I.anyPress("shoot") then netlanLeave(); resetPersist(); clearSave(); A.stopMusic(); initGame() end
end

function dDead()
  G.rect({ 0, 0, 0 }, 0, 0, SW, SH, .9)
  G.text("EQUIPA ELIMINADA", SW / 2, 56, "center", F("orb", 30), "#cc2020")
  G.text("TODOS OS UPGRADES PERDIDOS", SW / 2, 78, "center", F("vt", 16), "#886666")
  for i, p in ipairs(players) do
    G.text("P" .. i .. ":  $" .. p.coins .. "  ·  Nível " .. levelNum .. "  ·  Arma " .. p.weaponLvl, SW / 2, 100 + (i - 1) * 18, "center", F("vt", 16), p.col.m)
  end
  local hy = 140
  G.rect("#0a081c", SW / 2 - 200, hy, 400, 200, .95); G.srect("#334466", SW / 2 - 200 + .5, hy + .5, 399, 199, 1)
  G.text("HIGHSCORES", SW / 2, hy + 20, "center", F("vt", 18), "#6080c0")
  local f = F("vt", 16)
  if not scoreSaved then
    G.text("INICIAIS  (cima/baixo letra · A seguinte · B saltar)", SW / 2, hy + 44, "center", f, "#aabbcc")
    for i = 1, 3 do
      local x = SW / 2 - 40 + (i - 1) * 40
      local sel = i == initPos
      G.rect(sel and "#203070" or "#141030", x - 15, hy + 56, 30, 34)
      G.text(ALPHA:sub(initials[i], initials[i]), x, hy + 84, "center", F("vt", 32), (sel and gFrame % 30 < 20) and "#ffe95a" or "#d0e0ff")
    end
  end
  local y0 = scoreSaved and hy + 44 or hy + 112
  for i = 1, min(#scores, scoreSaved and 8 or 4) do
    local s = scores[i]
    local c = i == 1 and "#ffd700" or i <= 3 and "#aaaacc" or "#6677aa"
    G.text(i .. ". " .. s.name .. "  (" .. s.mode .. ")", SW / 2 - 170, y0 + (i - 1) * 18, "left", f, c)
    G.text("Nv" .. s.level .. "  ·  $" .. s.coins, SW / 2 + 170, y0 + (i - 1) * 18, "right", f, c)
  end
  if #scores == 0 then G.text("ainda sem scores", SW / 2, y0 + 8, "center", f, "#556677") end
  if scoreSaved and floor(gFrame / 30) % 2 == 0 then
    G.text("[A / START]  RECOMEÇAR   ·   [B / SELECT]  MENU", SW / 2, SH - 22, "center", F("vt", 18), "#dddddd")
  end
end

-- ═══ LAN LOBBY ═══════════════════════════════════════════════
function uLanLobby()
  A.startMusic()
  local L = NETL.lobby
  if L == "choose" then
    if I.anyPress("up") then NETL.sel = max(0, NETL.sel - 1); A.play("menuMove") end
    if I.anyPress("down") then NETL.sel = min(2, NETL.sel + 1); A.play("menuMove") end
    if I.anyPress("jump") or I.anyPress("start") then
      A.play("menuConfirm")
      if NETL.sel == 0 then netlanHost() elseif NETL.sel == 1 then netlanBrowse() else gState = "MENU" end
    end
    if I.anyPress("back") or I.anyPress("shoot") then gState = "MENU" end
  elseif L == "browse" then
    local n = #NETL.hosts
    if I.anyPress("up") then NETL.sel = max(0, NETL.sel - 1) end
    if I.anyPress("down") then NETL.sel = min(max(0, n - 1), NETL.sel + 1) end
    if n > 0 and (I.anyPress("jump") or I.anyPress("start")) then
      A.play("menuConfirm")
      local h = NETL.hosts[min(NETL.sel + 1, n)]
      if h.relay then NETL.relayIP = h.ip; NETL.lobby = "online"; NETL.sel = 0; NETL.status = ""
      else netlanJoin(h.ip) end
    end
    if I.anyPress("back") or I.anyPress("shoot") then netlanLeave(); NETL.lobby = "choose" end
  elseif L == "online" then
    if I.anyPress("up") then NETL.sel = max(0, NETL.sel - 1); A.play("menuMove") end
    if I.anyPress("down") then NETL.sel = min(2, NETL.sel + 1); A.play("menuMove") end
    if I.anyPress("jump") or I.anyPress("start") then
      A.play("menuConfirm")
      if NETL.sel == 0 then
        local c = ""
        for _ = 1, 4 do local k = rnd(1, #ROOM_CHARS + 1); c = c .. ROOM_CHARS:sub(k, k) end
        netlanRelay(NETL.relayIP, c, true)
      elseif NETL.sel == 1 then NETL.lobby = "code"; NETL.codeIdx = { 1, 1, 1, 1 }; NETL.codePos = 1
      else netlanBrowse() end
    end
    if I.anyPress("back") or I.anyPress("shoot") then netlanBrowse() end
  elseif L == "code" then
    local ci, cp, nC = NETL.codeIdx, NETL.codePos, #ROOM_CHARS
    if I.anyPress("up") then ci[cp] = (ci[cp] - 2) % nC + 1; A.play("menuMove") end
    if I.anyPress("down") then ci[cp] = ci[cp] % nC + 1; A.play("menuMove") end
    if I.anyPress("left") then NETL.codePos = max(1, cp - 1) end
    if I.anyPress("right") then NETL.codePos = min(4, cp + 1) end
    if I.anyPress("jump") then
      if cp < 4 then NETL.codePos = cp + 1
      else
        local c = ""
        for i = 1, 4 do c = c .. ROOM_CHARS:sub(ci[i], ci[i]) end
        A.play("menuConfirm"); netlanRelay(NETL.relayIP, c, false)
      end
    end
    if I.anyPress("back") or I.anyPress("shoot") then NETL.lobby = "online"; NETL.sel = 1 end
  else
    if I.anyPress("back") or I.anyPress("shoot") then netlanLeave(); NETL.lobby = "choose" end
  end
end

local function lobbySlab(i, label, sel, y)
  local bw, bh, sk = 300, 28, 10
  local bx = SW / 2 - bw / 2
  local slab = { bx + sk, y, bx + bw + sk, y, bx + bw - sk, y + bh, bx - sk, y + bh }
  G.poly(sel and "#e0348e" or "#08001a", slab, sel and 1 or .8)
  G.spoly("#29f3ff", slab, sel and 2 or 1, sel and 1 or .55)
  G.text(label, SW / 2, y + bh / 2 + 7, "center", F("vt", 22), sel and "#ffffff" or "#7fe9ff")
end

function dLanLobby()
  G.vgrad(0, 0, SW, SH, { { 0, "#04010f" }, { .55, "#170533" }, { 1, "#3a0b4e" } })
  for _, s in ipairs(stars) do G.rect({ 1, 1, 1 }, s.x, s.y, s.s, s.s, .25 + s.b * .6) end
  local ft = F("orb", 34)
  G.textStroke("CO-OP LAN", SW / 2, 78, "center", ft, "#ff2f8e", 3)
  G.gradBegin({ { 0, "#ffffff" }, { .45, "#9df4ff" }, { .5, "#2a1a6a" }, { .55, "#ff6ad5" }, { 1, "#ffffff" } }, 50, 80)
  G.text("CO-OP LAN", SW / 2, 78, "center", ft, { 1, 1, 1 })
  G.gradEnd()
  G.rect("#050012", SW / 2 - 230, 100, 460, 280, .85)
  G.srect("#ff2f8e", SW / 2 - 229.5, 100.5, 459, 279, 1, .6)
  G.rect("#ff2f8e", SW / 2 - 230, 100, 460, 2)
  local f16, f18 = F("vt", 16), F("vt", 18)
  local L = NETL.lobby
  if L == "choose" then
    for i, lab in ipairs({ "CRIAR JOGO", "PROCURAR JOGO", "VOLTAR" }) do lobbySlab(i, lab, NETL.sel == i - 1, 140 + (i - 1) * 44) end
    G.text("As duas consolas têm de estar na mesma rede Wi-Fi.", SW / 2, 300, "center", f16, "#8a7aa8")
  elseif L == "browse" then
    G.text("JOGOS NA REDE", SW / 2, 136, "center", f18, "#7fe9ff")
    if #NETL.hosts == 0 then
      G.text(NETL.status, SW / 2, 200, "center", f18, gFrame % 40 < 26 and "#ff6ad5" or "#c0127a")
    else
      for i, h in ipairs(NETL.hosts) do lobbySlab(i, h.name, NETL.sel == i - 1, 150 + (i - 1) * 38) end
    end
    G.text("A entrar  ·  B voltar", SW / 2, 350, "center", f16, "#8a7aa8")
  elseif L == "online" then
    G.text("ONLINE · RELAY " .. (NETL.relayIP or ""), SW / 2, 132, "center", f18, "#7fe9ff")
    for i, lab in ipairs({ "CRIAR SALA", "ENTRAR COM CÓDIGO", "VOLTAR" }) do lobbySlab(i, lab, NETL.sel == i - 1, 150 + (i - 1) * 44) end
    G.text("Joga com quem estiver no browser ou noutra consola.", SW / 2, 300, "center", f16, "#8a7aa8")
    if NETL.status ~= "" then G.text(NETL.status, SW / 2, 325, "center", f16, "#ff4040") end
  elseif L == "code" then
    G.text("CÓDIGO DA SALA", SW / 2, 150, "center", f18, "#7fe9ff")
    for i = 1, 4 do
      local x, sel = SW / 2 - 90 + (i - 1) * 48, i == NETL.codePos
      G.rect("#141030", x, 170, 40, 52)
      G.srect(sel and "#ffe95a" or "#29f3ff", x + .5, 170.5, 39, 51, sel and 2 or 1)
      local k = NETL.codeIdx[i]
      G.text(ROOM_CHARS:sub(k, k), x + 20, 212, "center", F("vt", 40), (sel and gFrame % 30 < 20) and "#ffffff" or "#ffe95a")
    end
    G.text("cima/baixo letra  ·  A seguinte  ·  B voltar", SW / 2, 260, "center", f16, "#8a7aa8")
  else
    local online = NETL.transport == "relay"
    G.text(NETL.mode == "host" and (online and "A TUA SALA" or "ESTA CONSOLA É O ANFITRIÃO") or (online and "SALA" or "A LIGAR"), SW / 2, 150, "center", f18, "#7fe9ff")
    if online then G.text(NETL.code or "", SW / 2, 210, "center", F("vt", 64), "#ffe95a")
    elseif NETL.mode == "host" then G.text(NETL.ip, SW / 2, 205, "center", F("vt", 48), "#ffe95a") end
    G.text(NETL.status, SW / 2, 250, "center", f18, gFrame % 40 < 26 and "#ff6ad5" or "#c0127a")
    G.text("B cancela", SW / 2, 350, "center", f16, "#8a7aa8")
  end
  G.text("No LAN cada jogador usa o seu comando (ou as teclas do P1).", SW / 2, SH - 22, "center", F("vt", 14), "#6a6890")
end

function dNetBadge()
  if not NETL.mode or gState == "LOBBY" or not NETL.started then return end
  local f = F("vt", 14)
  G.rect({ 0, 0, 0 }, SW - 200, SH - 24, 190, 16, .55)
  G.text("* " .. (NETL.transport == "relay" and ("ONLINE · " .. (NETL.code or "")) or "LAN") .. " · " .. (NETL.mode == "host" and "ANFITRIÃO" or "CONVIDADO"), SW - 14, SH - 12, "right", f, NETL.peer and "#3cffaa" or "#ff4040")
  if NETL.lost then
    G.rect({ 0, 0, 0 }, 0, SH / 2 - 34, SW, 68, .75)
    G.text(NETL.mode == "host" and "O 2.º JOGADOR SAIU" or "LIGAÇÃO PERDIDA", SW / 2, SH / 2, "center", F("vt", 26), "#ff4040")
    G.text(NETL.mode == "host" and "Podes continuar sozinho  ·  Start volta ao menu" or "Start volta ao menu", SW / 2, SH / 2 + 22, "center", f, "#dddddd")
  end
end
