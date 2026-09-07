-- placements.lua -- the single source of truth for the 251, Johto edition.
--
-- Same contract as Gen151's table, and the same two rules that make it worth
-- reading:
--
--   SPEC 4  If the justification is "it needed to go somewhere," the
--           placement is wrong.
--   SPEC 5  A species' placement must sit behind progression at least as
--           demanding as its vanilla acquisition.
--
-- Row shape:
--
--   species  the id to substitute in
--   map      the map constant it substitutes on
--   method   "grass" (which is also the cave and tower roll) or "water"
--   tier     a key of rarity.lua's TIERS
--   band     "low" / "mid" / "high" -- the destination map's OWN levels,
--            thirded, rather than the species' vanilla gift level.  Derived
--            at load time so one row stays right on all three cartridges,
--            whose bands differ by as much as twenty levels.
--   gate     the progression rung the map sits behind, for the hint text
--   lineage  optional: "gs" or "crystal", when a row is right on one
--            lineage and wrong on the other.  CELEBI is the only user.
--   why      one sentence on why this location.
--
-- ------- what is derived and what is decided
--
-- SET B, the version exclusives, is DERIVED and spliced in by
-- tools/build_placements2.py.  It needs no taste: the species is missing on
-- one cartridge and present on another, so the placement is simply the map
-- the OTHER cartridge puts it on.  That is the strongest authority available
-- -- it is what the same game does with the same species on the same map --
-- and it is why GOLD's VULPIX and SILVER's GROWLITHE both land on ROUTE_36.
-- The two cartridges swap exactly that slot, and the mod swaps it back.
--
-- SET A, below, is the part that needed deciding, and every row cites
-- something.  Where a later official game put a species in the wild, that is
-- the authority (the three Kanto starters are Let's Go's own habitats, two of
-- them on the same route number).  Where no game ever did, the row says so
-- and justifies itself on habitat and gate instead, the way Gen151's fossils
-- do.
--
-- ------- what is NOT here
--
-- Two whole categories, on purpose:
--
--   the ten trade evolutions   ALAKAZAM, MACHAMP, GOLEM, GENGAR, POLITOED,
--                              SLOWKING, STEELIX, SCIZOR, KINGDRA, PORYGON2.
--                              A trade evolution is not a missing habitat,
--                              it is a missing cable, so it gets the cable.
--   the eleven statics         LAPRAS, SNORLAX, SUDOWOODO, the three birds,
--                              the three beasts, LUGIA, HO-OH.  All of them
--                              exist on the cartridge and none is renewable,
--                              so the answer is to let a fled or fainted one
--                              come back rather than to put a second copy in
--                              the grass.
--
-- And six babies that look missing and are not: PICHU, CLEFFA, IGGLYBUFF,
-- SMOOCHUM, ELEKID and MAGBY all breed from adults already in the grass, and
-- the engine implements the Day-Care (src/core/gen2/Breeding.lua), so the
-- gap set closes over breeding and drops them.  Placing them would have been
-- inventing work for the player and for this table.

local P = {}

-- The rungs, in the order Johto opens them, spelled the way the game spells
-- them because these strings reach the player through the FIELD NOTES box.
P.GATES = {
  "CUT", "FLASH", "SURF", "WHIRLPOOL", "STRENGTH",
  "8 BADGES", "the LEAGUE", "16 BADGES",
}

-- Which rung each map this table touches sits on.  A map with no entry is
-- open Johto -- reachable on foot with nothing in the bag -- and prints no
-- requirement line, because there is nothing to require.
P.MAP_GATES = {
  ILEX_FOREST = "CUT",
  DARK_CAVE_VIOLET_ENTRANCE = "FLASH",
  DARK_CAVE_BLACKTHORN_ENTRANCE = "FLASH",
  ROUTE_32 = "SURF",          -- the water table, not the grass
  ROUTE_41 = "SURF",
  MOUNT_MORTAR_B1F = "STRENGTH",
  ICE_PATH_1F = "STRENGTH",
  WHIRL_ISLAND_B1F = "WHIRLPOOL",
  WHIRL_ISLAND_B2F = "WHIRLPOOL",
  -- Kanto in its entirety is behind the Elite Four in Gen 2.
  ROUTE_2 = "the LEAGUE", ROUTE_3 = "the LEAGUE", ROUTE_10_NORTH = "the LEAGUE",
  ROUTE_25 = "the LEAGUE", VICTORY_ROAD = "8 BADGES",
  SILVER_CAVE_ROOM_3 = "16 BADGES",
}

-- ------------------------------------------------------------------ SET A
--
-- The decisions.  Ordered by what they answer rather than by dex number, so
-- a reader can check a whole category's reasoning at once.

P.common = {

  -- ---- the Kanto starters (VERY_RARE, feature "gifts")
  --
  -- Let's Go is the authority, exactly as it is in Gen151: it is the one
  -- official game that ever put these three in tall grass, and two of its
  -- three habitats survive into Gen 2's Kanto under the same route number.
  { species = "BULBASAUR", map = "ROUTE_2", method = "grass", band = "mid",
    tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild BULBASAUR in VIRIDIAN FOREST, and Route 2 is "
      .. "what Gen 2 left of that forest -- the same trees, walked through "
      .. "rather than entered" },
  { species = "CHARMANDER", map = "ROUTE_3", method = "grass", band = "mid",
    tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go's own CHARMANDER route, still there and still the climb "
      .. "to MT.MOON" },
  { species = "SQUIRTLE", map = "ROUTE_25", method = "grass", band = "mid",
    tier = "VERY_RARE", feature = "gifts",
    why = "Let's Go puts wild SQUIRTLE on Routes 24 and 25; 25 is the one "
      .. "that still carries a grass table in Gen 2" },

  -- ---- the Johto starters (VERY_RARE, feature "gifts")
  --
  -- Invented locations, and the row says so: no official game has ever put a
  -- Johto starter in a wild table, so these are justified on habitat and
  -- gate the way Gen151's fossils are.  One each of forest, fire and river,
  -- which is also what the three of them are.
  { species = "CHIKORITA", map = "ILEX_FOREST", method = "grass", band = "mid",
    tier = "VERY_RARE", feature = "gifts",
    why = "Johto has exactly one forest and this is it -- the leaf on "
      .. "CHIKORITA's head is the forest's own canopy, and the shrine at its "
      .. "centre is already where Johto keeps what it will not explain" },
  { species = "CYNDAQUIL", map = "BURNED_TOWER_1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "the tower burned down and nothing has grown back: a fire mouse "
      .. "that sleeps in ash is the one thing that would live there, and the "
      .. "floor already rolls its own encounters" },
  { species = "TOTODILE", map = "ROUTE_32", method = "water", band = "mid",
    tier = "VERY_RARE", feature = "gifts",
    why = "the river below VIOLET, which is the first real water in Johto "
      .. "and the only stretch of it a jaw that size has room in" },

  -- ---- the gift and the prize (RARE, feature "gifts")
  { species = "EEVEE", map = "ROUTE_34", method = "grass", band = "mid",
    tier = "RARE", feature = "gifts",
    why = "Route 34 is the GOLDENROD approach, so the gate is the same one "
      .. "BILL's gift sits behind -- the rule Gen151 used for the CELADON "
      .. "MANSION EEVEE, one city over" },
  { species = "PORYGON", map = "ROUTE_10_NORTH", method = "grass", band = "mid",
    tier = "RARE", feature = "gifts",
    why = "the route the POWER PLANT stands on, and the only place Gen 2 "
      .. "still keeps VOLTORB: the man-made-Pokemon habitat, behind the "
      .. "LEAGUE rather than behind a coin counter" },

  -- ---- the fossils (VERY_RARE, feature "fossils")
  --
  -- Invented, like Gen151's.  The gate is what decided them: no cartridge
  -- will revive a fossil for you in Gen 2 at all, so nothing here may sit
  -- anywhere a player reaches on the way past.  The two marine fossils keep
  -- the one-floor separation the Mt. Moon choice used to give them.
  { species = "OMANYTE", map = "WHIRL_ISLAND_B2F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "fossils",
    why = "the deep floor of the sea cave, behind SURF and WHIRLPOOL: a "
      .. "living ammonite belongs where the water never reached the surface" },
  { species = "KABUTO", map = "WHIRL_ISLAND_B1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "fossils",
    why = "one floor above its Helix counterpart, so the two fossils keep "
      .. "the separation the Mt. Moon choice gave them" },
  { species = "AERODACTYL", map = "VICTORY_ROAD", method = "grass",
    band = "high", tier = "VERY_RARE", feature = "fossils",
    why = "the last rock cave before the League, which is where Gen151 put "
      .. "it in Kanto and is the same argument here: the only band that "
      .. "suits a revived AERODACTYL behind the only gate that suits it" },

  -- ---- the two the cartridge hands over once (VERY_RARE)
  { species = "TYROGUE", map = "MOUNT_MORTAR_B1F", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "the KARATE KING's own floor -- the cartridge already hands a "
      .. "TYROGUE over down here, so this is that gift made renewable "
      .. "rather than a new idea about where one lives" },
  { species = "TOGEPI", map = "ROUTE_30", method = "grass", band = "low",
    tier = "VERY_RARE", feature = "gifts",
    why = "where MR.POKeMON found the egg: the row puts the species back "
      .. "where its own story says it came from" },

  -- ---- the five that are not on the cartridge at all (VERY_RARE)
  --
  -- The three Kanto birds join MEWTWO and MEW here, and it took checking to
  -- believe it: Gen 2's ONLY statics are the thirteen `loadwildmon` calls in
  -- its map scripts, and ARTICUNO, ZAPDOS and MOLTRES are not among them.
  -- They are not gated, not roaming and not in a wild table -- they simply
  -- are not in Gold, Silver or Crystal.  So unlike LUGIA or SNORLAX, which
  -- exist and merely cannot be got twice, these five have no acquisition of
  -- any kind and these rows are not a renewable copy of something.  They are
  -- the only way.
  { species = "ARTICUNO", map = "ICE_PATH_B3F", method = "grass", band = "high",
    tier = "VERY_RARE", feature = "gifts",
    why = "the deepest floor of the only ice cave either region has, behind "
      .. "STRENGTH: Gen 2 kept ARTICUNO's habitat and left the bird out of "
      .. "it" },
  { species = "ZAPDOS", map = "ROUTE_10_NORTH", method = "grass", band = "high",
    tier = "VERY_RARE", feature = "gifts",
    why = "the route the POWER PLANT stands on, which is where ZAPDOS lived "
      .. "in Red and is still the only place Gen 2 keeps VOLTORB" },
  { species = "MOLTRES", map = "SILVER_CAVE_OUTSIDE", method = "grass",
    band = "high", tier = "VERY_RARE", feature = "gifts",
    why = "FireRed puts MOLTRES at a mountain's summit and MT.SILVER is the "
      .. "only summit Gen 2 has -- behind sixteen badges, which is the "
      .. "hardest thing either region asks for anything" },

  --
  -- CERULEAN CAVE is sealed in Gen 2 and nothing replaced it.
  { species = "MEWTWO", map = "SILVER_CAVE_ROOM_3", method = "grass",
    band = "high", tier = "VERY_RARE", feature = "gifts",
    why = "CERULEAN CAVE is sealed in Gen 2 and MT.SILVER is the cave that "
      .. "replaced it: the deepest room, behind sixteen badges, which asks "
      .. "more than the Kanto cave ever did" },
  { species = "MEW", map = "RUINS_OF_ALPH_INNER_CHAMBER", method = "grass",
    band = "mid", tier = "VERY_RARE", feature = "gifts",
    why = "the one room in Johto you reach by solving something rather than "
      .. "by walking, which is the shape MEW's Gen 1 placement had: the "
      .. "MANSION journals made you read before the forest would answer" },

  -- ---- CELEBI, on the two cartridges that cannot be given the event
  --
  -- Crystal does not want this row and does not get it: the GS BALL feature
  -- switches the cartridge's own event back on, and a spawn as well would be
  -- a second CELEBI in a game whose whole point is that there is one.
  { species = "CELEBI", map = "ILEX_FOREST", method = "grass", band = "high",
    tier = "VERY_RARE", feature = "gifts", lineage = "gs",
    why = "GOLD and SILVER have no shrine script to switch on -- no GS BALL, "
      .. "no event, nothing gated -- but they do have the forest the shrine "
      .. "stands in, and that is where it would have been" },

  -- BEGIN SET B -- generated by tools/build_placements2.py
  --
  -- Do not edit: run tools/build_placements2.py.  Each row is the
  -- map the sibling cartridge keeps this species on, which is the
  -- strongest authority there is -- it is the same game doing the
  -- same thing with the same species.
  --
  { species = "EKANS", map = "ROUTE_32", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "SILVER and CRYSTAL keep it on ROUTE_32 / ROUTE_33 / ROUTE_42; GOLD keeps it nowhere at all" },
  { species = "SANDSHREW", map = "UNION_CAVE_1F", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and CRYSTAL keep it on UNION_CAVE_1F / UNION_CAVE_B1F; SILVER keeps it nowhere at all" },
  { species = "VULPIX", map = "ROUTE_36", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "SILVER keeps it on ROUTE_36 / ROUTE_37; neither GOLD nor CRYSTAL keeps it anywhere" },
  { species = "MEOWTH", map = "ROUTE_38", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "SILVER and CRYSTAL keep it on ROUTE_38 / ROUTE_39; GOLD keeps it nowhere at all" },
  { species = "MANKEY", map = "ROUTE_42", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD keeps it on ROUTE_42; neither SILVER nor CRYSTAL keeps it anywhere" },
  { species = "GROWLITHE", map = "ROUTE_36", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and CRYSTAL keep it on ROUTE_35 / ROUTE_36 / ROUTE_37; SILVER keeps it nowhere at all" },
  { species = "LEDYBA", map = "ROUTE_30", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "SILVER and CRYSTAL keep it on NATIONAL_PARK / ROUTE_30 / ROUTE_31 / ROUTE_36 / ROUTE_37; GOLD keeps it nowhere at all" },
  { species = "SPINARAK", map = "ROUTE_30", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and CRYSTAL keep it on NATIONAL_PARK / ROUTE_30 / ROUTE_31 / ROUTE_36 / ROUTE_37; SILVER keeps it nowhere at all" },
  { species = "MAREEP", map = "ROUTE_32", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and SILVER keep it on ROUTE_32 / ROUTE_42 / ROUTE_43; CRYSTAL keeps it nowhere at all" },
  { species = "GIRAFARIG", map = "ROUTE_43", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and SILVER keep it on ROUTE_43; CRYSTAL keeps it nowhere at all" },
  { species = "GLIGAR", map = "ROUTE_45", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and CRYSTAL keep it on ROUTE_45; SILVER keeps it nowhere at all" },
  { species = "TEDDIURSA", map = "DARK_CAVE_VIOLET_ENTRANCE", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and CRYSTAL keep it on DARK_CAVE_BLACKTHORN_ENTRANCE / DARK_CAVE_VIOLET_ENTRANCE / ROUTE_45; SILVER keeps it nowhere at all" },
  { species = "DELIBIRD", map = "ICE_PATH_1F", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "SILVER and CRYSTAL keep it on ICE_PATH_1F / ICE_PATH_B1F / ICE_PATH_B2F_BLACKTHORN_SIDE / ICE_PATH_B2F_MAHOGANY_SIDE / ICE_PATH_B3F; GOLD keeps it nowhere at all" },
  { species = "MANTINE", map = "ROUTE_41", method = "water", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "GOLD and CRYSTAL keep it on ROUTE_41; SILVER keeps it nowhere at all" },
  { species = "SKARMORY", map = "ROUTE_45", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "SILVER and CRYSTAL keep it on ROUTE_45; GOLD keeps it nowhere at all" },
  { species = "PHANPY", map = "ROUTE_46", method = "grass", band = "mid",
    tier = "UNCOMMON", feature = "exclusives",
    why = "SILVER and CRYSTAL keep it on ROUTE_45 / ROUTE_46; GOLD keeps it nowhere at all" },
  -- END SET B
}

return P
