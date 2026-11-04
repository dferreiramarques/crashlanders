-- Procedural SID-style audio: every sound effect and the fugue loop are
-- synthesised into SoundData at load time (no audio files needed).
local A = {}
local SR = 22050
local MASTER = 0.4
local TAU = math.pi * 2
local exp, floor, abs, sin = math.exp, math.floor, math.abs, math.sin

local N = {
  C2 = 65.41, D2 = 73.42, E2 = 82.41, A2 = 110,
  C3 = 130.81, D3 = 146.83, E3 = 164.81, G3 = 196, A3 = 220,
  C4 = 261.63, E4 = 329.63, G4 = 392, C5 = 523.25, E5 = 659.25, G5 = 784, A5 = 880,
}
A.N = N

local function osc(kind, p)
  p = p % 1
  if kind == "square" then return p < .5 and 1 or -1
  elseif kind == "sawtooth" then return 2 * p - 1
  elseif kind == "triangle" then return 1 - 4 * abs(p - .5)
  end
  return sin(p * TAU)
end

-- Buffer helpers --------------------------------------------------------------
local function newBuf(sec)
  local n = floor(sec * SR) + 1
  local b = {}
  for i = 1, n do b[i] = 0 end
  return { d = b, n = n, wrap = false }
end
local function put(buf, i, v)
  if buf.wrap then i = (i % buf.n) end
  local k = i + 1
  if k >= 1 and k <= buf.n then buf.d[k] = buf.d[k] + v end
end

-- tone(): oscillator → 1-pole low-pass → ADSR (same envelope as the web build)
local function tone(buf, f, kind, vol, a, d, sus, r, dur, t0, fCut)
  if not f or f <= 0 then return end
  local al = 1 - exp(-TAU * (fCut or 7000) / SR)
  local lp, ph = 0, 0
  local i0 = floor(t0 * SR)
  local total = floor((dur + r) * SR)
  for i = 0, total do
    local t = i / SR
    local env
    if t < a then env = vol * t / a
    elseif t < a + d then env = vol + (vol * sus - vol) * ((t - a) / d)
    elseif t < dur then env = vol * sus
    else env = vol * sus * math.max(0, 1 - (t - dur) / r) end
    ph = ph + f / SR
    lp = lp + al * (osc(kind, ph) - lp)
    put(buf, i0 + i, lp * env)
  end
end

local function sweep(buf, f0, f1, kind, vol, dur, t0)
  f1 = math.max(f1, 10)
  local ph = 0
  local i0 = floor((t0 or 0) * SR)
  local total = floor(dur * SR)
  for i = 0, total do
    local k = i / total
    local f = f0 * (f1 / f0) ^ k
    ph = ph + f / SR
    put(buf, i0 + i, osc(kind, ph) * vol * (1 - k))
  end
end

local function noise(buf, vol, dur, t0, fCut, ftype)
  fCut = fCut or 500
  local i0 = floor((t0 or 0) * SR)
  local total = floor(dur * SR)
  local a1 = 1 - exp(-TAU * fCut * 1.6 / SR)
  local a2 = 1 - exp(-TAU * fCut / 1.6 / SR)
  local aL = 1 - exp(-TAU * fCut / SR)
  local l1, l2, lL = 0, 0, 0
  for i = 0, total do
    local s = love.math.random() * 2 - 1
    local out
    if ftype == "lowpass" then lL = lL + aL * (s - lL); out = lL
    else l1 = l1 + a1 * (s - l1); l2 = l2 + a2 * (s - l2); out = (l1 - l2) * 1.6 end
    local env = vol * (0.0001 / vol) ^ (i / total)
    put(buf, i0 + i, out * env)
  end
end

local function toSource(buf, loop)
  local sd = love.sound.newSoundData(buf.n, SR, 16, 1)
  for i = 1, buf.n do
    local v = buf.d[i] * MASTER
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i - 1, v)
  end
  local src = love.audio.newSource(sd)
  src:setLooping(loop or false)
  return src
end

-- Sound effects ----------------------------------------------------------------
local defs = {
  shoot   = { .08, function(b) sweep(b, 760, 360, "square", .06, .065) end },
  jump    = { .12, function(b) sweep(b, 240, 580, "square", .09, .1) end },
  jumpAir = { .12, function(b) sweep(b, 360, 820, "square", .09, .1) end },
  land    = { .08, function(b) noise(b, .13, .05, 0, 220); sweep(b, 90, 50, "triangle", .07, .045) end },
  hit     = { .16, function(b) noise(b, .22, .12, 0, 380); sweep(b, 260, 70, "sawtooth", .1, .13) end },
  bossHit = { .07, function(b) sweep(b, 160, 80, "sawtooth", .08, .055) end },
  coin    = { .14, function(b)
    tone(b, N.C5, "square", .09, .001, .01, 1, .01, .05, 0)
    tone(b, N.E5, "square", .09, .001, .01, 1, .01, .05, .065) end },
  explode = { .45, function(b) noise(b, .3, .4, 0, 260); noise(b, .2, .3, 0, 120); sweep(b, 110, 35, "sawtooth", .12, .35) end },
  burst   = { .12, function(b) noise(b, .15, .09, 0, 900); sweep(b, N.E4, N.A5, "square", .09, .09) end },
  revive  = { .4, function(b)
    for i, f in ipairs({ N.C4, N.E4, N.G4, N.C5 }) do tone(b, f, "square", .09, .001, .01, .8, .03, .065, (i - 1) * .08) end end },
  levelEnd = { .7, function(b)
    for i, f in ipairs({ N.C4, N.E4, N.G4, N.C5, N.E5, N.G5 }) do tone(b, f, "square", .1, .001, .02, .8, .05, .11, (i - 1) * .09) end end },
  death   = { .7, function(b)
    noise(b, .22, .45, 0, 200)
    for i, f in ipairs({ N.G4, N.E4, N.C4, N.A3 }) do tone(b, f, "sawtooth", .09, .001, .02, .6, .07, .09, (i - 1) * .13) end end },
  menuMove    = { .05, function(b) sweep(b, 280, 340, "square", .04, .04) end },
  menuConfirm = { .14, function(b)
    tone(b, N.G4, "square", .08, .001, .01, 1, .02, .04, 0)
    tone(b, N.C5, "square", .08, .001, .01, 1, .02, .04, .065) end },
  para    = { .18, function(b) noise(b, .05, .16, 0, 600, "lowpass") end },
  laser   = { .12, function(b) sweep(b, 2200, 180, "square", .09, .1); noise(b, .04, .06, 0, 1400) end },
  thruster = { .2, function(b) noise(b, .03, .18, 0, 70, "lowpass") end },
  bossShoot = { .08, function(b) noise(b, .08, .04, 0, 600); sweep(b, 220, 120, "square", .07, .06) end },
  bossJump  = { .2, function(b) sweep(b, 60, 180, "sawtooth", .14, .18) end },
  slam      = { .27, function(b) sweep(b, 400, 60, "sawtooth", .12, .25) end },
  charge    = { .57, function(b) sweep(b, 120, 900, "square", .05, .55) end },
  pickup    = { .14, function(b) sweep(b, N.C4, N.G4, "triangle", .08, .12) end },
}

local pool = {}

-- Fugue loop (same score as the web build) --------------------------------------
local BPM = 90
local S16 = 60 / BPM / 4
local FSUB = { 0, false, 7, 3, 0, -2, -4, false, -5, -7, -9, -12, false, false, 0, 7 }
local FCTR = { 12, 14, 15, 17, false, 15, 14, 12, false, 10, 9, 7, 5, false, 3, 0 }
local FBAS = { N.C2, 55, N.D2, N.E2 }
local FROOT = { N.C3, N.A2, N.D3, N.E3 }
local function st(root, s) return root * 2 ^ (s / 12) end
local HTYPES = { "sawtooth", "square", "triangle", "square" }

local function renderMusic()
  local buf = newBuf(64 * S16)
  buf.wrap = true                       -- tails wrap around → seamless loop
  local function harm(freq, h, vol, t, dur)
    for k = 1, h do tone(buf, freq * k, HTYPES[k], vol / math.sqrt(k), .003, .03, .6, .05, dur, t, 3500 / k) end
  end
  for step = 0, 63 do
    local t = step * S16
    local sec = floor(step / 16)
    local ss = step % 16
    if ss == 0 then
      tone(buf, FBAS[sec + 1], "sawtooth", .18, .01, .05, .8, .12, S16 * 15.4, t, 400)
      tone(buf, FBAS[sec + 1] * 1.5, "sawtooth", .08, .005, .05, .6, .1, S16 * 7.5, t, 500)
    end
    local si = FSUB[ss + 1]
    if si then harm(st(FROOT[sec + 1], si), sec + 1, .095 - sec * .008, t, S16 * .88) end
    for v = 0, sec - 1 do
      local ci = FCTR[((ss + v * 4) % 16) + 1]
      if ci then harm(st(FROOT[v + 1], ci - 12), v + 1, .055 - v * .008, t, S16 * .75) end
    end
    if ss == 0 or ss == 8 then noise(buf, .05 + sec * .008, .05, t, 160) end
    if ss == 4 or ss == 12 then noise(buf, .025, .025, t, 2200) end
    if ss == 8 and sec >= 2 then noise(buf, .04, .08, t, 80, "lowpass") end
  end
  return toSource(buf, true)
end

local music
function A.load()
  for name, d in pairs(defs) do
    local b = newBuf(d[1])
    d[2](b)
    pool[name] = { toSource(b) }
  end
  music = renderMusic()
end

function A.play(name)
  local p = pool[name]
  if not p then return end
  for _, s in ipairs(p) do
    if not s:isPlaying() then s:play(); return end
  end
  if #p < 6 then
    local s = p[1]:clone()
    p[#p + 1] = s
    s:play()
  end
end

function A.startMusic() if music and not music:isPlaying() then music:play() end end
function A.stopMusic() if music then music:stop() end end
function A.musicPlaying() return music and music:isPlaying() end

return A
