-- A TM is kept when it is used, the way an HM already is.
--
-- ------- what the cartridge does
--
-- `ItemEffects.use` answers a machine with one of two verdicts and the only
-- difference between them is whether the item survives:
--
--     -- HMs are never consumed; TMs are single-use
--     return (itemDef.machine.kind == "HM" and "learnkept" or "learn"), ...
--
-- and `BagMenu` reads that verdict in the one place it teaches a move
-- (BagMenu.lua:224-247): the two share a branch, and `consume` is called
-- inside `if result == "learn"`.  Twice, because a POKeMON with four moves
-- goes through `MoveLearnMenu` first and the TM is only spent if the swap
-- actually happened.
--
-- So the whole of this feature is answering `learnkept` where the engine
-- answered `learn`.  Nothing is re-implemented, no consumption is undone
-- after the fact, and the two call sites that spend a TM are simply never
-- reached -- including the one behind the forget list, which is the one an
-- "undo the removal afterwards" version of this would have got wrong.
--
-- ------- what it does NOT change
--
-- The refusals are all still the engine's: a species that cannot learn the
-- move is still refused with SFX_DENIED, a POKeMON that already knows it is
-- still told so, and neither of those reaches the verdict this touches.  A TM
-- still costs what it costs at Celadon; what changes is that buying a second
-- copy of one stops being a thing you do.
--
-- Gen 1 only.  Gold's item path is `src/ui/gen2/`, which does not go through
-- `src.inventory.ItemEffects` at all, so there is nothing here to wrap on
-- that boot and the feature stands down rather than pretending.
local generation = ...

local feature = {
  games = { "gen1" },
  option = {
    key = "qol_reusable_tms",
    label = "REUSABLE TMS",
    type = "toggle",
    default = true,
  },
  menu = {
    label = "REUSABLE TMS",
    key = "qol_reusable_tms",
    description = "A TM IS KEPT WHEN\nIT IS USED, THE\fWAY AN HM IS.",
  },
}

-- Stashed on the module so a hot reload wraps the ENGINE's own `use` again
-- rather than compounding a wrapper around the previous wrapper.  Same trick
-- the caught indicator uses on `BattleState.dexCaught`.
local VANILLA = "__qolReusableTmsVanilla"

function feature.install(mod, services)
  local ok, ItemEffects = pcall(require, "src.inventory.ItemEffects")
  if not ok or type(ItemEffects) ~= "table"
      or type(ItemEffects.use) ~= "function" then
    mod.log:warn("src.inventory.ItemEffects is not what this build expects; "
      .. "TMs stay single-use")
    return
  end

  local base = rawget(ItemEffects, VANILLA)
  if not base then
    base = ItemEffects.use
    ItemEffects[VANILLA] = base
  end

  local function on()
    return services.options.value(nil, "qol_reusable_tms") and true or false
  end

  -- Written as a tail call through a second function so every value the
  -- engine returned is carried through untouched.  `use` is not a two-value
  -- function: the healing items answer `"consumed", { text }, jingle`, and a
  -- wrapper that named its returns would quietly eat the third and take the
  -- jingle off a POTION.
  local function retune(verdict, ...)
    if verdict == "learn" and on() then return "learnkept", ... end
    return verdict, ...
  end

  ItemEffects.use = function(...)
    return retune(base(...))
  end
end

return feature
