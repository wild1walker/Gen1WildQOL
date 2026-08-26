-- Rarity tiers (SPEC 5).
--
-- One table, used everywhere, so retuning is a single edit and the mod option
-- can scale the whole ladder without touching a placement.
--
-- ---------------------------------------------------------------- the rule
--
-- Every tier is anchored to a share the cartridge itself charges.  Gen 1
-- picks a wild slot from ten cumulative buckets out of 256
-- (engine/battle/wild_encounters.asm), whose widths are:
--
--     51  51  39  25  25  25  13  13  11  3
--
-- So the RAREST thing vanilla ever asks a player to find is a tenth-slot
-- species at 3/256 -- 1.17% of that map's encounters, about 85 encounters to
-- meet one.  Nothing on the cartridge is rarer than that, and so nothing here
-- is either.  A mod whose whole premise is "the vanilla encounter keeps its
-- exact vanilla behaviour" has no business charging more for its own
-- additions than the game charges for its own.
--
-- The first cut did.  VERY_RARE was 0.4% -- three and a half times rarer than
-- anything in the game -- which worked out at ~250 encounters and, on a
-- low-rate map like Viridian Forest, five and a half thousand steps for one
-- Bulbasaur.  For a STARTER: the thing a player most wants was the most
-- expensive thing in the mod.  The tell was that the RARITY % option could
-- fix it by hand (300% put VERY_RARE back on vanilla's floor), which is the
-- escape hatch doing the work the default should have been doing.
--
-- ------------------------------------------------------------ the second rule
--
-- A tier is a share of ENCOUNTERS, but a player spends STEPS, and the two
-- come apart on a quiet map: 0.4% of an 8/256 route costs nearly twice what
-- 0.4% of a 15/256 route costs.  Same word on the tin, twice the hunt.  So
-- the share is not the target any more -- the HUNT is, and build.lua solves
-- for the share that makes the hunt the same length wherever the placement
-- lands.  See Rarity.medianSteps and Rarity.shareForSteps below.

local Rarity = {}

-- The cartridge's own bucket widths, out of 256.  Kept here rather than
-- inlined so the anchors below can be read against them.
Rarity.SLOT_WIDTHS = { 51, 51, 39, 25, 25, 25, 13, 13, 11, 3 }

-- Vanilla's rarity floor: the tenth slot.  Nothing in this table goes below
-- it, and the clamp in Rarity.weight enforces that.
Rarity.FLOOR = 3 / 256

-- Parts per Roll.RARITY_SCALE (10000) of the encounters on that map.  The
-- encounter RATE is never touched, so these change what jumps the player,
-- never how often.
Rarity.TIERS = {
  -- version exclusives, in their natural habitat.  The ninth slot, 11/256:
  -- the species reads as a resident of the route, not as a prize.
  UNCOMMON = 430,   -- 4.30%, vanilla's ninth slot
  -- one-time gift mons and NPC-trade mons.  Between the ninth slot and the
  -- tenth: findable in an afternoon, never on the way past.
  RARE = 250,       -- 2.50%
  -- starters, fossils, and anything the vanilla game treated as unique.
  -- Vanilla's rarest slot exactly -- the most the cartridge ever asks, and
  -- therefore the most this mod is willing to ask.
  VERY_RARE = 117,  -- 1.17%, vanilla's tenth slot
}

Rarity.ORDER = { "UNCOMMON", "RARE", "VERY_RARE" }

Rarity.LABELS = {
  UNCOMMON = "uncommon",
  RARE = "rare",
  VERY_RARE = "very rare",
}

-- The reference map rate the tiers above are quoted at: 25/256, the rate
-- most Kanto grass runs at.  The hunt each tier is worth is computed from
-- its share AT THIS RATE, and then build.lua re-solves the share for
-- whatever rate the destination map actually has.
Rarity.REFERENCE_RATE = 25

-- Median steps to meet a species that is `share` of the encounters on a map
-- whose encounter rate is `rate`/256.  Median rather than mean because the
-- mean of a geometric distribution is the tail talking: half of all players
-- find it faster than this, which is the number a person actually feels.
function Rarity.medianSteps(share, rate)
  if not share or share <= 0 or not rate or rate <= 0 then return nil end
  local encounters = math.log(0.5) / math.log(1 - share)
  return encounters * 256 / rate
end

-- The inverse: the share that makes the hunt `steps` long on a map whose
-- rate is `rate`/256.  This is what makes a tier mean the same thing
-- everywhere -- on a quiet map the share goes UP, because the player is
-- meeting fewer things per step and the tier is a promise about time.
function Rarity.shareForSteps(steps, rate)
  if not steps or steps <= 0 or not rate or rate <= 0 then return nil end
  local encounters = steps * rate / 256
  if encounters < 1 then encounters = 1 end
  return 1 - 0.5 ^ (1 / encounters)
end

-- The hunt a tier is worth, in steps, at the reference rate.
function Rarity.steps(tier)
  local base = Rarity.TIERS[tier]
  if not base then return nil end
  return Rarity.medianSteps(base / 10000, Rarity.REFERENCE_RATE)
end

-- The mod option is a percentage multiplier: 100 leaves the table alone, 300
-- triples every tier, 25 quarters it.
--
-- Two clamps.  The ceiling stops a scaled tier reaching half a map's
-- encounters -- a placement that displaced every vanilla species would break
-- prime directive 1 by the back door.  The floor is only applied at the
-- default multiplier: a player who deliberately turns RARITY % down is
-- asking for a longer hunt and is allowed to have one, but the SHIPPED table
-- may never sit below what the cartridge itself charges.
function Rarity.weight(tier, multiplierPercent)
  local base = Rarity.TIERS[tier]
  if not base then return nil end
  local percent = multiplierPercent or 100
  local scaled = math.floor(base * percent / 100 + 0.5)
  if percent >= 100 then
    local floor = math.floor(Rarity.FLOOR * 10000 + 0.5)
    if scaled < floor then scaled = floor end
  end
  if scaled < 0 then return 0 end
  if scaled > 5000 then return 5000 end
  return scaled
end

-- ------------------------------------------------------------- the ceilings
--
-- Equalising the hunt has a failure mode at the quiet end of the map list.
-- Route 20's surf rate is 5/256: to make a RARE cost its 280 steps there, the
-- solve wants Lapras to be nearly 12% of what the player meets.  The arithmetic
-- is right -- you surf for 280 steps and get a coin flip -- but 1 encounter in
-- 8 does not read as "rare", it reads as "Lapras lives here", and the mod has
-- then rewritten what that route IS rather than added to it.
--
-- So two ceilings, both stated as shares the cartridge itself justifies:
--
--   * no single placement may be a bigger share of a map than vanilla's NINTH
--     slot, 11/256.  Nothing this mod adds is ever more of a map than the
--     second-rarest thing the cartridge put there.
--   * no map may give away more than a quarter of its encounters in total.
--     Three encounters in four stay vanilla everywhere, so a map still reads
--     as itself.
--
-- Where a ceiling bites, the hunt gets longer than the tier's target and that
-- is the correct trade: a promise about time is worth less than a route that
-- still feels like the route.
Rarity.ROW_CEILING = 430    -- 11/256, vanilla's ninth slot
Rarity.MAP_CEILING = 2500   -- a quarter of a map's encounters

-- One ceiling shared by every tier flattened the ladder, though, and the
-- breakdown is what caught it.  On a 10/256 map the solve wants 10.4% for an
-- UNCOMMON and 6.2% for a RARE; a single 4.30% cap clamped both to the same
-- number, so MAGMAR and HITMONCHAN came out at 1 in 23 with the same 412-step
-- hunt.  Two different words on the tin, one thing behind it.  Below about
-- 15/256 the two tiers had stopped being distinguishable at all.
--
-- So the ceiling is a ladder too: each tier's is the geometric mean of the
-- absolute ceiling and that tier's own flat share -- halfway between them in
-- ratio terms.  That keeps three properties at once:
--
--   * UNCOMMON's ceiling is still exactly vanilla's ninth slot, so the
--     absolute bound on any placement has not moved;
--   * every tier's ceiling is strictly below the one above it, so the
--     ordering holds on EVERY map rate rather than only on busy ones;
--   * every tier's ceiling is still well above its own flat share, so a quiet
--     map can still lift the share and shorten the walk, which was the whole
--     point of solving per rate.
--
--   UNCOMMON  sqrt(430 x 430) = 430   (4.30%)
--   RARE      sqrt(430 x 250) = 328   (3.28%)
--   VERY_RARE sqrt(430 x 117) = 224   (2.24%)
function Rarity.ceilingFor(tier)
  local flat = Rarity.TIERS[tier]
  if not flat then return nil end
  return math.floor(math.sqrt(Rarity.ROW_CEILING * flat) + 0.5)
end

-- The same, re-solved for a destination map's own encounter rate, so a tier
-- costs the same hunt wherever it lands.  Falls back to the flat share when
-- the rate is unknown -- a Super Rod row has no map rate to speak of, since
-- the rod's own bite roll is what gates it.
-- Returns the weight and, second, whether a ceiling held it back -- because
-- a capped row's hunt is legitimately longer than its tier's target and
-- anything checking that the tiers hold has to be able to tell the two apart.
function Rarity.weightForRate(tier, multiplierPercent, rate)
  local flat = Rarity.weight(tier, multiplierPercent)
  if not flat or not rate or rate <= 0 or rate == Rarity.REFERENCE_RATE then
    return flat, false
  end
  local steps = Rarity.medianSteps(flat / 10000, Rarity.REFERENCE_RATE)
  local share = steps and Rarity.shareForSteps(steps, rate)
  if not share then return flat, false end
  local scaled = math.floor(share * 10000 + 0.5)
  -- the ceiling never fights the player's own multiplier: a tier already
  -- scaled past it by RARITY % keeps what the player asked for, and only the
  -- rate solve is held back
  local ceiling = math.max(Rarity.ceilingFor(tier) or Rarity.ROW_CEILING, flat)
  local capped = scaled > ceiling
  if capped then scaled = ceiling end
  if scaled < 1 then scaled = 1 end
  if scaled > 5000 then scaled = 5000 end
  return scaled, capped
end

return Rarity
