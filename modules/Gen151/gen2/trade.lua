-- The ten trade evolutions, without a second Game Boy.
--
-- ------- why this is not Gen151's LINK CABLE
--
-- Gen151 sells a consumable cable and evolves one Pokemon per cable.  It
-- gives two reasons, and on Gold only one of them still holds.
--
-- The reason that does NOT survive is the important one.  Gen151 rejects
-- "just let it evolve on level-up" because that evolves every KADABRA the
-- player owns whether they wanted it or not, and B-cancelling out of the
-- animation every level is a bad opt-out.  True in Red.  Not true here: Gen 2
-- ships the EVERSTONE, a permanent, first-class, player-understood opt-out
-- that the cartridge's own evolution code already checks --
--
--     IsMonHoldingEverstone: checked before LEVEL, HAPPINESS, STAT and TRADE
--     src/core/gen2/Evolution.lua:47
--
-- -- so the objection is answered by the game rather than by an item this mod
-- would have to invent, price, and find a shelf for.
--
-- ------- what this actually changes
--
-- One thing.  Gold's trade-evolution rule is already complete:
--
--     if not ctx.link then return false, "not trading" end
--     if Evolution.holdsEverstone(mon) then return false, "everstone" end
--     if entry.item then ... if mon.item ~= entry.item then ... end end
--     src/core/gen2/Evolution.lua:121-133
--
-- Everstone, the held item, the Time Capsule exemption -- all of it is
-- written and all of it is right.  The only clause a single save can never
-- satisfy is the first one.  So this supplies the link and touches nothing
-- else: SCIZOR still costs a METAL COAT, an EVERSTONE still says no, and a
-- POLIWHIRL still becomes POLIWRATH first if you use the WATER STONE,
-- because the row order in the ROM is the tiebreak and this does not reorder
-- anything.
--
-- ------- the one divergence, stated plainly
--
-- The held item is NOT consumed.  In a real trade evolution it is, and the
-- cartridge's own check says so by returning a third value the
-- `evolution.check` hook has no way to pass back (the hook contract is Gen
-- 1's verbatim: four arguments in, ONE boolean out).  Consuming it from here
-- would mean mutating the mon inside what is meant to be a predicate, and a
-- predicate that eats a METAL COAT when something merely ASKS whether a
-- Pokemon would evolve is a much worse bug than a coat that survives.
--
-- So one METAL COAT can make both a SCIZOR and a STEELIX.  That is a real
-- divergence, in the generous direction, and it is here rather than in a
-- release note.

local Trade = {}

local TRADE = "EVOLVE_TRADE"
local EVERSTONE = "EVERSTONE"

-- Whether this row is one a save cannot otherwise reach, and whether the mon
-- in front of us satisfies everything about it except the cable.
--
-- Pure, and separated from the hook for exactly that reason: this is the
-- whole feature, and it is the part worth driving from a test bench.
function Trade.wouldTrade(entry, mon, ctx)
  ctx = ctx or {}
  if type(entry) ~= "table" or entry.method ~= TRADE then return false end
  if not entry.into then return false end

  -- A real link is up: this is a genuine trade, and the cartridge's own path
  -- is already about to handle it correctly.  Standing aside is not an
  -- optimisation, it is the difference between helping and interfering.
  if ctx.link then return false end
  -- A stone is being used on this mon.  wForceEvolution blocks everything but
  -- the ITEM path, and quietly firing a trade evolution off the back of a
  -- FIRE STONE would be a genuine surprise.
  if ctx.force then return false end
  -- The cartridge's own opt-out, and the reason this feature can be a rule
  -- rather than an item.
  if mon and mon.item == EVERSTONE then return false end

  -- The six Gen 2 rows carry a held item; the four inherited from Gen 1 do
  -- not, and for those any trade will do.
  if entry.item then
    -- The Time Capsule cannot carry a held item, which is why the cartridge
    -- refuses an item trade evolution across it.  Nothing here should make
    -- that refusal come out differently.
    if ctx.timeCapsule then return false end
    if not mon or mon.item ~= entry.item then return false end
  end

  return true
end

function Trade.install(mod)
  mod.hooks:wrap("evolution.check", function(next, _data, mon, entry, ctx)
    if Trade.wouldTrade(entry, mon, ctx) then return true end
    return next()
  end)
end

return Trade
