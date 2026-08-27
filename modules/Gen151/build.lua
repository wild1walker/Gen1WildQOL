-- Turn placements.lua into roll rows and slot appends (SPEC 3c, 4, 5).
--
-- Pure Lua: everything here takes a `source` -- four small readers over the
-- content registries -- and gives back plain values, so tests can drive it
-- with no engine and no love.*.  main.lua does the wiring; this file does the
-- deciding.
--
-- Reading through the registries rather than through a data table is not
-- ceremony: mod.content.<name>:each() enumerates the BASE table's ids as well
-- as the registered ones, so it is the documented way to ask what vanilla
-- contains, it needs no permission, and it works the same under the headless
-- loader as it does in the game.
--
-- The one rule worth stating up front, because it replaces a whole feature
-- nobody would have enjoyed maintaining: a placement is applied only when its
-- species has NO renewable source in the tables actually merged on this
-- install.  That is the same question tools/gapset.py asked to derive the
-- rows, so it needs no version detection -- Blue's Ekans rows simply do not
-- fire on Red, where Ekans is already in the grass -- and it means a species
-- some other encounter mod already provided is left alone rather than
-- provided twice.

local Build = {}

local KINDS = { "grass", "water" }

-- ------------------------------------------------------------ renewability

-- Every species reachable from a table that can be rolled again tomorrow.
-- Statics, gifts, NPC trades and Game Corner prizes are deliberately NOT in
-- here: "obtainable" is not the bar, "renewable" is (SPEC 0).
function Build.renewable(source)
  local have = {}
  for _, record in source.eachEncounter() do
    for _, kind in ipairs(KINDS) do
      local group = record[kind]
      if group and (group.rate or 0) > 0 then
        for _, slot in ipairs(group.slots or {}) do
          have[slot.species] = true
        end
      end
    end
  end
  -- the rods, through field.fishing's three shapes: `always` (Old Rod),
  -- `pool` (Good Rod), `perMap` (Super Rod, via the named field key)
  for _, def in pairs(source.field("fishing") or {}) do
    if def.always and def.always.species then have[def.always.species] = true end
    for _, slot in ipairs(def.pool or {}) do have[slot.species] = true end
    if def.perMap then
      for _, group in pairs(source.field(def.perMap) or {}) do
        for _, slot in ipairs(group) do have[slot.species] = true end
      end
    end
  end
  -- ...and the closure over evolution, EXCEPT trade.  A trade evolution is
  -- precisely the thing that is not reachable in a single save, which is why
  -- Alakazam, Machamp, Golem and Gengar need an item rather than a spawn.
  local species = {}
  for id, def in source.eachPokemon() do species[id] = def end
  local changed = true
  while changed do
    changed = false
    for id, def in pairs(species) do
      if have[id] then
        for _, evo in ipairs(def.evolutions or {}) do
          if evo.method ~= "TRADE" and evo.species and not have[evo.species] then
            have[evo.species] = true
            changed = true
          end
        end
      end
    end
  end
  return have
end

-- ------------------------------------------------------------------ levels

-- SPEC 5: "Read the map's existing slots and place inside their range."
-- A band of "low" / "mid" / "high" takes that third of the map's own distinct
-- levels, so one row lands correctly on all three versions -- whose bands for
-- the same map differ by as much as twenty levels.
function Build.bandLevels(levels, band)
  local sorted = {}
  local seen = {}
  for _, level in ipairs(levels) do
    if not seen[level] then
      seen[level] = true
      sorted[#sorted + 1] = level
    end
  end
  table.sort(sorted)
  local n = #sorted
  if n == 0 then return nil end
  if not band or n < 3 then return sorted end
  local third = math.floor(n / 3)
  if third < 1 then third = 1 end
  local out = {}
  local from, to
  if band == "low" then
    from, to = 1, third
  elseif band == "high" then
    from, to = n - third + 1, n
  else
    from, to = third + 1, n - third
    if from > to then from, to = 1, n end
  end
  for i = from, to do out[#out + 1] = sorted[i] end
  return out
end

local function levelsOfGroup(group)
  local out = {}
  for _, slot in ipairs(group.slots or group or {}) do
    out[#out + 1] = slot.level
  end
  return out
end

-- Explicit levels are the DONOR cartridge's, and the donor did not
-- necessarily agree with this one about how strong that route is: Yellow's
-- Route 9 runs 16-20 where Red's runs 11-17, so Red's level-11 Ekans would
-- arrive on Yellow a full evolution behind its neighbours.  SPEC 5 is
-- explicit that the DESTINATION map's band wins, so a donor level outside it
-- clamps to the nearest end.  The spread the donor chose survives wherever it
-- fits, which is most of the time; where it does not, the row still reads as
-- a resident of the route it is on.
local function clampToBand(levels, group)
  local band = levelsOfGroup(group)
  if #band == 0 or not levels then return levels end
  local lo, hi = band[1], band[1]
  for _, level in ipairs(band) do
    if level < lo then lo = level end
    if level > hi then hi = level end
  end
  local out, seen = {}, {}
  for _, level in ipairs(levels) do
    local clamped = level
    if clamped < lo then clamped = lo end
    if clamped > hi then clamped = hi end
    if not seen[clamped] then
      seen[clamped] = true
      out[#out + 1] = clamped
    end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------- resolving

local function groupFor(source, mapId, method)
  local record = source.encounter(mapId)
  if not record then return nil, "no encounter table" end
  local group = record[method == "water" and "water" or "grass"]
  if not group then return nil, "no " .. method .. " table" end
  if (group.rate or 0) == 0 then
    -- Red and Blue give only Routes 19, 20 and 21 a live surf rate; every
    -- other water table is rate 0, so a slot there could never be rolled.
    -- Raising the rate is not on the table -- it is the one thing the
    -- divergence budget does not cover -- so this is a real placement bug and
    -- says so rather than failing silently.
    return nil, method .. " rate is 0 on this version"
  end
  return group
end

local function rodPool(source, mapId, rod)
  local def = (source.field("fishing") or {})[rod]
  if not def then return nil, "no " .. rod .. " definition" end
  if def.pool then return def.pool end
  if def.perMap then
    local group = (source.field(def.perMap) or {})[mapId]
    if not group then return nil, "no " .. rod .. " group on this map" end
    return group
  end
  if def.always then return { def.always } end
  return nil, rod .. " has no pool"
end

-- opts: { features = { [name] = bool }, multiplier = percent, rarity = <module>,
--         gated = { [name] = function() -> bool } }
--
-- Returns { rows, fishing, appends, skipped, warnings }.
--   rows      -> { map, method, species, levels, weight, ... } for the roll layer
--   appends   -> mapId -> { grass = { slot, ... }, water = { ... } }, the
--                data-layer rows that make AREA work (SPEC 6a)
--   skipped   -> rows not applied, with the reason, for the log and the tests
function Build.resolve(placements, source, opts)
  local rarity = opts.rarity
  local have = Build.renewable(source)
  local out = { rows = {}, fishing = {}, appends = {}, skipped = {},
                warnings = {} }

  local function featureOn(row)
    local feature = row.feature
    return feature == nil or opts.features[feature] == true
  end

  local function levelsFor(row, group)
    if row.levels and #row.levels > 0 then
      return clampToBand(row.levels, group)
    end
    return Build.bandLevels(levelsOfGroup(group), row.band)
  end

  -- The destination map's own encounter rate, out of 256.  A tier is a
  -- promise about how long the hunt is, and the hunt is steps rather than
  -- encounters -- so the same share costs nearly twice as much on an 8/256
  -- route as on a 15/256 one.  This is what lets the share be re-solved per
  -- map so the promise holds wherever a row lands.
  local function rateOf(row)
    if row.rod then return nil end   -- a rod has its own bite roll
    local record = source.encounter(row.map)
    local group = record
      and record[row.method == "water" and "water" or "grass"]
    local rate = group and group.rate
    if type(rate) ~= "number" or rate <= 0 then return nil end
    return rate
  end

  local function consider(row, kind)
    if not featureOn(row) then
      out.skipped[#out.skipped + 1] =
        { row = row, why = "feature " .. tostring(row.feature) .. " is off" }
      return nil
    end
    if have[row.species] then
      out.skipped[#out.skipped + 1] =
        { row = row, why = "already renewable on this install" }
      return nil
    end
    local weight, capped =
      rarity.weightForRate(row.tier, opts.multiplier, rateOf(row))
    if not weight then
      out.warnings[#out.warnings + 1] =
        ("%s: unknown rarity tier %s"):format(row.species, tostring(row.tier))
      return nil
    end
    return weight, capped
  end

  for _, row in ipairs(placements.common) do
    local weight, capped = consider(row)
    if weight then
      local group, why = groupFor(source, row.map, row.method)
      if not group then
        out.warnings[#out.warnings + 1] =
          ("%s on %s: %s"):format(row.species, row.map, why)
      else
        local levels = levelsFor(row, group)
        out.rows[#out.rows + 1] = {
          species = row.species, map = row.map, method = row.method,
          levels = levels, weight = weight, tier = row.tier, capped = capped,
          feature = row.feature, gated = row.gated, why = row.why,
          gate = row.gate or placements.MAP_GATES[row.map],
          vanillaCount = #(group.slots or {}),
        }
      end
    end
  end

  for _, row in ipairs(placements.gapFill) do
    local weight, capped = consider(row)
    if weight then
      local group, why = groupFor(source, row.map, row.method)
      if not group then
        out.warnings[#out.warnings + 1] =
          ("%s on %s: %s"):format(row.species, row.map, why)
      else
        out.rows[#out.rows + 1] = {
          species = row.species, map = row.map, method = row.method,
          levels = levelsFor(row, group), weight = weight, tier = row.tier,
          capped = capped, feature = row.feature, why = row.why,
          gate = row.gate or placements.MAP_GATES[row.map],
          vanillaCount = #(group.slots or {}),
        }
      end
    end
  end

  for _, row in ipairs(placements.fishing) do
    local weight, capped = consider(row)
    if weight then
      local pool, why = rodPool(source, row.map, row.rod)
      if not pool then
        out.warnings[#out.warnings + 1] =
          ("%s on %s: %s"):format(row.species, row.map, why)
      else
        out.fishing[#out.fishing + 1] = {
          species = row.species, map = row.map, rod = row.rod,
          levels = row.levels and clampToBand(row.levels, pool)
            or Build.bandLevels(levelsOfGroup(pool), row.band),
          weight = weight, tier = row.tier, feature = row.feature,
          why = row.why, gate = row.gate or placements.MAP_GATES[row.map],
        }
      end
    end
  end

  -- ------------------------------------------------- the per-map ceiling
  --
  -- The per-row ceiling holds one placement to vanilla's ninth slot, but a
  -- map with six of them can still end up a third mod content -- Pokemon
  -- Mansion B1F did, at 34%.  Prime directive 1 survives that (no vanilla
  -- slot moved), and the map still stops being itself, which is the same
  -- complaint by a different route.
  --
  -- So a map gives away at most a quarter of its encounters, and where the
  -- rows on one would exceed that they are ALL scaled down by the same
  -- factor: the ladder between them is a deliberate ordering and a ceiling
  -- has no business flattening it.  The player's own RARITY % scales the
  -- ceiling with it, so somebody who asked for triple rates still gets them.
  do
    local ceiling = math.floor(rarity.MAP_CEILING
      * (opts.multiplier or 100) / 100 + 0.5)
    local byMap = {}
    for _, row in ipairs(out.rows) do
      local key = row.map .. "|" .. row.method
      byMap[key] = (byMap[key] or 0) + row.weight
    end
    for _, row in ipairs(out.rows) do
      local key = row.map .. "|" .. row.method
      local total = byMap[key]
      if total > ceiling and total > 0 then
        row.weight = math.max(1, math.floor(row.weight * ceiling / total))
        row.crowded = true
      end
    end
  end

  -- The data layer: one appended slot per (map, method, species), never a
  -- bare `slots = {...}` list and never a `buckets` key.  These are what the
  -- AREA screen scans, so they are the hint system for everything except the
  -- Super Rod rows -- which is exactly why the Super Rod rows get an explicit
  -- FIELD NOTES entry instead.
  --
  -- A gated row (Mew) is deliberately NOT appended here: it is added at
  -- runtime when its flag flips, so opening the dex before the gate cannot
  -- spoil the location.
  local seen = {}
  for _, row in ipairs(out.rows) do
    if not row.gated then
      local key = row.map .. "|" .. row.method .. "|" .. row.species
      if not seen[key] then
        seen[key] = true
        local byMap = out.appends[row.map]
        if not byMap then
          byMap = {}
          out.appends[row.map] = byMap
        end
        local kind = row.method == "water" and "water" or "grass"
        byMap[kind] = byMap[kind] or {}
        byMap[kind][#byMap[kind] + 1] =
          { species = row.species, level = row.levels[1] }
      end
    end
  end

  return out
end

return Build
