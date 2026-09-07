-- The Johto placement table, checked against its own rules.
--
-- The table is the whole feature: every spawn and every hint comes out of it,
-- so a row that is wrong is a spawn that is wrong somewhere a player will
-- find it and this suite will not.  What can be checked without a cartridge
-- is checked here; what needs the pret trees is checked by
-- tools/build_placements2.py --check, which re-derives SET B and fails on
-- drift.
--
-- Run:  luajit tests/placements2_test.lua

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

local P = assert(loadfile("modules/Gen151/gen2/placements.lua"))()

-- The tiers the table is allowed to ask for, copied from Gen151's rarity.lua
-- rather than required from it: this file has no engine and no sibling mod.
local TIERS = { UNCOMMON = true, RARE = true, VERY_RARE = true }
local BANDS = { low = true, mid = true, high = true }
local METHODS = { grass = true, water = true }
local LINEAGES = { gs = true, crystal = true }

local gates = {}
for _, gate in ipairs(P.GATES) do gates[gate] = true end

-- ------------------------------------------------------------- every row

do
  io.write("every row is well formed\n")

  ok(#P.common >= 30, "the table is populated")

  local bad = {}
  for _, row in ipairs(P.common) do
    local id = tostring(row.species)
    if type(row.species) ~= "string" then bad[#bad + 1] = "species " .. id end
    if type(row.map) ~= "string" then bad[#bad + 1] = id .. " map" end
    if not METHODS[row.method] then bad[#bad + 1] = id .. " method" end
    if not TIERS[row.tier] then bad[#bad + 1] = id .. " tier" end
    if not BANDS[row.band] then bad[#bad + 1] = id .. " band" end
    if type(row.feature) ~= "string" then bad[#bad + 1] = id .. " feature" end
    if row.lineage ~= nil and not LINEAGES[row.lineage] then
      bad[#bad + 1] = id .. " lineage"
    end
  end
  eq(table.concat(bad, ", "), "", "no row has a field the runtime cannot read")
end

-- ------------------------------------------------- SPEC 4: the reasons

do
  io.write("every row says why\n")

  local missing, thin = {}, {}
  for _, row in ipairs(P.common) do
    if type(row.why) ~= "string" or row.why == "" then
      missing[#missing + 1] = tostring(row.species)
    elseif #row.why < 40 then
      thin[#thin + 1] = tostring(row.species)
    end
  end
  eq(table.concat(missing, ", "), "",
     "SPEC 4: a placement with no justification is a placement nobody "
     .. "decided")
  eq(table.concat(thin, ", "), "",
     "and a justification too short to be an argument is the same thing "
     .. "wearing a sentence")
end

-- ------------------------------------------------ one row per species

do
  io.write("one home each\n")

  -- A species placed twice is two spawns for one gap, which doubles the
  -- divergence budget spent on it without anybody deciding to.  The one
  -- exception the shape allows is a lineage-scoped row, which by definition
  -- cannot collide with itself.
  local seen, twice = {}, {}
  for _, row in ipairs(P.common) do
    local key = tostring(row.species) .. "/" .. tostring(row.lineage or "all")
    if seen[key] then twice[#twice + 1] = key end
    seen[key] = true
  end
  eq(table.concat(twice, ", "), "", "no species is placed twice on one lineage")
end

-- ------------------------------------------- SPEC 5: gates that exist

do
  io.write("gates are on the ladder\n")

  local unknown = {}
  for map, gate in pairs(P.MAP_GATES) do
    if not gates[gate] then unknown[#unknown + 1] = map .. "=" .. gate end
  end
  eq(table.concat(unknown, ", "), "",
     "every MAP_GATES rung is one the ladder actually has, so the hint text "
     .. "can never print a requirement the player cannot look up")

  -- The gate is what SPEC 5 is enforced with, so a map carrying a placement
  -- and no gate entry is claiming to be open Johto.  That is a real claim
  -- and usually true -- but never for Kanto, which in Gen 2 sits behind the
  -- Elite Four in its entirety.
  local kanto = {
    ROUTE_1 = true, ROUTE_2 = true, ROUTE_3 = true, ROUTE_4 = true,
    ROUTE_5 = true, ROUTE_6 = true, ROUTE_7 = true, ROUTE_8 = true,
    ROUTE_9 = true, ROUTE_10_NORTH = true, ROUTE_11 = true, ROUTE_12 = true,
    ROUTE_13 = true, ROUTE_14 = true, ROUTE_15 = true, ROUTE_16 = true,
    ROUTE_17 = true, ROUTE_18 = true, ROUTE_21 = true, ROUTE_22 = true,
    ROUTE_24 = true, ROUTE_25 = true, MOUNT_MOON = true,
    ROCK_TUNNEL_1F = true, ROCK_TUNNEL_B1F = true, DIGLETTS_CAVE = true,
  }
  local ungated = {}
  for _, row in ipairs(P.common) do
    if kanto[row.map] and not P.MAP_GATES[row.map] then
      ungated[#ungated + 1] = row.species .. " on " .. row.map
    end
  end
  eq(table.concat(ungated, ", "), "",
     "a Kanto placement always carries a gate: the whole region is behind "
     .. "the Elite Four in Gen 2, and a row that does not say so would "
     .. "print a hint sending a player somewhere they cannot walk")
end

-- --------------------------------------------------- what is NOT placed

do
  io.write("the two categories that are somebody else's job\n")

  local placed = {}
  for _, row in ipairs(P.common) do placed[row.species] = true end

  -- A trade evolution is a missing cable, not a missing habitat.  Placing
  -- one would hand the player ALAKAZAM out of the grass and leave KADABRA
  -- -- which is already renewable -- with nothing to become.
  local TRADE = { "ALAKAZAM", "MACHAMP", "GOLEM", "GENGAR", "POLITOED",
                  "SLOWKING", "STEELIX", "SCIZOR", "KINGDRA", "PORYGON2" }
  local wrong = {}
  for _, species in ipairs(TRADE) do
    if placed[species] then wrong[#wrong + 1] = species end
  end
  eq(table.concat(wrong, ", "), "",
     "no trade evolution is placed: the cable is the answer to a cable")

  -- The statics all exist on the cartridge.  A second copy in the grass
  -- would make LUGIA an encounter rather than an event, which is a much
  -- bigger change than making the one in the Whirl Islands come back.
  -- The eight that really do exist on the cartridge.  The three Kanto birds
  -- are NOT here and that took checking: Gen 2's only statics are the
  -- thirteen `loadwildmon` calls in its map scripts, and ARTICUNO, ZAPDOS and
  -- MOLTRES are not among them -- so they are placed, like MEWTWO and MEW.
  --
  -- These eight are answered without a spawn, three different ways: LUGIA,
  -- HO-OH, SNORLAX and SUDOWOODO are put back on their maps; RAIKOU, ENTEI
  -- and SUICUNE live in the roamer slots, CRYSTAL's SUICUNE included, since
  -- the third slot the cart already rolls is where GOLD and SILVER keep it;
  -- and LAPRAS was never a gap at all -- it is on a DAILY flag, so it is
  -- back in UNION CAVE every Friday.
  local STATIC = { "LAPRAS", "SNORLAX", "SUDOWOODO", "RAIKOU", "ENTEI",
                   "SUICUNE", "LUGIA", "HO_OH" }
  wrong = {}
  for _, species in ipairs(STATIC) do
    if placed[species] then wrong[#wrong + 1] = species end
  end
  eq(table.concat(wrong, ", "), "",
     "no static is placed: a fled LUGIA should come back, not turn up in "
     .. "tall grass")

  -- The six babies breed from adults already in the grass, and the engine
  -- implements the Day-Care, so the gap set closes over breeding and drops
  -- them.  A row for any of them is work nobody needed.
  local BRED = { "PICHU", "CLEFFA", "IGGLYBUFF", "SMOOCHUM", "ELEKID",
                 "MAGBY" }
  wrong = {}
  for _, species in ipairs(BRED) do
    if placed[species] then wrong[#wrong + 1] = species end
  end
  eq(table.concat(wrong, ", "), "",
     "no baby that the Day-Care already produces is placed")
end

-- ------------------------------------------------------ CELEBI's scope

do
  io.write("CELEBI is scoped to the cartridges that need it\n")

  local celebi
  for _, row in ipairs(P.common) do
    if row.species == "CELEBI" then celebi = row end
  end
  ok(celebi, "CELEBI is in the table")
  eq(celebi and celebi.lineage, "gs",
     "and only for GOLD and SILVER: Crystal's own event is switched on by "
     .. "the GS BALL feature, and a spawn as well would be a second CELEBI "
     .. "in a game whose whole point is that there is one")
  eq(celebi and celebi.map, "ILEX_FOREST",
     "in the forest the shrine stands in, which is where it would have been")
end

-- ------------------------------------------------- the three that surprised

do
  io.write("the birds are placed, not left to a static that does not exist\n")

  local placed = {}
  for _, row in ipairs(P.common) do placed[row.species] = row end

  for _, species in ipairs({ "ARTICUNO", "ZAPDOS", "MOLTRES" }) do
    ok(placed[species],
       species .. " has a placement: Gen 2 has no static for it and no wild "
       .. "table entry either, so without a row it is simply not in the game")
  end
  eq(placed.ARTICUNO and placed.ARTICUNO.map, "ICE_PATH_B3F",
     "ARTICUNO in the only ice cave either region has")
  eq(placed.MOLTRES and placed.MOLTRES.tier, "VERY_RARE",
     "and a bird nobody could ever catch here asks vanilla's rarest slot, "
     .. "which is the most this mod is willing to ask")
end

io.write(("placements2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
