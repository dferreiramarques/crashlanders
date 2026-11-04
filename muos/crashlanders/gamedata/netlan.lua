-- LAN co-op + online cross-play via relay. Host-authoritative, same messages as the web build.
--  * Online: the console talks plain TCP (one JSON per line) to relay/relay.js, which joins the
--    browser's Supabase room on its behalf — so consoles and browsers share the same 4-letter rooms.
--  * Discovery: the host broadcasts "CRASHLANDERS|<name>" over UDP; guests list them.
--  * Transport: ENet (bundled with LÖVE). Guest → host: buttons. Host → guest: ~30 snapshots/s.
local J = require "json"
local A = require "audio"
local I = require "input"
local socket = require "socket"
local udp4 = socket.udp4 or socket.udp   -- plain udp() may pick IPv6 and then refuse IPv4 sends
local enet = require "enet"
local floor = math.floor

local DISC_PORT, GAME_PORT, RELAY_PORT = 47231, 47232, 47240
local tcp4 = socket.tcp4 or socket.tcp
ROOM_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local tcp, outbuf, inpart = nil, "", ""
local ACTIONS = { left = "left", right = "right", up = "aimUp", down = "aimDown", jump = "jump", shoot = "shoot", b1 = "b1", b2 = "b2", b3 = "b3", b4 = "b4" }

NETL = { mode = nil, started = false, peer = nil, lost = false, status = "", remote = {}, remotePrev = {},
  events = {}, hosts = {}, sel = 0, lobby = "choose", lastIn = "", lastInF = 0, lastSnapT = 0, ip = "?" }
mapDirty = true

local host, udp, discT = nil, nil, 0

local function localIP()
  local s = udp4()
  s:setpeername("10.255.255.255", 9)          -- no packet is sent; just picks the LAN interface
  local ip = s:getsockname()
  s:close()
  return ip or "?"
end

-- ── Remote player input (used by actors.lua) ──
function PIN(p, a) if p.remote then return NETL.remote[ACTIONS[a]] == 1 end return I.down(p.id, a) end
function PPRESS(p, a)
  if p.remote then local w = ACTIONS[a]; return NETL.remote[w] == 1 and NETL.remotePrev[w] ~= 1 end
  return I.pressed(p.id, a)
end

-- ── Mirror particles / sounds from the host simulation ──
local origFx, origPlay = fx, A.play
local function r1(v) if type(v) == "number" then return floor(v * 10 + .5) / 10 end return v end
local function hexcol(c)
  if type(c) ~= "table" then return c end
  return string.format("#%02x%02x%02x", floor(c[1] * 255 + .5), floor(c[2] * 255 + .5), floor(c[3] * 255 + .5))
end
fx = function(x, y, n, col, spd, sz)
  if NETL.mode == "host" and NETL.started then NETL.events[#NETL.events + 1] = { "f", r1(x), r1(y), n, hexcol(col), spd or 3, sz or 2 } end
  return origFx(x, y, n, col, spd, sz)
end
A.play = function(name)
  if NETL.mode == "host" and NETL.started then NETL.events[#NETL.events + 1] = { "p", name } end
  return origPlay(name)
end

-- ── Session control ──
function netlanHost()
  netlanLeave()
  host = enet.host_create("*:" .. GAME_PORT, 2, 2)
  if not host then NETL.status = "Porta " .. GAME_PORT .. " ocupada"; return end
  udp = udp4(); udp:settimeout(0); udp:setsockname("0.0.0.0", 0); udp:setoption("broadcast", true)
  NETL.mode, NETL.lobby, NETL.ip = "host", "wait", localIP()
  NETL.status = "À espera do 2.º jogador…"
end

function netlanBrowse()
  netlanLeave()
  udp = udp4(); udp:settimeout(0)
  local ok = udp:setsockname("0.0.0.0", DISC_PORT)
  NETL.mode, NETL.lobby, NETL.hosts, NETL.sel = "browse", "browse", {}, 0
  NETL.status = ok and "A procurar jogos na rede…" or "Não foi possível escutar a porta " .. DISC_PORT
end

function netlanJoin(ip)
  if udp then udp:close(); udp = nil end
  host = enet.host_create(nil, 1, 2)
  host:connect(ip .. ":" .. GAME_PORT, 2)
  NETL.mode, NETL.lobby, NETL.status, NETL.joinIP = "guest", "wait", "A ligar a " .. ip .. "…", ip
  initLevel(true); gState = "LOBBY"
end

-- Online room through the relay (asHost: create a room; otherwise join `code`)
function netlanRelay(ip, code, asHost)
  netlanLeave()
  tcp = tcp4()
  tcp:settimeout(3)
  local ok, err = tcp:connect(ip, RELAY_PORT)
  if not ok then NETL.lobby, NETL.status = "online", "Relay indisponível (" .. tostring(err) .. ")"; tcp = nil; return end
  tcp:settimeout(0); tcp:setoption("tcp-nodelay", true)
  outbuf, inpart = "", ""
  NETL.transport, NETL.mode, NETL.code, NETL.lobby = "relay", asHost and "host" or "guest", code, "wait"
  NETL.status = "A entrar na sala…"
  outbuf = J.encode({ t = "join", room = code, role = NETL.mode }) .. "\n"
  if not asHost then initLevel(true); gState = "LOBBY" end
end

function netlanLeave()
  if NETL.peer then pcall(function() NETL.peer:disconnect_now() end) end
  if host then pcall(function() host:flush(); host:destroy() end) end
  if udp then udp:close() end
  if tcp then pcall(function() tcp:close() end) end
  host, udp, tcp, outbuf, inpart = nil, nil, nil, "", ""
  NETL.transport = nil
  NETL.mode, NETL.started, NETL.peer, NETL.lost = nil, false, nil, false
  NETL.remote, NETL.remotePrev, NETL.events = {}, {}, {}
  for _, p in ipairs(players) do p.remote = false end
end

-- ── Snapshots (keys match the web build) ──
local function r2(v) if type(v) == "number" then return floor(v * 100 + .5) / 100 end return v end
local function pack(o, keys) local r = {}; for _, k in ipairs(keys) do r[k] = r2(o[k]) end; return r end
local PK = { "x", "y", "vx", "vy", "hp", "maxHP", "facing", "aimAngle", "iframes", "onGround", "coins", "weaponLvl", "fireRate", "doubleJump", "parachute", "dmgMult", "airJumps", "reviveTimer", "jh", "sh", "shootCD", "boarded" }
local BK = { "x", "y", "vx", "vy", "hp", "facing", "state", "burstState", "burstWindup", "burstTimer", "flash", "laserT", "laserAng", "mouthT", "rising", "hitCounter", "dmgDropped", "onGround", "name", "legs", "arms", "eyes" }

local function encodeMap()
  local t = {}
  for y = 0, MH - 1 do for x = 0, MW - 1 do
    t[#t + 1] = map[y][x] == 1 and string.char(65 + tileHP[y][x] * 2 + tileKind[y][x]) or "."
  end end
  return table.concat(t)
end
local function decodeMap(s)
  local i = 1
  for y = 0, MH - 1 do for x = 0, MW - 1 do
    local c = s:byte(i); i = i + 1
    if c == 46 or not c then map[y][x], tileHP[y][x], tileKind[y][x] = 0, 0, 0
    else local v = c - 65; map[y][x], tileHP[y][x], tileKind[y][x] = 1, floor(v / 2), v % 2 end
  end end
end

local function snapshot()
  local s = { src = "love", g = gState, f = gFrame, lv = levelNum, np = numPlayers, sh = shake, ct = cinT, gh = lvl.groundHue, bh = lvl.bossHue,
    pl = {}, pb = {}, bb = {}, dr = {}, ev = NETL.events }
  NETL.events = {}
  for i, p in ipairs(players) do s.pl[i] = pack(p, PK) end
  for i, b in ipairs(pBullets) do s.pb[i] = pack(b, { "x", "y", "vx", "vy", "pid" }) end
  for i, b in ipairs(bBullets) do s.bb[i] = pack(b, { "x", "y", "vx", "vy", "r", "burst" }) end
  for i, d in ipairs(drops) do s.dr[i] = pack(d, { "x", "y", "type", "bob" }) end
  if bossSpawned and boss then s.bo = pack(boss, BK); s.bo.pid = bossPartIds() end
  if gState == "CIN_SPACE" or gState == "CIN_ORBIT" or gState == "CIN_CRASH" then
    s.cs = cs; s.cshots = cShots; s.planet = planet; s.crashDone = crashDone
    s.debris = {}
    for i, d in ipairs(debris) do s.debris[i] = pack(d, { "x", "y", "w", "h", "angle", "t", "landed" }) end
  end
  if gState == "EXTRACT" and extractShip then s.es = extractShip; s.et = extractTimer end
  if gState == "WARP" then s.wt = warpTimer; s.st = storeTimer end
  if mapDirty or gFrame % 60 == 0 then s.map = encodeMap(); mapDirty = false end
  if gFrame % 6 == 0 then s.dust = {}; for x = 0, MW - 1 do s.dust[x + 1] = floor(dustPiles[x] + .5) end end
  return s
end

local function applySnap(s)
  NETL.started = true; NETL.lastSnapT = love.timer.getTime()
  gState, levelNum, numPlayers, cinT, gFrame = s.g, s.lv, s.np, s.ct, s.f
  shake = math.max(shake, s.sh or 0)
  if lvl.groundHue ~= s.gh or lvl.bossHue ~= s.bh then setLvlPalette(s.gh, s.bh) end
  for i, q in ipairs(s.pl) do
    local p = players[i]
    if not p then p = newBody(q.x, q.y, PW, PH); p.id = i; p.col = PCOLS[i]; p.kbVx = 0; p.aimElev = 0; players[i] = p end
    for k, v in pairs(q) do p[k] = v end
  end
  for i = #s.pl + 1, #players do players[i] = nil end
  pBullets, bBullets, drops = s.pb, s.bb, s.dr
  if s.bo then
    if not boss then boss = newBody(s.bo.x, s.bo.y, BW, BH) end
    for k, v in pairs(s.bo) do boss[k] = v end
    boss.parts = bossPartsFromIds(s.bo.pid)
    bossSpawned = true
    if A.musicPlaying() then A.stopMusic() end
  else boss, bossSpawned = nil, false end
  if s.cs then cs, cShots, planet, debris, crashDone = s.cs, s.cshots or {}, s.planet, s.debris or {}, s.crashDone end
  if s.es then extractShip, extractTimer = s.es, s.et end
  if s.wt then warpTimer, storeTimer = s.wt, s.st end
  if s.map then decodeMap(s.map) end
  if s.dust then for x = 0, MW - 1 do dustPiles[x] = s.dust[x + 1] or 0 end end
  for _, e in ipairs(s.ev or {}) do
    if e[1] == "f" then origFx(e[2], e[3], e[4], e[5], e[6], e[7])
    elseif e[1] == "p" then origPlay(e[2]) end
  end
end

local function send(tbl, reliable)
  if NETL.transport == "relay" then
    if tcp and (reliable or #outbuf < 24000) then outbuf = outbuf .. J.encode(tbl) .. "\n" end   -- drop snapshots if backed up
  elseif NETL.peer then NETL.peer:send(J.encode(tbl), reliable and 1 or 0, reliable and "reliable" or "unreliable") end
end
local function flush() if host then host:flush() end end

local function handle(m)
  if not m then return end
  if NETL.mode == "host" and m.t == "in" then NETL.remote = m.k or {}
  elseif NETL.mode == "guest" and m.t == "snap" then applySnap(m.s)
  elseif m.t == "peer" then
    if m.on and not NETL.peer then NETL.peer = true; NETL.lost = false; onPeerJoinedRelay()
    elseif not m.on and NETL.peer then NETL.peer = nil; NETL.remote = {}; if NETL.started then NETL.lost = true end end
  elseif m.t == "status" then
    if m.st == "SUBSCRIBED" and not NETL.peer then NETL.status = NETL.mode == "host" and "À espera do 2.º jogador…" or "À espera do anfitrião…"
    elseif m.st ~= "SUBSCRIBED" then NETL.status = "Relay: " .. tostring(m.st) end
  end
end

local function pollRelay()
  if not tcp then return end
  if #outbuf > 0 then
    local n, err, partial = tcp:send(outbuf)
    local sent = n or partial or 0
    outbuf = outbuf:sub(sent + 1)
    if err == "closed" then tcp = nil end
  end
  while tcp do
    local line, err, part = tcp:receive("*l", inpart)
    if line then inpart = ""; handle(J.decode(line))
    else
      inpart = part or ""
      if err == "closed" then tcp = nil; NETL.peer = nil; if NETL.started then NETL.lost = true else NETL.status = "Relay fechou a ligação" end end
      break
    end
  end
end

function onPeerJoinedRelay() onPeerJoined() end
function onPeerJoined()
  if NETL.mode == "host" then
    NETL.started = true; numPlayers = 2; levelNum = 1
    persist = { { weaponLvl = 0, coins = 0, fireRate = false, doubleJump = false, parachute = false },
                { weaponLvl = 0, coins = 0, fireRate = false, doubleJump = false, parachute = false } }
    initLevel(true); startCin()
  else NETL.status = "Ligado! À espera do jogo…" end
end

-- Called every frame (before the simulation step)
function netlanPoll()
  if NETL.mode == "host" and udp then
    discT = discT + 1
    if discT % 30 == 1 and not NETL.peer then
      local msg = "CRASHLANDERS|" .. (love.system.getOS() .. "-" .. NETL.ip)
      udp:sendto(msg, "255.255.255.255", DISC_PORT)
      udp:sendto(msg, "127.0.0.1", DISC_PORT)            -- same-machine testing
    end
  elseif NETL.mode == "browse" and udp then
    while true do
      local data, ip = udp:receivefrom()
      if not data then break end
      local name = data:match("^CRASHLANDERS|(.+)$")
      local rname = data:match("^CRASHRELAY|(.+)$")
      if rname then
        local found = false
        for _, h in ipairs(NETL.hosts) do if h.relay and (h.ip == ip or h.name == rname) then h.t = love.timer.getTime(); found = true end end
        if not found then NETL.hosts[#NETL.hosts + 1] = { ip = ip, name = "ONLINE (relay " .. rname .. ")", relay = true, t = love.timer.getTime() } end
      end
      if name then
        local found = false
        for _, h in ipairs(NETL.hosts) do if not h.relay and (h.ip == ip or h.name == name) then h.t = love.timer.getTime(); found = true end end
        if not found then NETL.hosts[#NETL.hosts + 1] = { ip = ip, name = name, t = love.timer.getTime() } end
      end
    end
    for i = #NETL.hosts, 1, -1 do if love.timer.getTime() - NETL.hosts[i].t > 4 then table.remove(NETL.hosts, i) end end
  end
  pollRelay()
  if not host then return end
  while true do
    local ok, ev = pcall(host.service, host, 0)
    if not ok or not ev then break end
    if ev.type == "connect" then
      if not NETL.peer then NETL.peer = ev.peer; NETL.lost = false; onPeerJoined() else ev.peer:disconnect() end
    elseif ev.type == "disconnect" then
      if ev.peer == NETL.peer then NETL.peer = nil; NETL.remote = {}; if NETL.started then NETL.lost = true else NETL.status = "Ligação recusada" end end
    elseif ev.type == "receive" then
      local m = J.decode(ev.data)
      if m then
        if NETL.mode == "host" and m.t == "in" then NETL.remote = m.k or {}
        elseif NETL.mode == "guest" and m.t == "snap" then applySnap(m.s) end
      end
    end
  end
end

-- Host: after each simulation step
function netlanHostTick()
  if not NETL.started then NETL.events = {}; return end
  if gState == "PLAY" and next(NETL.remote) then anyMoved = true end
  NETL.remotePrev = {}
  for k, v in pairs(NETL.remote) do NETL.remotePrev[k] = v end
  if NETL.peer and gFrame % 2 == 0 then send({ t = "snap", s = snapshot() }, false); flush() end
  if NETL.lost and I.anyPress("start") then netlanLeave(); initGame() end
end

-- Guest: replaces the simulation step
function netlanGuestUpdate()
  local k = {}
  local keys = {}
  for a, w in pairs(ACTIONS) do if I.down(1, a) or (LANTEST_KEYS and LANTEST_KEYS[a]) then k[w] = 1; keys[#keys + 1] = w end end
  table.sort(keys)
  local sig = table.concat(keys, ",")
  if NETL.peer and (sig ~= NETL.lastIn or gFrame - NETL.lastInF > 15) then
    send({ t = "in", k = k }, true); flush()
    NETL.lastIn, NETL.lastInF = sig, gFrame
  end
  gFrame = gFrame + 1
  for _, b in ipairs(pBullets) do b.x = b.x + b.vx; b.y = b.y + b.vy end
  for _, b in ipairs(bBullets) do b.x = b.x + b.vx; b.y = b.y + b.vy end
  for _, d in ipairs(drops) do d.bob = (d.bob or 0) + .08 end
  if NETL.started and love.timer.getTime() - NETL.lastSnapT > 5 then NETL.lost = true end
  if I.anyPress("back") or (NETL.lost and I.anyPress("start")) then netlanLeave(); A.stopMusic(); initGame() end
end
