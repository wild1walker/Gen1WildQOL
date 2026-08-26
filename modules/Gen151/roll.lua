-- The two-stage encounter roll (SPEC 3c).
--
-- Stage one is vanilla, exactly: the engine's own Encounter.roll runs against
-- the map's ORIGINAL slots, using the engine's own bucket list.  The encounter
-- rate is never touched, so steps-to-encounter is bit-identical to a clean
-- install, and the appended slots are unreachable from here by construction.
--
-- Stage two is substitution: once stage one has produced an encounter, one
-- independent draw decides whether a Gen151 species stands in for it.  This is
-- where the divergence budget is spent, and it is spent visibly -- probability
-- is conserved, the cost comes out of the vanilla species' share, and the size
-- of that cost is the rarity tier the placement declared.
--
-- Two properties are load-bearing and both are tested in tests/:
--
--   * a map with no additions, or whose additions all weigh zero, draws NO
--     extra random numbers.  The RNG stream is then identical to vanilla,
--     draw for draw, which is what makes the zero-rarity regression test a
--     real test rather than a distribution approximation.
--   * `buckets` is never read.  Another mod appending slots and shipping its
--     own bucket list cannot make this roll fall off the end of a table --
--     the failure mode that returns "no encounter" with no error anywhere.
--
-- Pure Lua, no love.* and no engine require, so tests/roll_test.lua drives it
-- directly against the real src/world/Encounter.lua.

local Roll = {}
Roll.__index = Roll

-- rarity weights are parts per RARITY_SCALE of the encounters on that map
Roll.RARITY_SCALE = 10000

function Roll.new()
  return setmetatable({ maps = {} }, Roll)
end

local function bucketFor(terrain)
  -- "indoor" is the caves/towers/Mansion path, which rolls the GRASS table
  -- (OverworldController: the indoor branch passes the whole encDef through)
  return terrain == "water" and "water" or "grass"
end

Roll.bucketFor = bucketFor

-- The map's vanilla slot count, recorded before any Gen151 patch lands.  A
-- map we never record stays completely untouched: `roll` hands it straight to
-- the next link, foreign bucket lists and all, because a table we did not
-- append to is none of our business.
function Roll:setVanillaCount(mapId, terrain, count)
  local kind = bucketFor(terrain)
  local byMap = self.maps[mapId]
  if not byMap then
    byMap = {}
    self.maps[mapId] = byMap
  end
  local entry = byMap[kind]
  if not entry then
    entry = { rows = {}, trimCache = {} }
    byMap[kind] = entry
  end
  entry.count = count
  return entry
end

-- row: { species, level, weight, active = fn? }
-- `active` is how the Mew gate keeps its species out of the roll until the
-- event flag flips, without the row having to be added and removed.
function Roll:add(mapId, terrain, row)
  local entry = self:setVanillaCount(mapId, terrain,
    (self.maps[mapId] and self.maps[mapId][bucketFor(terrain)] or {}).count)
  entry.rows[#entry.rows + 1] = row
  return row
end

function Roll:rows(mapId, terrain)
  local byMap = self.maps[mapId]
  local entry = byMap and byMap[bucketFor(terrain)]
  return entry and entry.rows or nil
end

-- A def carrying only the vanilla slots and no bucket list.  Cached on the
-- slots table identity, so the steady state allocates nothing: data.encounters
-- is stable after the merge, and the Mew gate only ever touches the appended
-- region, which is not in here.
local function trimmed(entry, encDef)
  local group = encDef and encDef.grass
  local slots = group and group.slots
  if not slots then return encDef end
  local hit = entry.trimCache[slots]
  if hit then return hit end
  local count = entry.count or #slots
  local kept = {}
  for i = 1, math.min(count, #slots) do kept[i] = slots[i] end
  -- deliberately no `buckets` key: stage one uses the engine's own list
  local def = { grass = { rate = group.rate, slots = kept } }
  entry.trimCache[slots] = def
  return def
end

Roll.trimmed = trimmed

-- Which row a draw lands on, and at what level.
--
-- The level comes out of the SAME draw rather than a second one: a row carries
-- the donor table's whole level spread (SPEC 5, "match the destination map's
-- existing level band"), and the offset inside the row's own window picks
-- among them.  Reusing the entropy keeps the promise that a map with nothing
-- to substitute costs exactly zero extra draws -- a second draw for the level
-- would have made that "zero or one, depending".
local function pickRow(rows, pick)
  local acc = 0
  for i = 1, #rows do
    local row = rows[i]
    if row.weight > 0 and (not row.active or row.active()) then
      local start = acc
      acc = acc + row.weight
      if pick < acc then
        local level = row.level
        if not level and row.levels and #row.levels > 0 then
          level = row.levels[1 + ((pick - start) % #row.levels)]
        end
        return { species = row.species, level = level }
      end
    end
  end
  return nil
end

local function activeTotal(rows)
  local total = 0
  for i = 1, #rows do
    local row = rows[i]
    if row.weight > 0 and (not row.active or row.active()) then
      total = total + row.weight
    end
  end
  return total
end

-- vanilla(def, ctx) is the rest of the hook chain, ending in Encounter.roll.
function Roll:roll(vanilla, encDef, ctx, rng)
  local byMap = self.maps[ctx and ctx.mapId]
  local entry = byMap and byMap[bucketFor(ctx and ctx.terrain)]
  if not entry then return vanilla(encDef, ctx) end

  -- stage one -- vanilla, exactly
  local enc = vanilla(trimmed(entry, encDef), ctx)
  if not enc then return nil end

  -- stage two -- substitution.  Sum first: an all-zero map must not draw.
  if activeTotal(entry.rows) <= 0 then return enc end
  return pickRow(entry.rows, rng(0, Roll.RARITY_SCALE - 1)) or enc
end

-- The Super Rod peer.  The fishing chain hands over the map's candidate list
-- and the vanilla link rolls the bite; substitution happens after, on the same
-- terms, so the bite odds (size/(size+4), engine mechanics) never move.
--
-- Appending to a Super Rod group would not work anyway: rollFishingGroup picks
-- `floor(r/2) % 4`, so a fifth entry in a group is unreachable.  Substitution
-- is the only honest way in.
function Roll:fish(vanilla, rod, mapId, pool, rng)
  local enc = vanilla(rod, mapId, pool)
  if not enc then return nil end
  local byRod = self.fishing and self.fishing[mapId]
  local rows = byRod and byRod[rod]
  if not rows then return enc end
  if activeTotal(rows) <= 0 then return enc end
  return pickRow(rows, rng(0, Roll.RARITY_SCALE - 1)) or enc
end

function Roll:addFishing(mapId, rod, row)
  self.fishing = self.fishing or {}
  local byMap = self.fishing[mapId]
  if not byMap then
    byMap = {}
    self.fishing[mapId] = byMap
  end
  local rows = byMap[rod]
  if not rows then
    rows = {}
    byMap[rod] = rows
  end
  rows[#rows + 1] = row
  return row
end

return Roll
