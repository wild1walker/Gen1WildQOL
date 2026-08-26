-- placements.lua -- the single source of truth (SPEC 8).
--
-- Every spawn Gen151 adds and every hint it prints comes from this table.
-- hints.lua is generated from it, main.lua drives the roll layer from it, and
-- SPOILERS.md is printed from it, so a placement can never disagree with what
-- the mod tells the player about it.
--
-- Row shape:
--
--   species  the id to substitute in
--   map      the map constant it substitutes on
--   method   "grass" (also the caves/towers/Mansion "indoor" roll, which
--            reads the grass table), "water" (surfing), or "super_rod"
--   tier     a key of rarity.lua's TIERS
--   levels   explicit levels, when the placement is copied from a table that
--            already chose them
--   band     "low" / "mid" / "high" -- otherwise, take the destination map's
--            OWN distinct levels and use that third of them.  SPEC 5: "Match
--            the destination map's existing level band, not the species'
--            vanilla gift level."  Deriving it at load time rather than
--            writing it down is what keeps one row correct on all three
--            versions, whose bands differ by up to twenty levels.
--   gate     the progression gate the map sits behind, for the hint text
--   why      one sentence on why this location.  SPEC 4: "If the
--            justification is 'it needed to go somewhere,' the placement is
--            wrong."
--
-- The version tables are additive to `common`, never a replacement for it.
--
-- Set A rows (the design decisions) are authored here.
-- Set B rows (the version exclusives) are DERIVED and spliced in by
-- tools/build_placements.py; tests/placements_test.lua re-derives them and
-- fails if the checked-in rows have drifted.  Edit the tool, not the block.

local P = {}

-- The ladder from SPEC 5, in order.  A placement's gate must sit at or above
-- the rung the vanilla game charged for that species.
-- The ladder from SPEC 5, in the order the game opens it up.  A placement's
-- gate must sit at or above the rung the vanilla game charged for that
-- species; tests/placements_test.lua checks every row against it.
--
-- Spelled the way the game spells them, in caps, because these strings reach
-- the player through the FIELD NOTES text box.
P.GATES = {
  "FLASH", "the SILPH SCOPE", "the FLUTE", "the BICYCLE",
  "the SAFARI ZONE", "SURF", "STRENGTH", "8 BADGES", "the LEAGUE",
}

-- Which rung each map Gen151 touches sits on.  A map with no entry is open
-- Kanto -- reachable on foot with nothing in the bag -- and its hints simply
-- do not print a requirement line, because there is nothing to require.
P.MAP_GATES = {
  ROCK_TUNNEL_1F = "FLASH", ROCK_TUNNEL_B1F = "FLASH",
  POKEMON_TOWER_3F = "the SILPH SCOPE",
  POKEMON_TOWER_7F = "the SILPH SCOPE",
  ROUTE_12 = "the FLUTE", ROUTE_13 = "the FLUTE",
  ROUTE_14 = "the FLUTE", ROUTE_15 = "the FLUTE",
  ROUTE_16 = "the BICYCLE", ROUTE_17 = "the BICYCLE",
  ROUTE_18 = "the BICYCLE",
  SAFARI_ZONE_CENTER = "the SAFARI ZONE", SAFARI_ZONE_EAST = "the SAFARI ZONE",
  SAFARI_ZONE_NORTH = "the SAFARI ZONE", SAFARI_ZONE_WEST = "the SAFARI ZONE",
  ROUTE_19 = "SURF", ROUTE_20 = "SURF", ROUTE_21 = "SURF",
  POWER_PLANT = "SURF",
  POKEMON_MANSION_1F = "SURF", POKEMON_MANSION_2F = "SURF",
  POKEMON_MANSION_3F = "SURF", POKEMON_MANSION_B1F = "SURF",
  SEAFOAM_ISLANDS_1F = "SURF", SEAFOAM_ISLANDS_B1F = "SURF",
  SEAFOAM_ISLANDS_B2F = "SURF", SEAFOAM_ISLANDS_B3F = "SURF",
  -- IsSurfingAllowed bars the B4F stairs until both plug boulders are down
  -- (FieldDefaults.seafoam), so the deepest floor really is STRENGTH-gated.
  SEAFOAM_ISLANDS_B4F = "STRENGTH",
  ROUTE_23 = "8 BADGES", VICTORY_ROAD_1F = "8 BADGES",
  VICTORY_ROAD_2F = "8 BADGES", VICTORY_ROAD_3F = "8 BADGES",
  CERULEAN_CAVE_1F = "the LEAGUE", CERULEAN_CAVE_2F = "the LEAGUE",
  CERULEAN_CAVE_B1F = "the LEAGUE",

}

-- ------------------------------------------------------- difficulty gating
--
-- SPEC 5: "A species' placement must sit behind progression at least as
-- demanding as its vanilla acquisition."  Two tables make that testable
-- instead of assertable: how far into the game each map is, and how far into
-- the game the vanilla cartridge made you go for each species.
-- tests/placements_test.lua checks every Set A row against the pair.
--
-- The rungs are ordered by when a normal playthrough opens them, not by which
-- HM they need -- what is being gated here is effort, and a route you can
-- only reach after Rock Tunnel is late whether or not anything in your bag
-- says so.
P.LADDER = {
  "open Kanto",          -- 1
  "Cerulean and south",  -- 2
  "past Rock Tunnel",    -- 3
  "past Celadon",        -- 4
  "the POKe FLUTE",      -- 5
  "the SAFARI ZONE",     -- 6
  "SURF",                -- 7
  "CINNABAR",            -- 8
  "STRENGTH",            -- 9
  "VICTORY ROAD",        -- 10
  "CERULEAN CAVE",       -- 11
}

P.MAP_RUNG = {
  ROUTE_1 = 1, ROUTE_2 = 1, ROUTE_3 = 1, ROUTE_4 = 1, ROUTE_22 = 1,
  VIRIDIAN_FOREST = 1, MT_MOON_1F = 1, MT_MOON_B1F = 1, MT_MOON_B2F = 1,
  ROUTE_5 = 2, ROUTE_6 = 2, ROUTE_9 = 2, ROUTE_10 = 2, ROUTE_11 = 2,
  ROUTE_24 = 2, ROUTE_25 = 2, DIGLETTS_CAVE = 2,
  ROCK_TUNNEL_1F = 3, ROCK_TUNNEL_B1F = 3,
  -- Celadon is reached through the Route 7-8 Underground Path, which is on
  -- the far side of Rock Tunnel, so Routes 7 and 8 are later than their
  -- numbers suggest.
  ROUTE_7 = 3, ROUTE_8 = 3,
  POKEMON_TOWER_3F = 4, POKEMON_TOWER_7F = 4,
  ROUTE_12 = 5, ROUTE_13 = 5, ROUTE_14 = 5, ROUTE_15 = 5,
  ROUTE_16 = 5, ROUTE_17 = 5, ROUTE_18 = 5,
  SAFARI_ZONE_CENTER = 6, SAFARI_ZONE_EAST = 6, SAFARI_ZONE_NORTH = 6,
  SAFARI_ZONE_WEST = 6,
  ROUTE_19 = 7, ROUTE_20 = 7, ROUTE_21 = 7, POWER_PLANT = 7,
  POKEMON_MANSION_1F = 8, POKEMON_MANSION_2F = 8, POKEMON_MANSION_3F = 8,
  POKEMON_MANSION_B1F = 8,
  SEAFOAM_ISLANDS_1F = 8, SEAFOAM_ISLANDS_B1F = 8, SEAFOAM_ISLANDS_B2F = 8,
  SEAFOAM_ISLANDS_B3F = 8,
  -- IsSurfingAllowed bars the B4F stairs until both plug boulders are down
  SEAFOAM_ISLANDS_B4F = 9,
  ROUTE_23 = 10, VICTORY_ROAD_1F = 10, VICTORY_ROAD_2F = 10,
  VICTORY_ROAD_3F = 10,
  CERULEAN_CAVE_1F = 11, CERULEAN_CAVE_2F = 11, CERULEAN_CAVE_B1F = 11,
}

-- What the vanilla cartridge charged, per Set A species.  Set B rows are
-- exempt by construction: they land on the maps a sibling cartridge already
-- chose, at the levels it chose, so the price is the one the game itself set.
P.MIN_RUNG = {
  -- Oak hands these over in the first five minutes.
  BULBASAUR = 1, CHARMANDER = 1, SQUIRTLE = 1,
  -- The Route 2 gate trade wants an ABRA, which lives on Routes 24 and 25.
  MR_MIME = 2,
  -- The Celadon Mansion roof, reached through the Route 7-8 tunnel.
  EEVEE = 3,
  -- Both prizes sit in the Saffron Dojo, and Saffron opens on a drink bought
  -- in Celadon.
  HITMONLEE = 4, HITMONCHAN = 4,
  -- The Celadon Game Corner, and a great many coins.
  PORYGON = 4,
  -- The Cerulean trade wants a POLIWHIRL, i.e. a rod and some levels.
  JYNX = 5,
  -- Both statics sleep behind the POKe FLUTE.
  SNORLAX = 5,
  -- Silph Co., which opens once the Rocket Hideout is cleared.
  LAPRAS = 6,
  -- All three revive in the Cinnabar Lab, which is across the water.
  OMANYTE = 8, KABUTO = 8, AERODACTYL = 8,
  -- The journals are in the Mansion, on the same island.
  MEW = 8,
}

-- Which mod option each row answers to, so a player who wants the version
-- exclusives but not a wild Charmander gets exactly that (SPEC 7).
P.FEATURES = {
  exclusives = "version exclusives",
  gifts = "one-time gift mons",
  fossils = "fossils",
  snorlax = "Snorlax",
  mew = "Mew",
}

-- ---------------------------------------------------------------- Set A
--
-- Missing on every version for the same reason on every version, so these
-- rows are shared.  Set C follows from them: fixing BULBASAUR fixes IVYSAUR
-- and VENUSAUR, so neither is placed (SPEC 4 step 1).

P.common = {

  -- ---- starters (VERY_RARE, feature "gifts")
  --
  -- Let's Go Pikachu/Eevee is the later official Kanto game that answered
  -- "where would these live", and its answer is used verbatim: Bulbasaur in
  -- Viridian Forest and Cerulean Cave, Charmander on Route 3 and in Rock
  -- Tunnel, Squirtle on Route 25 and in Seafoam Islands.  Two habitats each,
  -- one early and one late, so a player who reaches the endgame still short
  -- of one is not sent back to a level-4 route to find it.
  { species = "BULBASAUR", map = "VIRIDIAN_FOREST", method = "grass",
    band = "low", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild Bulbasaur in Viridian Forest; the forest is "
      .. "also where a starter-less player first walks through tall grass" },
  { species = "BULBASAUR", map = "CERULEAN_CAVE_1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go's other Bulbasaur habitat, and the late-game copy for a "
      .. "player who finished the game still needing one" },
  { species = "CHARMANDER", map = "ROUTE_3", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild Charmander on Route 3, on the climb to Mt. "
      .. "Moon where a fire type first earns its keep" },
  { species = "CHARMANDER", map = "ROCK_TUNNEL_1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go's other Charmander habitat; a cave that wants a light "
      .. "source is a fair place to meet one" },
  { species = "SQUIRTLE", map = "ROUTE_25", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild Squirtle on Routes 24 and 25, along Cerulean's "
      .. "waterfront" },
  { species = "SQUIRTLE", map = "SEAFOAM_ISLANDS_1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go's other Squirtle habitat, and the one sea cave in Kanto" },

  -- ---- the Fighting Dojo's prize pair (RARE, feature "gifts")
  --
  -- No official Kanto game ever put either in the wild, so this is an
  -- invented location, chosen the way SPEC 4 asks: the only Fighting-type
  -- habitat in Kanto's own tables is Victory Road's Machop line, and Victory
  -- Road sits behind all eight badges, which is at least as demanding as
  -- walking into the Dojo.
  { species = "HITMONLEE", map = "VICTORY_ROAD_1F", method = "grass",
    band = "mid", tier = "RARE", feature = "gifts",
    why = "Kanto's only Fighting-type habitat is Victory Road's Machop line; "
      .. "the Dojo's prize pair belongs with them" },
  { species = "HITMONCHAN", map = "VICTORY_ROAD_2F", method = "grass",
    band = "mid", tier = "RARE", feature = "gifts",
    why = "the other half of the Dojo's prize pair, one floor up from its "
      .. "twin so the choice the Dojo made stays a choice" },

  -- ---- the NPC trades (RARE, feature "gifts")
  { species = "MR_MIME", map = "ROUTE_11", method = "grass",
    band = "high", tier = "RARE", feature = "gifts",
    why = "Route 11's Drowzee band is the only Psychic habitat outside the "
      .. "endgame caves, and the Route 2 trade that hands MR.MIME over in "
      .. "vanilla is itself gated on finding an ABRA" },
  { species = "JYNX", map = "SEAFOAM_ISLANDS_B2F", method = "grass",
    band = "mid", tier = "RARE", feature = "gifts",
    why = "an Ice type belongs in the ice cave; Seafoam is also the only "
      .. "place in Kanto its Seel and Dewgong neighbours live" },

  -- ---- the gifts (RARE, feature "gifts")
  { species = "LAPRAS", map = "ROUTE_20", method = "water", band = "high",
    tier = "RARE", feature = "gifts",
    why = "the open sea between Fuchsia and Cinnabar, past the Seafoam "
      .. "Islands -- the one stretch of Kanto where surfing something that "
      .. "big reads as ordinary" },
  { species = "EEVEE", map = "ROUTE_7", method = "grass", band = "mid",
    tier = "RARE", feature = "gifts",
    why = "Route 7 is the Celadon approach, so the gate is the same one the "
      .. "Celadon Mansion gift sits behind" },
  { species = "PORYGON", map = "POWER_PLANT", method = "grass", band = "mid",
    tier = "RARE", feature = "gifts",
    why = "the only man-made-Pokemon habitat in Kanto: a building full of "
      .. "Magnemite and Voltorb, behind SURF rather than a coin counter" },

  -- ---- the fossils (VERY_RARE, feature "fossils")
  --
  -- Invented locations: no official Kanto game puts any of the three in a
  -- wild table.  The gate is the constraint that decided them -- vanilla
  -- charges a Cinnabar Lab revival for all three, so none of them may appear
  -- anywhere reachable before SURF, which rules out Mt. Moon, where the
  -- fossils are actually found.
  { species = "OMANYTE", map = "SEAFOAM_ISLANDS_B4F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "fossils",
    why = "the deepest floor of the sea cave, behind SURF and STRENGTH: a "
      .. "living ammonite belongs where the water never reached the surface" },
  { species = "KABUTO", map = "SEAFOAM_ISLANDS_B3F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "fossils",
    why = "one floor above its Helix counterpart, so the two fossils keep "
      .. "the separation the Mt. Moon choice gave them" },
  { species = "AERODACTYL", map = "VICTORY_ROAD_3F", method = "grass",
    band = "high", tier = "VERY_RARE", feature = "fossils",
    why = "the top of the last rock cave before the League: the only place "
      .. "in Kanto whose band suits a revived AERODACTYL and whose gate is "
      .. "at least as demanding as the Old Amber's Cinnabar Lab" },

  -- ---- Snorlax (VERY_RARE, feature "snorlax")
  --
  -- SPEC 5: both statics stay; this is the renewable copy so a player who
  -- KOs or flees both is not locked out.  The two statics sleep on Routes 12
  -- and 16, so their immediate neighbours are where a third one wandered to.
  { species = "SNORLAX", map = "ROUTE_13", method = "grass", band = "high",
    tier = "VERY_RARE", feature = "snorlax",
    why = "next door to the Route 12 sleeper: one that wandered south and "
      .. "found somewhere quieter" },
  { species = "SNORLAX", map = "ROUTE_17", method = "grass", band = "high",
    tier = "VERY_RARE", feature = "snorlax",
    why = "next door to the Route 16 sleeper, down the length of Cycling "
      .. "Road" },

  -- ---- Mew (VERY_RARE, feature "mew", gated)
  --
  -- Not a static and not an ordinary wild slot: the row only exists once the
  -- Mansion journals have been read, and until then the species is not in
  -- data.encounters at all, so the AREA screen cannot spoil it.
  { species = "MEW", map = "POKEMON_MANSION_B1F", method = "grass",
    band = "high", tier = "VERY_RARE", feature = "mew", gated = "mew",
    -- the only row that overrides its map's gate: reaching the Mansion is
    -- not what unlocks this one, reading all four of its journals is
    gate = "4 JOURNALS",
    why = "the basement the journals describe: MEW was here before MEWTWO "
      .. "was, and reading all four diaries is what brings it back" },
}

-- ---------------------------------------------------------- Super Rod
--
-- The `encounter.fishing` hook, which touches no grass table and cannot
-- conflict with any encounter mod.  Substitution rather than an extra pool
-- entry: the engine's rejection loop picks `floor(r/2) % 4`, so a fifth entry
-- in a Super Rod group is unreachable no matter who adds it.
--
-- These rows are invisible to the AREA screen (SPEC 6a), so every one of them
-- is covered explicitly by the FIELD NOTES hints.
P.fishing = {
  { species = "OMANYTE", map = "SEAFOAM_ISLANDS_B4F", rod = "SUPER_ROD",
    band = "high", tier = "VERY_RARE", feature = "fossils",
    why = "the same floor as its grass row, for a player carrying a rod "
      .. "instead of a repel" },
  { species = "KABUTO", map = "SEAFOAM_ISLANDS_B3F", rod = "SUPER_ROD",
    band = "high", tier = "VERY_RARE", feature = "fossils",
    why = "the same floor as its grass row" },
}

-- ---------------------------------------------------------------- Set B
--
-- DERIVED.  Do not hand-edit: tools/build_placements.py regenerates this
-- block and tests/placements_test.lua fails if it has drifted.
--
-- The rule: a species missing from one version is present on another, and
-- that other version already answered every question a placement has to
-- answer -- which maps, which levels, which company.  Re-using its answer is
-- the most defensible source there is, and it makes the addition feel like it
-- was always there, because on the other cartridge it was.
--
-- Two rows carry a tier the rule cannot derive.  FARFETCHD and LICKITUNG are
-- wild on Yellow but cost an NPC trade on Red and Blue, so Yellow's tables
-- give the location and Red's price gives the tier.
--
-- One table, not three.  Every row here -- and every row in P.common above --
-- is applied only when its species has no renewable source in the tables
-- actually merged on this install, which is the same question the derivation
-- asked.  So a Red row cannot fire on Blue, no version has to be detected at
-- all, and a species some other encounter mod already provided is left alone
-- rather than provided twice.

P.gapFill = {
  -- BELLSPROUT: BLUE puts it on ROUTE_12, ROUTE_13, ROUTE_14, ROUTE_15,
  -- ROUTE_24, ROUTE_25, ROUTE_5, ROUTE_6, ROUTE_7. Gen151 gives every
  -- version that is missing it the same maps at the substitution rate,
  -- carrying BLUE's own levels.
  { species = "BELLSPROUT", map = "ROUTE_12", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_13", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_14", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_15", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_24", method = "grass",
    levels = { 12, 13, 14 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_25", method = "grass",
    levels = { 12, 13, 14 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_5", method = "grass",
    levels = { 13, 15, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_6", method = "grass",
    levels = { 13, 15, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "BELLSPROUT", map = "ROUTE_7", method = "grass",
    levels = { 19, 22 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  -- EKANS: RED puts it on ROUTE_10, ROUTE_11, ROUTE_23, ROUTE_4, ROUTE_8,
  -- ROUTE_9. Gen151 gives every version that is missing it the same maps at
  -- the substitution rate, carrying RED's own levels.
  { species = "EKANS", map = "ROUTE_10", method = "grass",
    levels = { 11, 13, 15, 17 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "EKANS", map = "ROUTE_11", method = "grass",
    levels = { 12, 14, 15 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "EKANS", map = "ROUTE_23", method = "grass",
    levels = { 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "EKANS", map = "ROUTE_4", method = "grass",
    levels = { 6, 8, 10, 12 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "EKANS", map = "ROUTE_8", method = "grass",
    levels = { 17, 19 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "EKANS", map = "ROUTE_9", method = "grass",
    levels = { 11, 13, 15, 17 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- ELECTABUZZ: RED puts it on POWER_PLANT. Gen151 gives every version that
  -- is missing it the same maps at the substitution rate, carrying RED's
  -- own levels.
  { species = "ELECTABUZZ", map = "POWER_PLANT", method = "grass",
    levels = { 33, 36 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- FARFETCHD: YELLOW puts it on ROUTE_12, ROUTE_13. Gen151 gives every
  -- version that is missing it the same maps at the substitution rate,
  -- carrying YELLOW's own levels.
  { species = "FARFETCHD", map = "ROUTE_12", method = "grass",
    levels = { 26, 31 }, tier = "RARE", feature = "exclusives",
    why = "YELLOW's own grass table" },
  { species = "FARFETCHD", map = "ROUTE_13", method = "grass",
    levels = { 26, 31 }, tier = "RARE", feature = "exclusives",
    why = "YELLOW's own grass table" },
  -- GROWLITHE: RED puts it on POKEMON_MANSION_1F, POKEMON_MANSION_2F,
  -- POKEMON_MANSION_3F, POKEMON_MANSION_B1F, ROUTE_7, ROUTE_8. Gen151 gives
  -- every version that is missing it the same maps at the substitution
  -- rate, carrying RED's own levels.
  { species = "GROWLITHE", map = "POKEMON_MANSION_1F", method = "grass",
    levels = { 34 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "GROWLITHE", map = "POKEMON_MANSION_2F", method = "grass",
    levels = { 32 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "GROWLITHE", map = "POKEMON_MANSION_3F", method = "grass",
    levels = { 33 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "GROWLITHE", map = "POKEMON_MANSION_B1F", method = "grass",
    levels = { 35 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "GROWLITHE", map = "ROUTE_7", method = "grass",
    levels = { 18, 20 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "GROWLITHE", map = "ROUTE_8", method = "grass",
    levels = { 15, 16, 17, 18 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- KOFFING: RED puts it on POKEMON_MANSION_1F, POKEMON_MANSION_2F,
  -- POKEMON_MANSION_3F, POKEMON_MANSION_B1F. Gen151 gives every version
  -- that is missing it the same maps at the substitution rate, carrying
  -- RED's own levels.
  { species = "KOFFING", map = "POKEMON_MANSION_1F", method = "grass",
    levels = { 30, 32 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "KOFFING", map = "POKEMON_MANSION_2F", method = "grass",
    levels = { 30, 34 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "KOFFING", map = "POKEMON_MANSION_3F", method = "grass",
    levels = { 31, 35 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "KOFFING", map = "POKEMON_MANSION_B1F", method = "grass",
    levels = { 31, 33 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- LICKITUNG: YELLOW puts it on CERULEAN_CAVE_B1F. Gen151 gives every
  -- version that is missing it the same maps at the substitution rate,
  -- carrying YELLOW's own levels.
  { species = "LICKITUNG", map = "CERULEAN_CAVE_B1F", method = "grass",
    levels = { 50, 55 }, tier = "RARE", feature = "exclusives",
    why = "YELLOW's own grass table" },
  -- MAGMAR: BLUE puts it on POKEMON_MANSION_3F, POKEMON_MANSION_B1F. Gen151
  -- gives every version that is missing it the same maps at the
  -- substitution rate, carrying BLUE's own levels.
  { species = "MAGMAR", map = "POKEMON_MANSION_3F", method = "grass",
    levels = { 34 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "MAGMAR", map = "POKEMON_MANSION_B1F", method = "grass",
    levels = { 38 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  -- MANKEY: RED puts it on ROUTE_5, ROUTE_6, ROUTE_7, ROUTE_8. Gen151 gives
  -- every version that is missing it the same maps at the substitution
  -- rate, carrying RED's own levels.
  { species = "MANKEY", map = "ROUTE_5", method = "grass",
    levels = { 10, 12, 14, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "MANKEY", map = "ROUTE_6", method = "grass",
    levels = { 10, 12, 14, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "MANKEY", map = "ROUTE_7", method = "grass",
    levels = { 17, 18, 19, 20 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "MANKEY", map = "ROUTE_8", method = "grass",
    levels = { 18, 20 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- MEOWTH: BLUE puts it on ROUTE_5, ROUTE_6, ROUTE_7, ROUTE_8. Gen151
  -- gives every version that is missing it the same maps at the
  -- substitution rate, carrying BLUE's own levels.
  { species = "MEOWTH", map = "ROUTE_5", method = "grass",
    levels = { 10, 12, 14, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "MEOWTH", map = "ROUTE_6", method = "grass",
    levels = { 10, 12, 14, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "MEOWTH", map = "ROUTE_7", method = "grass",
    levels = { 17, 18, 19, 20 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "MEOWTH", map = "ROUTE_8", method = "grass",
    levels = { 18, 20 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  -- ODDISH: RED puts it on ROUTE_12, ROUTE_13, ROUTE_14, ROUTE_15,
  -- ROUTE_24, ROUTE_25, ROUTE_5, ROUTE_6, ROUTE_7. Gen151 gives every
  -- version that is missing it the same maps at the substitution rate,
  -- carrying RED's own levels.
  { species = "ODDISH", map = "ROUTE_12", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_13", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_14", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_15", method = "grass",
    levels = { 22, 24, 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_24", method = "grass",
    levels = { 12, 13, 14 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_25", method = "grass",
    levels = { 12, 13, 14 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_5", method = "grass",
    levels = { 13, 15, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_6", method = "grass",
    levels = { 13, 15, 16 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "ODDISH", map = "ROUTE_7", method = "grass",
    levels = { 19, 22 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- PIKACHU: RED puts it on POWER_PLANT, VIRIDIAN_FOREST. Gen151 gives
  -- every version that is missing it the same maps at the substitution
  -- rate, carrying RED's own levels.
  { species = "PIKACHU", map = "POWER_PLANT", method = "grass",
    levels = { 20, 24 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "PIKACHU", map = "VIRIDIAN_FOREST", method = "grass",
    levels = { 3, 5 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- PINSIR: BLUE puts it on SAFARI_ZONE_CENTER, SAFARI_ZONE_EAST. Gen151
  -- gives every version that is missing it the same maps at the
  -- substitution rate, carrying BLUE's own levels.
  { species = "PINSIR", map = "SAFARI_ZONE_CENTER", method = "grass",
    levels = { 23 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "PINSIR", map = "SAFARI_ZONE_EAST", method = "grass",
    levels = { 28 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  -- SANDSHREW: BLUE puts it on ROUTE_10, ROUTE_11, ROUTE_23, ROUTE_4,
  -- ROUTE_8, ROUTE_9. Gen151 gives every version that is missing it the
  -- same maps at the substitution rate, carrying BLUE's own levels.
  { species = "SANDSHREW", map = "ROUTE_10", method = "grass",
    levels = { 11, 13, 15, 17 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "SANDSHREW", map = "ROUTE_11", method = "grass",
    levels = { 12, 14, 15 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "SANDSHREW", map = "ROUTE_23", method = "grass",
    levels = { 26 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "SANDSHREW", map = "ROUTE_4", method = "grass",
    levels = { 6, 8, 10, 12 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "SANDSHREW", map = "ROUTE_8", method = "grass",
    levels = { 17, 19 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "SANDSHREW", map = "ROUTE_9", method = "grass",
    levels = { 11, 13, 15, 17 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  -- SCYTHER: RED puts it on SAFARI_ZONE_CENTER, SAFARI_ZONE_EAST. Gen151
  -- gives every version that is missing it the same maps at the
  -- substitution rate, carrying RED's own levels.
  { species = "SCYTHER", map = "SAFARI_ZONE_CENTER", method = "grass",
    levels = { 23 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "SCYTHER", map = "SAFARI_ZONE_EAST", method = "grass",
    levels = { 28 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  -- VULPIX: BLUE puts it on POKEMON_MANSION_1F, POKEMON_MANSION_2F,
  -- POKEMON_MANSION_3F, POKEMON_MANSION_B1F, ROUTE_7, ROUTE_8. Gen151 gives
  -- every version that is missing it the same maps at the substitution
  -- rate, carrying BLUE's own levels.
  { species = "VULPIX", map = "POKEMON_MANSION_1F", method = "grass",
    levels = { 34 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "VULPIX", map = "POKEMON_MANSION_2F", method = "grass",
    levels = { 32 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "VULPIX", map = "POKEMON_MANSION_3F", method = "grass",
    levels = { 33 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "VULPIX", map = "POKEMON_MANSION_B1F", method = "grass",
    levels = { 35 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "VULPIX", map = "ROUTE_7", method = "grass",
    levels = { 18, 20 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  { species = "VULPIX", map = "ROUTE_8", method = "grass",
    levels = { 15, 16, 17, 18 }, tier = "UNCOMMON", feature = "exclusives",
    why = "BLUE's own grass table" },
  -- WEEDLE: RED puts it on ROUTE_2, ROUTE_24, ROUTE_25, VIRIDIAN_FOREST.
  -- Gen151 gives every version that is missing it the same maps at the
  -- substitution rate, carrying RED's own levels.
  { species = "WEEDLE", map = "ROUTE_2", method = "grass",
    levels = { 3, 4, 5 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "WEEDLE", map = "ROUTE_24", method = "grass",
    levels = { 7 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "WEEDLE", map = "ROUTE_25", method = "grass",
    levels = { 8 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
  { species = "WEEDLE", map = "VIRIDIAN_FOREST", method = "grass",
    levels = { 3, 4, 5 }, tier = "UNCOMMON", feature = "exclusives",
    why = "RED's own grass table" },
}

return P
