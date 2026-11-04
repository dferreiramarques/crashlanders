-- Dev-only LAN smoke test, run two instances on one machine:
--   love gamedata --lanhost      love gamedata --languest
local T = { role = nil, t = 0, phase = 0 }
LANTEST_KEYS = nil

function T.update(dt)
  T.t = T.t + dt
  if T.phase == 0 and T.t > 1 then
    T.phase = 1
    if T.role == "host" then netlanHost() else netlanBrowse() end
    if T.relay then netlanBrowse() end
    print("[lantest] " .. T.role .. " started, status=" .. NETL.status)
  end
  if T.relay and T.phase == 1 then
    for _, h in ipairs(NETL.hosts) do
      if h.relay then
        T.phase = 2; print("[lantest] relay found @ " .. h.ip .. ", room " .. T.relay .. " as " .. T.role)
        netlanRelay(h.ip, T.relay, T.role == "host")
        if T.role == "host" then T.phase = 1.5 end
        break
      end
    end
    return
  end
  if T.phase == 1.5 then T.phase = 1; T.relay = nil end
  if T.role == "guest" and T.phase == 1 and #NETL.hosts > 0 then
    T.phase = 2; print("[lantest] guest found " .. NETL.hosts[1].name .. " @ " .. NETL.hosts[1].ip)
    netlanJoin(NETL.hosts[1].ip)
  end
  if T.role == "host" and T.phase == 1 and NETL.started then
    T.phase = 2; print("[lantest] host: guest connected, skipping intro")
    gState = "CIN_CRASH"; cinT = 0; initCrashEntry()
  end
  if T.role == "host" and T.phase == 2 and gState == "PLAY" then
    T.phase = 3; T.t0 = T.t; anyMoved = true; spawnBoss(); print("[lantest] host in PLAY, boss=" .. boss.name)
  end
  if T.role == "host" and T.phase == 3 then
    if not T.x0 and T.t - T.t0 > 2 then T.x0 = players[2].x end
    if T.t - T.t0 > (T.hold or 9) - 2 and not T.done then
      T.done = true
      print(string.format("[lantest] host: P2 moved %.0f px, remote=%s", players[2].x - (T.x0 or 0), tostring(players[2].remote)))
      love.graphics.captureScreenshot("lan_host.png")
    end
    if T.t - T.t0 > (T.hold or 9) then love.event.quit() end
  end
  if T.role == "guest" and T.phase == 2 and NETL.started and gState == "PLAY" then
    T.phase = 3; T.t0 = T.t; print("[lantest] guest sees PLAY, players=" .. #players)
  end
  if T.role == "guest" and T.phase == 3 then
    local e = T.t - T.t0
    LANTEST_KEYS = (e > 3 and e < 6) and { right = 1, shoot = 1 } or nil
    if e > 6.5 and not T.done then
      T.done = true
      print(string.format("[lantest] guest: P2 at x=%.0f, bullets=%d, boss=%s, map tiles ok=%s",
        players[2] and players[2].x or -1, #pBullets, boss and boss.name or "nil", tostring(map[MH - 1][5] == 1)))
      love.graphics.captureScreenshot("lan_guest.png")
    end
    if e > 8 then love.event.quit() end
  end
  if T.t > (T.limit or 60) then print("[lantest] TIMEOUT phase=" .. T.phase .. " state=" .. gState .. " status=" .. NETL.status); love.event.quit() end
end

return T
