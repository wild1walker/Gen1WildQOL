-- The Gen 2 spawn layer: renewability, bands, rows and the roll.
--
-- Two properties here are load-bearing and neither is obvious from reading
-- the code:
--
--   * a map with no rows, or whose rows all weigh zero, draws NO random
--     numbers.  If that ever stops being true the mod moves every encounter
--     on every map in the game by one step of the stream, on a cartridge
--     where nothing was supposed to change.
--   * the renewability closure runs DOWN through the Day-Care as well as up
--     through evolution.  Without it the mod places six babies the game
--     already hands out, and with it wrong it could place a legendary's
--     pre-evolution, which does not exist.
--
-- Run:  luajit tests/gen251_test.lua

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
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

local function load_(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local Build = load_("modules/Gen151/gen2/build.lua")
local Roll = load_("modules/Gen151/gen2/roll.lua")
local P = load_("modules/Gen151/gen2/placements.lua")

-- A Gold-shaped encounter table set, small enough to reason about.
local function tables()
  return {
    grass = {
      ROUTE_29 = {
        rates = { MORN = 30, DAY = 30, NITE = 30 },
        slots = {
          MORN = { { level = 2, species = "PIDGEY" },
                   { level = 3, species = "SENTRET" } },
          DAY  = { { level = 2, species = "PIDGEY" },
                   { level = 4, species = "SENTRET" } },
          NITE = { { level = 3, species = "HOOTHOOT" },
                   { level = 5, species = "RATTATA" } },
        },
      },
      ROUTE_36 = {
        rates = { MORN = 20, DAY = 20, NITE = 20 },
        slots = {
          MORN = { { level = 10, species = "GROWLITHE" } },
          DAY  = { { level = 12, species = "GROWLITHE" } },
          NITE = { { level = 14, species = "HOOTHOOT" } },
        },
      },
    },
    water = {
      ROUTE_32 = { rate = 4, slots = { { level = 20, species = "TENTACOOL" },
                                       { level = 25, species = "QUAGSIRE" } } },
    },
    fishGroups = {
      SHORE = { chance = 128,
                old = { { chance = 70, level = 10, species = "MAGIKARP" } },
                good = {}, super = {} },
    },
    trees = { ROUTE_29 = "FOREST" },
    treeSets = {
      FOREST = { common = { { chance = 50, level = 15, species = "EXEGGCUTE" } } },
      DEAD = { common = { { chance = 50, level = 15, species = "MEWTWO" } } },
    },
    bugContest = { { species = "CATERPIE", min = 7, max = 18, chance = 20 } },
  }
end

local POKEMON = {
  PIKACHU = { eggGroups = { "EGG_GROUND", "EGG_FAIRY" },
              evolutions = { { method = "EVOLVE_ITEM", into = "RAICHU" } } },
  PICHU = { eggGroups = { "EGG_NONE" },
            evolutions = { { method = "EVOLVE_HAPPINESS", into = "PIKACHU" } } },
  RAICHU = { eggGroups = { "EGG_GROUND", "EGG_FAIRY" }, evolutions = {} },
  KADABRA = { eggGroups = { "EGG_HUMANSHAPE" },
              evolutions = { { method = "EVOLVE_TRADE", into = "ALAKAZAM" } } },
  ALAKAZAM = { eggGroups = { "EGG_HUMANSHAPE" }, evolutions = {} },
  ARTICUNO = { eggGroups = { "EGG_NONE" }, evolutions = {} },
  GROWLITHE = { eggGroups = { "EGG_GROUND" },
                evolutions = { { method = "EVOLVE_ITEM", into = "ARCANINE" } } },
  ARCANINE = { eggGroups = { "EGG_GROUND" }, evolutions = {} },
  SENTRET = { eggGroups = { "EGG_GROUND" }, evolutions = {} },
  PIDGEY = { eggGroups = { "EGG_FLYING" }, evolutions = {} },
  HOOTHOOT = { eggGroups = { "EGG_FLYING" }, evolutions = {} },
  RATTATA = { eggGroups = { "EGG_GROUND" }, evolutions = {} },
  MAGIKARP = { eggGroups = { "EGG_WATER_2" }, evolutions = {} },
  TENTACOOL = { eggGroups = { "EGG_WATER_3" }, evolutions = {} },
  QUAGSIRE = { eggGroups = { "EGG_WATER_1" }, evolutions = {} },
  EXEGGCUTE = { eggGroups = { "EGG_PLANT" }, evolutions = {} },
  CATERPIE = { eggGroups = { "EGG_BUG" }, evolutions = {} },
  MEWTWO = { eggGroups = { "EGG_NONE" }, evolutions = {} },
}

-- ------------------------------------------------------- what counts

do
  io.write("what counts as renewable\n")

  local have = Build.renewable(tables(), POKEMON)

  ok(have.PIDGEY, "a grass slot counts")
  ok(have.HOOTHOOT, "including one that only appears at night")
  ok(have.TENTACOOL, "a water slot counts")
  ok(have.MAGIKARP, "and so does a rod")
  ok(have.EXEGGCUTE, "a headbutt tree counts, on a set a map points at")
  ok(have.CATERPIE, "and the Bug-Catching Contest counts: it comes round again")

  eq(have.MEWTWO, nil,
     "a tree set NOTHING points at does not count -- dead data in the ROM "
     .. "would otherwise credit the player with a Pokemon no tree can produce")

  ok(have.ARCANINE,
     "the closure runs UP: GROWLITHE is in the grass, so ARCANINE is reachable")
  eq(have.ALAKAZAM, nil,
     "but never across a trade: KADABRA is not here, and even if it were, a "
     .. "trade evolution is the one thing one save cannot reach")
end

-- ------------------------------------------------ the Day-Care direction

do
  io.write("the closure runs down as well as up\n")

  local have = Build.close({ PIKACHU = true }, POKEMON)
  ok(have.PICHU,
     "a renewable PIKACHU makes PICHU renewable, because the engine "
     .. "implements the Day-Care -- this is what keeps six babies out of the "
     .. "placement table")
  ok(have.RAICHU, "and RAICHU is still reachable upward")

  -- The bar on the down step: a parent that lays nothing cannot walk its
  -- pre-evolution into the set.
  local barred = Build.close({ ARTICUNO = true }, {
    ARTICUNO = { eggGroups = { "EGG_NONE" }, evolutions = {} },
    FAKEBABY = { eggGroups = { "EGG_NONE" },
                 evolutions = { { method = "EVOLVE_LEVEL", into = "ARTICUNO" } } },
  })
  eq(barred.FAKEBABY, nil,
     "a species in no egg group breeds nothing, so nothing walks down "
     .. "through it")

  eq(Build.breedable({ eggGroups = { "EGG_DITTO" } }), false,
     "DITTO is a parent but never a mother: it breeds as the OTHER parent's "
     .. "species, which the caller already had")
  eq(Build.breedable({ eggGroups = {} }), false, "no egg groups, no eggs")
  eq(Build.breedable(nil), false, "and no species at all is not breedable")
end

-- ------------------------------------------------------------- the bands

do
  io.write("bands come off the destination map\n")

  local t = tables()
  local levels = Build.levels(t, "ROUTE_29", "grass")
  eq(table.concat(levels, ","), "2,3,4,5",
     "grass reads all three times of day, so a row placed on the day band "
     .. "does not read wrong after dark")

  eq(table.concat(Build.levels(t, "ROUTE_32", "water"), ","), "20,25",
     "water reads its one table")
  eq(#Build.levels(t, "NOWHERE", "grass"), 0,
     "a map with no table has no band, which is how a bad row is caught")

  eq(table.concat(Build.band({ 5, 10, 15 }, "low"), ","), "5",
     "low is the bottom third")
  eq(table.concat(Build.band({ 5, 10, 15 }, "high"), ","), "15",
     "high is the top third")
  eq(table.concat(Build.band({ 4, 5 }, "mid"), ","), "4,5",
     "a map with fewer than three levels has no meaningful middle, so every "
     .. "band gets the short list rather than two of them getting nothing")
end

-- -------------------------------------------------------------- the rows

do
  io.write("which placements apply\n")

  local TIERS = { UNCOMMON = 430, RARE = 250, VERY_RARE = 117 }
  local placements = {
    MAP_GATES = { ROUTE_36 = "CUT" },
    common = {
      -- already in the grass on this cartridge
      { species = "GROWLITHE", map = "ROUTE_36", method = "grass",
        band = "mid", tier = "UNCOMMON", feature = "exclusives", why = "x" },
      -- not here, and its destination has a table
      { species = "VULPIX", map = "ROUTE_36", method = "grass", band = "mid",
        tier = "UNCOMMON", feature = "exclusives", why = "x" },
      -- destination has no table on this cartridge
      { species = "SKARMORY", map = "ROUTE_45", method = "grass", band = "mid",
        tier = "UNCOMMON", feature = "exclusives", why = "x" },
      -- scoped to the other lineage
      { species = "CELEBI", map = "ROUTE_29", method = "grass", band = "high",
        tier = "VERY_RARE", feature = "gifts", lineage = "gs", why = "x" },
    },
  }

  local out = Build.rows(placements, tables(), POKEMON,
                         { tiers = TIERS, lineage = "crystal" })

  local applied = {}
  for _, row in ipairs(out.rows) do applied[row.species] = row end
  eq(applied.GROWLITHE, nil,
     "a species already in this cartridge's grass is left alone -- which is "
     .. "the version detection that never had to be written")
  ok(applied.VULPIX, "and one that is not gets its row")
  eq(applied.VULPIX and applied.VULPIX.weight, 430, "at its tier's weight")
  eq(applied.VULPIX and applied.VULPIX.gate, "CUT",
     "carrying the gate its map sits behind, for the hint text")
  eq(applied.CELEBI, nil, "a row scoped to the other lineage does not apply")

  local unplaced = {}
  for _, row in ipairs(out.unplaced) do unplaced[row.species] = row.why end
  eq(unplaced.SKARMORY, "no table on this cartridge",
     "a row whose map has no table is REPORTED, not swallowed: that is a bug "
     .. "in the table rather than a fact about the save")

  -- The real table, against a real-shaped cartridge, must not report holes
  -- for a reason other than the fixture being small.
  ok(#P.common > 0, "the shipped table is loadable from here too")
end

-- --------------------------------------------------------------- the roll

do
  io.write("the roll\n")

  local vanillaCalls, draws = 0, 0
  local function vanilla(_, _)
    vanillaCalls = vanillaCalls + 1
    return { species = "PIDGEY", level = 3, slot = 2 }
  end
  local function rng()
    draws = draws + 1
    return 0
  end

  -- A map with no rows at all.
  local roll = Roll.new()
  local enc = roll:roll(vanilla, {}, { mapId = "ROUTE_29", terrain = "grass" },
                        rng)
  eq(enc.species, "PIDGEY", "an untouched map returns the cartridge's own roll")
  eq(draws, 0,
     "and draws NOTHING: the RNG stream is identical to a clean install, "
     .. "draw for draw, which is the whole promise")

  -- A map whose rows all weigh zero.
  roll:add("ROUTE_29", "grass",
           { species = "VULPIX", levels = { 5 }, weight = 0 })
  draws = 0
  enc = roll:roll(vanilla, {}, { mapId = "ROUTE_29", terrain = "grass" }, rng)
  eq(enc.species, "PIDGEY", "a zero-weight row substitutes nothing")
  eq(draws, 0, "and still draws nothing")

  -- A row that can win.
  roll:add("ROUTE_29", "grass",
           { species = "VULPIX", levels = { 6, 7 }, weight = 10000 })
  draws = 0
  enc = roll:roll(vanilla, {}, { mapId = "ROUTE_29", terrain = "grass" }, rng)
  eq(enc.species, "VULPIX", "a row that owns the whole scale always wins")
  eq(enc.level, 6, "and takes its level from the same draw, not a second one")
  eq(draws, 1, "exactly one draw is spent")
  eq(enc.slot, 2,
     "the cartridge's own encounter is EDITED, not replaced: the slot index "
     .. "it landed on survives for whatever else is listening")

  -- An inactive row is not in the sum.
  local gated = Roll.new()
  local open = false
  gated:add("ROUTE_29", "grass", { species = "MEW", levels = { 5 },
                                   weight = 10000,
                                   active = function() return open end })
  draws = 0
  enc = gated:roll(vanilla, {}, { mapId = "ROUTE_29", terrain = "grass" }, rng)
  eq(enc.species, "PIDGEY", "a gated row that is shut substitutes nothing")
  eq(draws, 0, "and costs no draw while it is shut")
  open = true
  enc = gated:roll(vanilla, {}, { mapId = "ROUTE_29", terrain = "grass" }, rng)
  eq(enc.species, "MEW", "and takes over once it opens")

  -- Terrain keeps its own list.
  eq(gated:rows("ROUTE_29", "water"), nil, "water is a separate bucket")
  ok(gated:rows("ROUTE_29", "grass"), "grass is the one that was filled")
  ok(gated:rows("ROUTE_29", "cave") == gated:rows("ROUTE_29", "grass"),
     "and a cave reads the grass table, exactly as it does on the cartridge")

  -- No encounter from the cartridge means no substitution.
  eq(roll:roll(function() return nil end, {},
               { mapId = "ROUTE_29", terrain = "grass" }, rng), nil,
     "no vanilla encounter, no substitute: the mod adds encounters to the "
     .. "roll, it does not add rolls")
end

-- ------------------------------------------------- the trade evolutions

do
  io.write("the ten trade evolutions\n")

  local Trade = load_("modules/Gen151/gen2/trade.lua")
  local function would(entry, mon, ctx) return Trade.wouldTrade(entry, mon, ctx) end

  local KADABRA = { method = "EVOLVE_TRADE", into = "ALAKAZAM" }
  local SCYTHER = { method = "EVOLVE_TRADE", into = "SCIZOR",
                    item = "METAL_COAT" }

  eq(would(KADABRA, {}, {}), true,
     "one of the four inherited from Gen 1 needs nothing but the cable")
  eq(would(SCYTHER, { item = "METAL_COAT" }, {}), true,
     "and one of the six Gen 2 rows still costs its held item")
  eq(would(SCYTHER, {}, {}), false, "without the item it does not fire")
  eq(would(SCYTHER, { item = "KINGS_ROCK" }, {}), false,
     "nor with the wrong one")

  eq(would(KADABRA, { item = "EVERSTONE" }, {}), false,
     "the EVERSTONE says no, which is the whole reason this can be a rule "
     .. "rather than an item: Gen 2 ships the opt-out Gen151 had to invent "
     .. "a consumable to avoid needing")

  eq(would(KADABRA, {}, { link = true }), false,
     "a real link is left entirely alone -- the cartridge's own path is "
     .. "already about to do this correctly, and standing aside is the "
     .. "difference between helping and interfering")
  eq(would(KADABRA, {}, { force = true }), false,
     "and a stone being used on the mon does not quietly trip a trade "
     .. "evolution off the back of it")
  eq(would(SCYTHER, { item = "METAL_COAT" }, { timeCapsule = true }), false,
     "the Time Capsule cannot carry a held item, so an item trade evolution "
     .. "across it stays refused exactly as the cartridge refuses it")

  eq(would({ method = "EVOLVE_LEVEL", into = "IVYSAUR", level = 16 }, {}, {}),
     false, "a level row is not this feature's business")
  eq(would({ method = "EVOLVE_TRADE" }, {}, {}), false,
     "and a row with nothing to evolve into is not a row")
  eq(would(nil, {}, {}), false, "no row at all is handled, not raised")
  ok(pcall(would, KADABRA, nil, nil),
     "a missing mon and a missing trigger do not raise")
end

-- ------------------------------------------------------------ the statics

do
  io.write("the statics that stay until they are caught\n")

  local Statics = load_("modules/Gen151/gen2/statics.lua")

  -- Gen 2 spells it `caught`; Gen 1 spells it `owned`.  Reading the Gen 1
  -- name would return nil for every species, and nil is indistinguishable
  -- from "not caught" -- so every static would be restored forever, for a
  -- player already holding the Pokemon.
  eq(Statics.owns({ pokedex = { caught = { LUGIA = true } } }, "LUGIA"), true,
     "ownership is read off pokedex.caught, which is what Gen 2 writes")
  eq(Statics.owns({ pokedex = { owned = { LUGIA = true } } }, "LUGIA"), false,
     "and NOT off pokedex.owned, which is the Gen 1 name and is always nil "
     .. "here")
  eq(Statics.owns(nil, "LUGIA"), false, "no save owns nothing")

  local empty = { pokedex = { caught = {} } }
  ok(Statics.wants(empty, "VERMILION_CITY"),
     "a map whose static is uncaught wants it back")
  eq(Statics.wants(empty, "VERMILION_CITY").species, "SNORLAX", "the right one")
  eq(Statics.wants({ pokedex = { caught = { SNORLAX = true } } },
                   "VERMILION_CITY"), nil,
     "a player who caught it keeps the cartridge's behaviour exactly")
  eq(Statics.wants(empty, "ROUTE_29"), nil, "a map with no static wants nothing")

  -- SUDOWOODO is restored, and the reason the file once gave for excluding
  -- it was wrong: `variablesprite` swaps the SHEET and nothing else, so the
  -- object keeps SudowoodoScript, and that script reads the SQUIRTBOTTLE
  -- rather than EVENT_FOUGHT_SUDOWOODO.
  ok(Statics.ROSTER.SUDOWOODO, "SUDOWOODO is restored like the rest")
  eq(Statics.ROSTER.SUDOWOODO.spriteSlot, 4,
     "with its sprite slot put back too, so the tree is a tree again rather "
     .. "than the TWIN the script left standing there")
  eq(Statics.wants({ pokedex = { caught = {} } }, "ROUTE_36").species,
     "SUDOWOODO", "and Route 36 knows to ask for it")

  -- SUICUNE is the one that really cannot be un-hidden: its object script is
  -- the generic ObjectEvent, and the scene that battles it is behind
  -- EVENT_GOT_RAINBOW_WING.  It gets the roamers instead.
  eq(Statics.ROSTER.SUICUNE, nil,
     "SUICUNE is not un-hidden: its object does nothing when talked to, and "
     .. "the scene that battles it cannot run again once the player has the "
     .. "RAINBOW WING")
end

-- ------------------------------------------------------------ the roamers

do
  io.write("the roamers that go back to roaming\n")

  local Statics = load_("modules/Gen151/gen2/statics.lua")
  local ROSTER = {
    { species = "RAIKOU", level = 40, map = "ROUTE_42" },
    { species = "ENTEI", level = 40, map = "ROUTE_37" },
  }
  local function ownsNothing() return false end

  -- A beaten or caught beast keeps its slot and loses its species and map,
  -- which is what BattleEnd_HandleRoamMons does -- `win` and `caught` are the
  -- same branch, so a KO reads exactly like a capture.
  local save = { roamers = { { species = nil, map = nil, hp = 0 },
                             { species = "ENTEI", map = "ROUTE_37", hp = 30 } } }
  local back = Statics.restoreRoamers(save, ROSTER, ownsNothing)
  eq(table.concat(back, ","), "RAIKOU", "an emptied slot is refilled")
  eq(save.roamers[1].species, "RAIKOU",
     "with the species its INDEX says it was -- the slot order is the only "
     .. "thing left that identifies a beaten beast")
  eq(save.roamers[1].map, "ROUTE_42", "back on its starting route")
  eq(save.roamers[1].hp, 0,
     "at full health, deliberately: a beast that came back at the health it "
     .. "fled with would be the same beast, and this is a fresh one")

  eq(save.roamers[2].hp, 30,
     "a beast still out there is left completely alone, hp and position and "
     .. "all")

  -- The player who actually caught it keeps the cartridge's behaviour.
  local caught = { roamers = { { species = nil, map = nil, hp = 0 } } }
  local none = Statics.restoreRoamers(caught, ROSTER,
    function(species) return species == "RAIKOU" end)
  eq(#none, 0, "a caught beast is not put back")
  eq(caught.roamers[1].species, nil, "and its slot stays empty")

  eq(#Statics.restoreRoamers(nil, ROSTER, ownsNothing), 0,
     "no save restores nothing")
  eq(#Statics.restoreRoamers({ roamers = {} }, nil, ownsNothing), 0,
     "and no roster restores nothing, rather than raising")
end

-- ------------------------------------------------- Crystal's SUICUNE

do
  io.write("Crystal's SUICUNE goes back to roaming\n")

  local Statics = load_("modules/Gen151/gen2/statics.lua")
  local ROW = { species = "SUICUNE", level = 40, map = "ROUTE_38" }

  local lost = { pokedex = { seen = { SUICUNE = true }, caught = {} },
                 roamers = { { species = "RAIKOU", map = "ROUTE_42" },
                             { species = "ENTEI", map = "ROUTE_37" } } }
  eq(Statics.wantsRoamingSuicune(lost), true,
     "seen and not caught is exactly `you met it and lost it` -- and `seen` "
     .. "is written when a battle starts, so the Route 36 and CIANWOOD "
     .. "sightings, which are sprites walking past, cannot trip it")

  eq(Statics.seedRoamingSuicune(lost, ROW), true, "so the third slot is seeded")
  eq(lost.roamers[3].species, "SUICUNE", "with SUICUNE")
  eq(lost.roamers[3].map, "ROUTE_38", "on the route GOLD and SILVER start it")
  eq(lost.roamers[3].hp, 0, "at full health")
  eq(lost.roamers[1].species, "RAIKOU", "and the other two are untouched")

  eq(Statics.seedRoamingSuicune(lost, ROW), false,
     "seeding is idempotent: a slot that already holds a beast is left alone")

  eq(Statics.wantsRoamingSuicune(
       { pokedex = { seen = { SUICUNE = true }, caught = { SUICUNE = true } } }),
     false, "a player who caught it keeps the cartridge's behaviour")
  eq(Statics.wantsRoamingSuicune({ pokedex = { seen = {}, caught = {} } }),
     false,
     "and a player who has never met it gets nothing -- this must not hand "
     .. "SUICUNE to somebody in the middle of Crystal's story")

  local roaming = { pokedex = { seen = { SUICUNE = true }, caught = {} },
                    roamers = { { species = "SUICUNE", map = "ROUTE_38" } } }
  eq(Statics.wantsRoamingSuicune(roaming), false,
     "a SUICUNE already out there is left completely alone")

  eq(Statics.seedRoamingSuicune({ pokedex = {} }, ROW), false,
     "no roamer list means the beasts were never released, so the player "
     .. "cannot have fought SUICUNE either -- nothing to repair")
  eq(Statics.wantsRoamingSuicune(nil), false, "no save wants nothing")
end

io.write(("gen251: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
