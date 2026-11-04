-- Dev-only smoke test:  love gamedata --autotest
-- Walks through every screen, saves screenshots to the save folder and quits.
local T = {}
local step, wait = 0, 0
local shots = {}

local function shot(name)
  love.graphics.captureScreenshot("autotest_" .. name .. ".png")
  shots[#shots + 1] = name
  print("[autotest] screenshot " .. name .. " state=" .. gState)
end

local plan = {
  { 90, function() shot("1_menu") end },
  { 1, function() numPlayers = 1; resetPersist(); gState = "CIN_SPACE"; cinT = 0; cShots = {}
      cs = { x = -80, y = SH * .44, vx = 3.5, vy = 0, angle = 0, av = 0, scale = .7, exploding = false, explodeT = 0, crashed = false, tumbleAv = 0, tumbleAngle = 0 } end },
  { 200, function() shot("2_space") end },
  { 1, function() while gState == "CIN_SPACE" do T.tick() end end },
  { 240, function() shot("3_orbit") end },
  { 1, function() while gState == "CIN_ORBIT" do T.tick() end end },
  { 1, function() while not crashDone do T.tick() end end },
  { 40, function() shot("4_crash_debris") end },
  { 1, function() local n = 0; while gState == "CIN_CRASH" and n < 2000 do T.tick(); n = n + 1 end; print("[autotest] play state=" .. gState) end },
  { 1, function() anyMoved = true; spawnBoss() end },
  { 420, function() shot("5_play_boss"); print("[autotest] boss=" .. tostring(boss and boss.name)) end },
  { 1, function() for _, p in ipairs(players) do p.coins = 260 end; boss.hp = 0 end },
  { 1, function() local n = 0; while gState ~= "WARP" and n < 3000 do T.tick(); n = n + 1 end; print("[autotest] after extract state=" .. gState) end },
  { 150, function() shot("6_store") end },
  { 1, function() for _, p in ipairs(players) do p.hp = 0 end end },
  { 1, function() initLevel(false); local n = 0; while gState ~= "PLAY" and n < 3000 do T.tick(); n = n + 1 end; for _, p in ipairs(players) do p.hp = 0 end end },
  { 80, function() shot("7_dead") end },
  { 30, function() print("[autotest] done: " .. #shots .. " screenshots in " .. love.filesystem.getSaveDirectory()); love.event.quit() end },
}

function T.update()
  if wait > 0 then wait = wait - 1; return end
  step = step + 1
  local s = plan[step]
  if not s then return end
  s[2]()
  wait = (plan[step + 1] and plan[step + 1][1]) or 0
end

return T
