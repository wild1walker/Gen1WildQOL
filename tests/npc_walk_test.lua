-- NPC WALK: one step per tile, not two.
--
-- The bug this holds is an animation, so what it checks is an animation: the
-- walk cycle is rendered a frame per character over three tiles and compared
-- as a string.  `.` is the standing frame, `L` and `R` are the two step
-- frames (the same frame, mirrored), and a tile is however many frames the
-- entity's cell takes.
--
-- The engine is not here, so the two things that decide the picture are stood
-- up from src/world/NPC.lua rather than approximated: the per-frame step
-- advance in NPC:update, and the walkPhase/pose pair the mod replaces.  What
-- is asserted is what those produce once the mod has been installed over them.
--
-- Run:  luajit tests/npc_walk_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  local same = actual == expected
  if not same then
    description = ("%s\n        got  %s\n        want %s")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

-- ------- the engine's NPC, as far as the walk goes
--
-- STEP_FRAMES is thirty-two: an NPC's cell takes twice as long as a player's,
-- which is the Gen 1 speed difference and is not what this mod changes.  The
-- walk cycle being SIXTEEN regardless is.

local STEP_FRAMES = 32

local NPC = {}
NPC.__index = NPC

local function newNPC(stepFrames)
  return setmetatable({
    cellX = 0, cellY = 0, px = 0, py = 0, facing = "right",
    moving = false, progress = 0, animClock = 0, stepFlip = false,
    stepFrames = stepFrames,
  }, NPC)
end

function NPC:update()
  local stepLen = self.stepFrames or STEP_FRAMES
  if not self.moving then return end
  self.progress = self.progress + 1
  self.animClock = (self.animClock or 0) + 1
  local moved = math.floor(self.progress * 16 / stepLen)
  self.px = self.cellX * 16 + moved
  if self.progress >= stepLen then
    self.cellX = self.targetX
    self.targetX = nil
    self.px = self.cellX * 16
    self.moving = false
    self.stepFlip = not self.stepFlip
  end
end

-- engine/overworld/movement.asm:301 -- the sixteen-frame cycle, whatever the
-- cell length is
function NPC:walkPhase()
  if not self.moving then return 0 end
  local p = (self.animClock or 0) % 16
  return (p >= 4 and p < 12) and 1 or 0
end

function NPC:pose()
  local flip = self.stepFlip
  if self.moving then
    flip = math.floor((self.animClock or 0) / 16) % 2 == 1
  end
  return self.sprite, self.px, self.py, self.facing,
         self:walkPhase(), flip, false
end

-- the stack the base walkPhase asks about a text box through
local Game = { stack = { states = {} } }
function Game.stack:top() return self.states[#self.states] end
package.preload["src.core.Game"] = function() return Game end
package.preload["src.world.NPC"] = function() return NPC end

-- ------- the mod host

local defined
local options = {}
local mod = {
  path = ".",
  options = {
    define = function(_, schema)
      defined = schema
      for _, row in ipairs(schema) do
        if options[row.key] == nil then options[row.key] = row.default end
      end
    end,
    get = function(_, key) return options[key] end,
    set = function(_, key, value) options[key] = value end,
  },
  exports = {},
  log = { info = function() end, warn = function(_, f) io.write("WARN " .. tostring(f) .. "\n") end,
          error = function(_, f) io.write("ERROR " .. tostring(f) .. "\n") end },
}

local function chunkOf(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ------- the picture

-- Walk `tiles` cells the way a script does -- one cell at a time, chained
-- back to back with no idle frame between -- and render the result.
local function cadence(npc, tiles)
  local out = {}
  for _ = 1, tiles do
    npc.targetX = npc.cellX + 1
    npc.moving = true
    npc.progress = 0
    local guard = 0
    while npc.moving and guard < 500 do
      guard = guard + 1
      npc:update()
      local _, _, _, _, phase, flip = npc:pose()
      out[#out + 1] = phase == 0 and "." or (flip and "R" or "L")
    end
  end
  return table.concat(out)
end

-- how many separate runs of step frames there are: one per tile is a walk,
-- two per tile is the hop
local function steps(picture)
  local n = 0
  for _ in picture:gmatch("[LR]+") do n = n + 1 end
  return n
end

io.write("as the engine draws it\n")
do
  local npc = newNPC()
  local before = cadence(npc, 3)
  eq(#before, 3 * STEP_FRAMES, "three tiles is three cells of frames")
  eq(steps(before), 6, "the engine takes TWO steps per tile -- the hop")
end

io.write("with NPC WALK installed\n")
chunkOf("modules/QualityOfLife/bundle_npc_walk.lua")(mod)

do
  ok(defined ~= nil and defined[1] and defined[1].key == "qol_npc_walk",
     "the feature defines its own row")
  ok(defined[1].default == true, "...and ships on")

  local npc = newNPC()
  local picture = cadence(npc, 3)
  eq(picture,
     ".......LLLLLLLLLLLLLLLL................RRRRRRRRRRRRRRRR................"
     .. "LLLLLLLLLLLLLLLL.........",
     "one step per tile, and the foot alternates tile by tile")
  eq(steps(picture), 3, "three tiles, three steps")
end

io.write("the escort that was already right is untouched\n")
do
  -- Oak's walk to the lab pins his cell to the player's -- `oak.stepFrames =
  -- ow.player.stepFramesCur`, data/scripts/story2.lua -- so his cell is
  -- sixteen frames and the engine's sixteen-frame cycle already fitted it.
  local oak = newNPC(16)
  eq(cadence(oak, 3),
     "...LLLLLLLL........RRRRRRRR........LLLLLLLL.....",
     "a sixteen-frame escort walks exactly as it always did")
end

io.write("and a sprinting escort stops sliding\n")
do
  -- With SPRINT on, the same pin makes the cell EIGHT frames against a
  -- sixteen-frame cycle: a leg lifted once every two tiles and slid the rest
  -- of the way.  One cycle per cell is one cycle per cell at any speed.
  local guide = newNPC(8)
  local picture = cadence(guide, 4)
  eq(steps(picture), 4, "four tiles, four steps, at double speed")
end

io.write("the row turns it off\n")
do
  options.qol_npc_walk = false
  local npc = newNPC()
  eq(steps(cadence(npc, 3)), 6,
     "OFF is the engine's own cadence back, with no relaunch")
  options.qol_npc_walk = true
  local back = newNPC()
  eq(steps(cadence(back, 3)), 3, "and ON is live the same way")
end

io.write("a text box freezes the walk\n")
do
  local npc = newNPC()
  npc.targetX, npc.moving, npc.progress = 1, true, 0
  for _ = 1, 12 do npc:update() end
  local _, _, _, _, moving = npc:pose()
  ok(moving == 1, "mid-stride, the leg is up")
  Game.stack.states[1] = { isOpaque = true }   -- something that is not the map
  local _, _, _, _, frozen = npc:pose()
  eq(frozen, 0, "with a box up the sprite stands, as UpdateNPCSprite does")
  Game.stack.states[1] = nil
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
