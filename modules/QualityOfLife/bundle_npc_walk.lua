-- NPC WALK -- one step per tile, not two.
--
-- ------- what it looks like
--
-- An NPC who walks you somewhere -- an escort, a rival leaving after a fight,
-- a guide taking you through a gate -- moves its legs twice as fast as it
-- covers ground.  Beside a walking player that does not read as walking at
-- all; it reads as a hop, or a scurry on the spot.  Which is what it is: the
-- legs are keeping the PLAYER's cadence while the body moves at half the
-- player's speed.
--
-- ------- where it comes from
--
-- Two constants that were the same number for one entity and not for the
-- other.  A player's cell takes sixteen frames (src/world/Player.lua
-- STEP_FRAMES) and its walk cycle is sixteen frames long (Player:walkPhase,
-- `animClock % 16`), so a player takes exactly one step per tile and the foot
-- alternates tile by tile.  An NPC's cell takes THIRTY-TWO frames
-- (src/world/NPC.lua STEP_FRAMES -- NPCs move at half the player's speed in
-- Gen 1) and its walk cycle is the same sixteen (NPC:walkPhase, the same
-- `% 16`).  Two cycles per tile.
--
-- Drawn out, a frame per character, over three tiles -- `.` is the standing
-- frame, `L` and `R` are the two step frames, `|` is a tile boundary:
--
--   player   ...LLLLLLLL........RRRRRRRR........LLLLLLLL.....
--                           |               |               |
--
--   NPC      ...LLLLLLLL........RRRRRRRR........LLLLLLLL........RRRR...
--                                          |                           |
--
-- Same cadence, half the distance.
--
-- ------- what this does
--
-- Ties the cycle to the step instead of to a constant: whatever an entity's
-- own cell length is, one walk cycle fits in it.  The step frame occupies the
-- middle half of the tile the way it always did, and the foot alternates once
-- per tile, from the engine's own stepFlip -- which is already exactly "how
-- many steps has this NPC taken", already toggled once per completed step,
-- and already what NPC:pose uses the moment the NPC stops.
--
--   NPC      .......LLLLLLLLLLLLLLLL................RRRRRRRRRRRRRRRR....
--                                          |                           |
--
-- The one escort that was already right stays byte for byte right.  Oak's
-- walk to the lab pins his step to the player's -- `oak.stepFrames =
-- ow.player.stepFramesCur` (data/scripts/story2.lua) -- so his cell is
-- sixteen frames, his cycle is sixteen frames, and the rule above is the rule
-- he was already following.  Held by the suite.
--
-- It also fixes the other end of the same mismatch: with SPRINT on, a pinned
-- escort's cell is EIGHT frames against a sixteen-frame cycle, so the escort
-- lifted a leg once every two tiles and slid the rest of the way.  One cycle
-- per cell is one cycle per cell at any speed.
--
-- ------- what it does not touch
--
-- The player: Player:pose derives its flip from a fixed-rate clock on purpose,
-- so a bicycle covers more ground per stride rather than animating at double
-- speed, and that is a different question from this one.
--
-- The follower: PikachuFollower writes its own `walkPhase` onto the follower
-- instance (src/world/PikachuFollower.lua makeFollower), and an instance field
-- shadows the class method, so its idle poses keep working untouched.
--
-- Marching in place (NPC_CHANGE_FACING -- Oak on the lab doormat) runs through
-- the same `progress` counter over the same cell length, so it gets the same
-- single cycle rather than two.

local PATCH_KEY = "__gen1wildNpcWalk"

local schema = {
  {
    key = "qol_npc_walk",
    label = "NPC WALK",
    type = "toggle",
    default = true,
    help = "NPCs take one step per tile instead of two, so an escort walks "
        .. "instead of hopping.",
  },
}

-- The engine's own NPC cell length, for an NPC that has not been given one.
-- Read off the module where it is reachable and defaulted where it is not,
-- rather than assumed: a total conversion may ship a different number, and
-- this rule is "one cycle per cell" at whatever that number is.
local DEFAULT_STEP_FRAMES = 32

-- UpdateNPCSprite branches to NotYetMoving while BIT_FONT_LOADED is set
-- (engine/overworld/movement.asm:139) -- the same test src/world/NPC.lua
-- makes, and the reason an NPC freezes mid-stride while somebody talks.
local function textBoxUp()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or type(Game) ~= "table" then return false end
  local stack = Game.stack
  local top = stack and stack.top and stack:top()
  return top ~= nil and not top.isOverworld
end

local function cellFrames(npc)
  local frames = tonumber(npc.stepFrames)
  if not frames or frames < 2 then return DEFAULT_STEP_FRAMES end
  return frames
end

-- The step frame occupies the middle half of the cell, which is what the
-- engine's own `p >= 4 and p < 12` out of sixteen says.
local function phaseFor(npc)
  local cycle = cellFrames(npc)
  local p = (npc.progress or 0) % cycle
  return (p >= cycle / 4 and p < cycle * 3 / 4) and 1 or 0
end

return function(mod)
  mod.options:define(schema)

  local function enabled()
    local ok, value = pcall(function() return mod.options:get("qol_npc_walk") end)
    if not ok or value == nil then return true end
    return value ~= false
  end

  local okNPC, NPC = pcall(require, "src.world.NPC")
  if not okNPC or type(NPC) ~= "table" then
    mod.log:warn("no src.world.NPC to patch; NPC WALK stands down")
    return
  end

  -- Idempotent: a hot reload runs this file again, and wrapping a wrap would
  -- put the engine's own cadence back underneath ours for good.
  if NPC[PATCH_KEY] then return end
  NPC[PATCH_KEY] = true

  local basePhase, basePose = NPC.walkPhase, NPC.pose
  if type(basePhase) ~= "function" or type(basePose) ~= "function" then
    mod.log:warn("src.world.NPC has no walkPhase/pose; NPC WALK stands down")
    return
  end

  -- Both are replaced rather than one, because they disagree about the same
  -- thing: pose derives the mirrored foot from the animation clock while
  -- moving and from stepFlip while standing, so at the end of every step the
  -- sprite could mirror on the spot.  One source for both.
  function NPC:walkPhase()
    if not enabled() then return basePhase(self) end
    -- the engine's own two reasons not to animate at all, restated rather
    -- than asked for: the base method answers 0 both for "standing" and for
    -- "mid-cycle on the standing frame", and those are not the same answer.
    if not self.moving or textBoxUp() then return 0 end
    return phaseFor(self)
  end

  function NPC:pose()
    local sprite, px, py, facing, phase, flip, hopping = basePose(self)
    if not enabled() then return sprite, px, py, facing, phase, flip, hopping end
    -- one foot per tile: stepFlip is the engine's own count of completed
    -- steps, and is what pose already uses the moment this NPC stops
    return sprite, px, py, facing, phase, self.stepFlip, hopping
  end

  mod.exports.npcWalkPhase = phaseFor
  mod.exports.npcCellFrames = cellFrames
end
