-- CRASHLANDERS — LÖVE 11.5 port (muOS / PortMaster, RG35XX H) of the web build.
-- The game is simulated at a fixed 60 Hz in an 800×450 space and rendered to a
-- canvas that is letterboxed onto whatever screen we get (640×480 on the RG35XX H).
SW, SH = 800, 450

local U = require "util"
local G = require "gfx"
local A = require "audio"
local I = require "input"
require "world"
require "actors"
require "scenes"
require "netlan"            -- after world/actors: wraps fx and A.play
local lg = love.graphics

local canvas, vignette
local STEP = 1 / 60
local acc = 0

local function makeVignette()
  -- low-res radial vignette + rounded CRT corners, scaled up smoothly
  local w, h = 200, 113
  local id = love.image.newImageData(w, h)
  for y = 0, h - 1 do for x = 0, w - 1 do
    local nx, ny = (x + .5) / w - .5, ((y + .5) / h - .5) * (h / w) * 1.6
    local d = math.sqrt(nx * nx + ny * ny) / .62
    local a = math.max(0, math.min(1, (d - .45) / .55)) ^ 1.6 * .55
    local cx, cy = math.min(x, w - 1 - x), math.min(y, h - 1 - y)
    local r = 4.5
    if cx < r and cy < r and (r - cx) ^ 2 + (r - cy) ^ 2 > r * r then a = 1 end
    id:setPixel(x, y, 0, 0, 0, a)
  end end
  local img = lg.newImage(id)
  img:setFilter("linear", "linear")
  return img
end

function love.load()
  lg.setDefaultFilter("linear", "linear")
  love.mouse.setVisible(false)
  canvas = lg.newCanvas(SW, SH)
  vignette = makeVignette()
  A.load()
  initGame()
end

local function update()
  gFrame = gFrame + 1
  updateParticles()
  if shake > 0 then shake = shake - 1 end
  if gState == "PLAY" and I.anyPressed then anyMoved = true end
  netlanPoll()
  if NETL.mode == "guest" and gState ~= "LOBBY" then netlanGuestUpdate(); return end
  if gState == "LOBBY" then uLanLobby()
  elseif gState == "MENU" then uMenu()
  elseif gState == "CIN_SPACE" then uCinSpace()
  elseif gState == "CIN_ORBIT" then uCinOrbit()
  elseif gState == "CIN_CRASH" then uCinCrash()
  elseif gState == "PLAY" then uPlay()
  elseif gState == "EXTRACT" then uExtract()
  elseif gState == "WARP" then uWarp()
  elseif gState == "DEAD" then uDead() end
  if NETL.mode == "host" then netlanHostTick() end
end

local autotest
for _, a in ipairs(arg or {}) do if a == "--autotest" then autotest = require "autotest" end end
if autotest then autotest.tick = function() I.update(); update() end end
local lantest
for _, a in ipairs(arg or {}) do
  if a == "--lanhost" or a == "--languest" then lantest = require "lantest"; lantest.role = a == "--lanhost" and "host" or "guest" end
  local rr, code = a:match("^%-%-relay(%a+)=(%w+)$")
  if rr then lantest = require "lantest"; lantest.role = rr; lantest.relay = code; lantest.limit = 150; lantest.hold = 45 end
end

function love.update(dt)
  if autotest then autotest.update() end
  if lantest then lantest.update(dt) end
  acc = acc + math.min(dt, .25)
  local n = 0
  while acc >= STEP and n < 5 do
    I.update()
    update()
    acc = acc - STEP; n = n + 1
  end
  if n == 5 then acc = 0 end
end

local function drawGame()
  lg.clear(0, 0, 0, 1)
  lg.push()
  if shake > 0 then lg.translate((love.math.random() - .5) * shake * 1.1, (love.math.random() - .5) * shake * .7) end
  if gState ~= "MENU" and gState ~= "LOBBY" and gState ~= "CIN_SPACE" and gState ~= "CIN_ORBIT" then
    G.vgrad(0, 0, SW, SH, { { 0, "#060410" }, { 1, "#0d051e" } })
    for _, s in ipairs(stars) do G.rect({ 1, 1, 1 }, s.x, s.y, s.s, s.s, .3 + s.b * .7 * (.8 + .2 * math.sin(gFrame * .04 + s.x))) end
  end
  if gState == "MENU" then dMenu()
  elseif gState == "LOBBY" then dLanLobby()
  elseif gState == "CIN_SPACE" then dCinSpace()
  elseif gState == "CIN_ORBIT" then dCinOrbit()
  elseif gState == "CIN_CRASH" then dMap(); dDustPiles(); dCrash(); dCinBars("CONTROLO PERDIDO", "IMPACTO IMINENTE!")
  elseif gState == "PLAY" or gState == "DEAD" then drawPlay(); dHUD()
  elseif gState == "EXTRACT" then dMap(); dDustPiles(); for _, p in ipairs(players) do dPlayer(p) end; dExtract()
  elseif gState == "WARP" then dWarp() end
  drawParticles()
  if gState == "DEAD" then dDead() end
  dNetBadge()
  lg.pop()
  lg.setColor(1, 1, 1, 1)
  lg.draw(vignette, 0, 0, 0, SW / vignette:getWidth(), SH / vignette:getHeight())
end

function love.draw()
  lg.setCanvas(canvas)
  drawGame()
  lg.setCanvas()
  local ww, wh = lg.getDimensions()
  local s = math.min(ww / SW, wh / SH)
  lg.clear(0, 0, 0, 1)
  lg.setColor(1, 1, 1, 1)
  lg.draw(canvas, math.floor((ww - SW * s) / 2), math.floor((wh - SH * s) / 2), 0, s, s)
end

function love.keypressed(k)
  if k == "f11" then love.window.setFullscreen(not love.window.getFullscreen()) end
end
