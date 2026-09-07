-- placements.lua + the live Gen 2 tables -> substitution rows.
--
-- Pure Lua: everything here takes plain tables and gives back plain values,
-- so tests/gen251build_test.lua drives it with no engine and no love.*.
-- main.lua does the wiring; this file does the deciding.
--
-- ------- the rule that replaces version detection
--
-- A placement is applied only when its species has NO renewable source in the
-- tables actually merged on this install.  Same rule Gen151 uses, and it does
-- the same three jobs: GOLD's VULPIX row simply does not fire on SILVER,
-- where VULPIX is already in the grass; a species some other encounter mod
-- already provided is left alone rather than provided twice; and nothing has
-- to ask which cartridge is running.
--
-- ------- why Gen 2 substitutes and never appends
--
-- Gen151 appends slots to a map's table and hides them from stage one.  That
-- is not available here, and not because it would be awkward: Gold picks a
-- grass slot with
--
--     slotFor(Encounter.GRASS_SLOT_CHANCES, roll(random, 100))
--     src/battle/gen2/Encounter.lua:52
--
-- a fixed seven-entry probability ladder.  An eighth slot is UNREACHABLE --
-- exactly the argument Gen151 makes about the Super Rod, where a fifth entry
-- in a group can never be drawn.  So substitution is the only honest way in,
-- which makes this layer simpler than its Gen 1 counterpart rather than
-- harder: there is nothing to append, so there is no vanilla slot count to
-- record and nothing to trim back out before stage one runs.

local Build = {}

-- Gold's three grass tables per map, and the one water table.
local DAYTIMES = { "MORN", "DAY", "NITE" }

-- ------------------------------------------------------------ renewability

-- Every species reachable from a table that can be rolled again tomorrow.
--
-- Gold has more of these than Red does, and all of them count: the swarms
-- shadow a map's own table while they run, headbutt trees and Rock Smash are
-- re-rollable indefinitely, and the Bug-Catching Contest comes round every
-- week.  Statics, gifts, NPC trades, the Game Corner and the roaming beasts
-- are all deliberately absent -- "obtainable" is not the bar, "renewable" is.
function Build.renewable(tables, pokemon)
  local have = {}
  local function take(species)
    if type(species) == "string" then have[species] = true end
  end

  for _, key in ipairs({ "grass", "swarmGrass" }) do
    for _, entry in pairs((tables or {})[key] or {}) do
      for _, daytime in ipairs(DAYTIMES) do
        for _, slot in ipairs((entry.slots or {})[daytime] or {}) do
          take(slot.species)
        end
      end
    end
  end

  for _, key in ipairs({ "water", "swarmWater" }) do
    for _, entry in pairs((tables or {})[key] or {}) do
      for _, slot in ipairs(entry.slots or {}) do take(slot.species) end
    end
  end

  -- the rods.  A fishing slot's species may be the literal 0 the ROM uses for
  -- "no fish here, roll the map's water table instead", and the day/nite
  -- sub-rows carry their own species, so both shapes are read.
  for _, group in pairs((tables or {}).fishGroups or {}) do
    for _, rod in ipairs({ "old", "good", "super" }) do
      for _, slot in ipairs(group[rod] or {}) do
        take(slot.species)
        take(slot.day and slot.day.species)
        take(slot.nite and slot.nite.species)
      end
    end
  end

  -- headbutt and Rock Smash, but only the sets a map actually points at: a
  -- tree set nothing names is dead data, and crediting it would leave a
  -- species unplaced that no tree in the game can produce.
  local live = {}
  for _, set in pairs((tables or {}).trees or {}) do live[set] = true end
  for _, set in pairs((tables or {}).rocks or {}) do live[set] = true end
  for id, set in pairs((tables or {}).treeSets or {}) do
    if live[id] then
      for _, half in ipairs({ "common", "rare" }) do
        for _, slot in ipairs(set[half] or {}) do take(slot.species) end
      end
    end
  end

  for _, slot in ipairs((tables or {}).bugContest or {}) do take(slot.species) end

  return Build.close(have, pokemon)
end

-- Grow the set both ways: evolution up, the Day-Care down.
--
-- UP is Gen151's rule -- everything except EVOLVE_TRADE, because a trade
-- evolution is the one thing a single save cannot reach, which is why the ten
-- of them get a cable rather than a spawn.
--
-- DOWN is Gen 2's own: the engine implements breeding, so a renewable PIKACHU
-- makes PICHU renewable and six babies need no placement at all.  It is
-- barred exactly where the cartridge bars it -- a parent in no egg group lays
-- nothing, so this cannot walk a legendary's pre-evolution into the set.
function Build.close(have, pokemon)
  have = have or {}
  local changed = true
  while changed do
    changed = false
    for id, def in pairs(pokemon or {}) do
      for _, evo in ipairs(def.evolutions or {}) do
        local into = evo.into
        if into and evo.method ~= "EVOLVE_TRADE" then
          if have[id] and not have[into] then
            have[into] = true
            changed = true
          elseif have[into] and not have[id]
              and Build.breedable((pokemon or {})[into]) then
            have[id] = true
            changed = true
          end
        end
      end
    end
  end
  return have
end

-- Whether the Day-Care will ever produce an egg from this species.  Two
-- EGG_NONE halves is the cartridge's way of saying no (the legendaries, UNOWN
-- and the babies), and DITTO is a parent but never a mother -- it always
-- breeds as the other parent's species, which the caller already has.
function Build.breedable(def)
  local groups = def and def.eggGroups
  if type(groups) ~= "table" or #groups == 0 then return false end
  for _, group in ipairs(groups) do
    if group ~= "EGG_NONE" and group ~= "EGG_DITTO" then return true end
  end
  return false
end

-- ------------------------------------------------------------- the bands
--
-- SPEC 5: "Match the destination map's existing level band, not the species'
-- vanilla gift level."  Derived here rather than written into the row,
-- because the same map's band moves between cartridges -- ROUTE_45 is not the
-- same climb on Crystal that it is on Gold -- and a written level would be
-- right on one of the three.

-- The destination map's own levels, sorted and deduplicated.  Grass reads all
-- three times of day, because a map's night table is as much "the levels this
-- map runs at" as its day one, and a row placed on the strength of the day
-- band would read wrong to a player who walked in after dark.
function Build.levels(tables, mapId, method)
  local seen, out = {}, {}
  local function take(slot)
    local level = slot and slot.level
    if type(level) == "number" and level > 0 and not seen[level] then
      seen[level] = true
      out[#out + 1] = level
    end
  end
  if method == "water" then
    local entry = ((tables or {}).water or {})[mapId]
    for _, slot in ipairs((entry or {}).slots or {}) do take(slot) end
  else
    local entry = ((tables or {}).grass or {})[mapId]
    for _, daytime in ipairs(DAYTIMES) do
      for _, slot in ipairs(((entry or {}).slots or {})[daytime] or {}) do
        take(slot)
      end
    end
  end
  table.sort(out)
  return out
end

-- The third of those levels a band names.  A map with fewer than three
-- distinct levels gives the same short list to every band rather than an
-- empty one for two of them: a two-level map has no meaningful "middle", and
-- refusing to place there would silently drop the row.
function Build.band(levels, band)
  local count = #levels
  if count == 0 then return {} end
  if count < 3 then return levels end
  local third = math.floor(count / 3)
  local first, last
  if band == "low" then
    first, last = 1, third
  elseif band == "high" then
    first, last = count - third + 1, count
  else
    first, last = third + 1, count - third
  end
  local out = {}
  for i = first, last do out[#out + 1] = levels[i] end
  return #out > 0 and out or levels
end

-- ---------------------------------------------------------------- the rows
--
-- Returns { rows, skipped, unplaced }:
--
--   rows      what the roll layer installs, one per applied placement
--   skipped   placements whose species is already renewable here, with the
--             reason -- this is the version detection that never happened
--   unplaced  placements whose destination map has no table on this
--             cartridge, which is a bug in the table rather than a fact
--             about the save, so it is reported rather than swallowed
function Build.rows(placements, tables, pokemon, opts)
  opts = opts or {}
  local tiers = opts.tiers or {}
  local lineage = opts.lineage
  local have = opts.renewable or Build.renewable(tables, pokemon)

  local out = { rows = {}, skipped = {}, unplaced = {} }
  for _, row in ipairs((placements or {}).common or {}) do
    local why
    if row.lineage and row.lineage ~= lineage then
      why = "wrong lineage"
    elseif have[row.species] then
      why = "already renewable"
    end

    if why then
      out.skipped[#out.skipped + 1] = { species = row.species, why = why }
    else
      local levels = Build.band(Build.levels(tables, row.map, row.method),
                                row.band)
      local weight = tiers[row.tier]
      if #levels == 0 or not weight then
        out.unplaced[#out.unplaced + 1] = {
          species = row.species, map = row.map,
          why = #levels == 0 and "no table on this cartridge" or "no tier",
        }
      else
        out.rows[#out.rows + 1] = {
          species = row.species, map = row.map, terrain = row.method,
          weight = weight, levels = levels, feature = row.feature,
          tier = row.tier, gate = (placements.MAP_GATES or {})[row.map],
          why = row.why,
        }
      end
    end
  end
  return out
end

return Build
