-- Input: keyboard (desktop) + gamepads (handheld / USB pads) mapped to the same actions.
--
--  Action   | Gamepad                    | P1 keyboard        | P2 keyboard
--  left/right | D-pad / left stick       | ← →                | A D
--  up/down  | D-pad / left stick (aim)   | ↑ ↓                | W S
--  jump     | A                          | AltGr / Shift dir. | 1 / Espaço
--  shoot    | B or R2 (hold)             | Ctrl dir.          | Q
--  b1..b4   | X, Y, L1, R1 (shop)        | Z X C V            | G H J K
--  start    | Start                      | Enter              | Enter
--  back     | Select                     | Esc                | Esc
local I = {}

local KEYS = {
  { left = { "left" }, right = { "right" }, up = { "up" }, down = { "down" },
    jump = { "ralt", "rshift" }, shoot = { "rctrl" },
    b1 = { "z" }, b2 = { "x" }, b3 = { "c" }, b4 = { "v" },
    start = { "return", "kpenter" }, back = { "escape" } },
  { left = { "a" }, right = { "d" }, up = { "w" }, down = { "s" },
    jump = { "1", "space" }, shoot = { "q" },
    b1 = { "g" }, b2 = { "h" }, b3 = { "j" }, b4 = { "k" },
    start = { "return", "kpenter" }, back = { "escape" } },
}
local PAD = {
  jump = { "a" }, shoot = { "b" }, b1 = { "x" }, b2 = { "y" }, b3 = { "leftshoulder" }, b4 = { "rightshoulder" },
  start = { "start" }, back = { "back" },
  left = { "dpleft" }, right = { "dpright" }, up = { "dpup" }, down = { "dpdown" },
}
local ACTIONS = { "left", "right", "up", "down", "jump", "shoot", "b1", "b2", "b3", "b4", "start", "back" }

local held = { {}, {} }
local prev = { {}, {} }
I.anyPressed = false

local function padFor(p)
  local js = love.joystick.getJoysticks()
  local pads = {}
  for _, j in ipairs(js) do if j:isGamepad() then pads[#pads + 1] = j end end
  return pads[p]
end

local function axisDir(j, action)
  local dz = .45
  if action == "left" then return j:getGamepadAxis("leftx") < -dz end
  if action == "right" then return j:getGamepadAxis("leftx") > dz end
  if action == "up" then return j:getGamepadAxis("lefty") < -dz end
  if action == "down" then return j:getGamepadAxis("lefty") > dz end
  if action == "shoot" then return j:getGamepadAxis("triggerright") > .5 end
  return false
end

-- Call once per simulation step, before the game update
function I.update()
  I.anyPressed = false
  for p = 1, 2 do
    local j = padFor(p)
    for _, a in ipairs(ACTIONS) do
      prev[p][a] = held[p][a]
      local v = false
      for _, k in ipairs(KEYS[p][a]) do if love.keyboard.isDown(k) then v = true break end end
      if not v and j then
        for _, b in ipairs(PAD[a]) do if j:isGamepadDown(b) then v = true break end end
        if not v then v = axisDir(j, a) end
      end
      held[p][a] = v
      if v and not prev[p][a] then I.anyPressed = true end
    end
  end
end

function I.down(p, a) return held[p][a] == true end
function I.pressed(p, a) return held[p][a] == true and not prev[p][a] end
-- either player
function I.anyDown(a) return I.down(1, a) or I.down(2, a) end
function I.anyPress(a) return I.pressed(1, a) or I.pressed(2, a) end

function I.clear()
  for p = 1, 2 do for _, a in ipairs(ACTIONS) do held[p][a] = false; prev[p][a] = true end end
end

return I
