-- An HM move can be forgotten, like any other.
--
-- ------- what the cartridge does
--
-- There is one way to remove a move in Gen 1: teach a fifth one and pick
-- which of the four goes.  `MoveLearnMenu:update` runs that list, and on A it
-- checks the row against `IsMoveHM` before it swaps:
--
--     if HM_MOVES[old.id] then
--       ... "HM techniques\ncan't be deleted!" ...
--       return
--     end
--
-- That is the whole of the lock.  There is no move deleter in this
-- generation, so nothing else has to be reached: the party's move reordering
-- moves slots around and deletes nothing, and Gen1Remember hands its relearn
-- through `Screens.push(game, "MoveLearnMenu", ...)`, so it comes through the
-- same list and the same check.
--
-- ------- and how this reaches inside it
--
-- `HM_MOVES` is a file-local in the engine, so the refusal cannot be switched
-- off from out here -- but it can be arrived at.  The wrapper answers the one
-- frame the engine would have refused: the forget list is up, A is down, and
-- the row under the cursor is an HM.  Everything else -- the cursor, B,
-- the abandon prompt, the whole YES/NO phase before the list -- falls through
-- to the engine untouched.
--
-- The three lines it runs in the engine's place are the engine's own, copied
-- from the branch below the refusal: swap the slot, remember the name for the
-- "forgot" page, and hand back to `finish`, which is the class's and does the
-- "1, 2 and... Poof!" pages, the SFX_SWAP and the callback.  So a forgotten
-- HM move reads exactly like a forgotten anything else, because past the
-- check it IS the same code.
--
-- ------- is this safe to do
--
-- It cannot strand a save.  An HM item is never consumed -- that is the rule
-- this suite's other machine feature is named after -- so the move can be
-- taught again from the same HM to the same POKeMON, or to another one, for
-- as long as the bag holds it.  Forgetting SURF in the middle of the water is
-- a walk back, not a dead end.
--
-- Gen 1 only.  Gold runs its own `src/ui/gen2/ForgetMoveList`, which this
-- does not touch.
local generation = ...

-- data/moves/hm_moves.asm (IsMoveHM), the same five the engine names.  A copy
-- rather than a reach into the engine's local: it is five constants that have
-- not moved since 1996, and the alternative is not being able to ask at all.
local HM_MOVES = {
  CUT = true, FLY = true, SURF = true, STRENGTH = true, FLASH = true,
}

local feature = {
  games = { "gen1" },
  option = {
    key = "qol_forget_hm",
    label = "FORGET HM MOVES",
    type = "toggle",
    default = true,
  },
  menu = {
    label = "FORGET HM MOVES",
    key = "qol_forget_hm",
    description = "AN HM MOVE CAN BE\nREPLACED WHEN A\fPOKeMON LEARNS A\nFIFTH MOVE.",
  },
}

local VANILLA = "__qolForgetHmVanilla"

-- Whether this frame is the one the engine is about to refuse.  Split out so
-- the test can drive it without an engine: it is the whole of the decision,
-- and everything around it is the swap the engine already knew how to do.
function feature.refuses(self, input)
  if type(self) ~= "table" or not self.selecting then return false end
  if not (input and type(input.wasPressed) == "function") then return false end
  if not input:wasPressed("a") then return false end
  local moves = self.mon and self.mon.moves
  local old = moves and moves[self.index]
  return (old and HM_MOVES[old.id]) and true or false
end

function feature.install(mod, services)
  local ok, MoveLearnMenu = pcall(require, "src.ui.MoveLearnMenu")
  if not ok or type(MoveLearnMenu) ~= "table"
      or type(MoveLearnMenu.update) ~= "function" then
    mod.log:warn("src.ui.MoveLearnMenu is not what this build expects; HM "
      .. "moves keep their lock")
    return
  end

  local base = rawget(MoveLearnMenu, VANILLA)
  if not base then
    base = MoveLearnMenu.update
    MoveLearnMenu[VANILLA] = base
  end

  MoveLearnMenu.update = function(self, dt)
    if not services.options.value(self and self.game, "qol_forget_hm") then
      return base(self, dt)
    end
    local input = self.game and self.game.input
    if not feature.refuses(self, input) then return base(self, dt) end

    -- the engine's own swap, from the branch under the refusal
    local old = self.mon.moves[self.index]
    local mdef = self.game.data.moves[self.newMoveId]
    self.mon.moves[self.index] = { id = self.newMoveId, pp = mdef.pp }
    self.forgot = self.game.data.moves[old.id].name
    self:finish(true)
  end
end

return feature
