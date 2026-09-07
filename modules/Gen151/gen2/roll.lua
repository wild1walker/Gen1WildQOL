-- The Gen 2 substitution roll.
--
-- One stage fewer than Gen151's two, because Gold leaves no room for the
-- other one.  Its grass slot comes off a fixed seven-entry probability ladder
-- (src/battle/gen2/Encounter.lua:52), so an appended eighth slot can never be
-- drawn -- which means stage one here is not "vanilla against a trimmed
-- table", it is vanilla, untouched, against the cartridge's own table.  The
-- encounter rate is never read and steps-to-encounter is bit-identical to a
-- clean install.
--
-- Stage two is the substitution: once the cartridge has produced an
-- encounter, ONE independent draw decides whether a placed species stands in
-- for it.  Probability is conserved -- the cost comes out of the vanilla
-- species' share, and the size of that cost is the rarity tier the placement
-- declared.
--
-- The load-bearing property, tested in tests/gen251roll_test.lua: a map with
-- no rows, or whose rows all weigh zero, draws NO extra random numbers.  The
-- RNG stream is then identical to vanilla draw for draw, which is what makes
-- the zero-rarity case a real regression test rather than a distribution
-- approximation.
--
-- Pure Lua, no love.* and no engine require.

local Roll = {}
Roll.__index = Roll

-- rarity weights are parts per RARITY_SCALE of the encounters on that map
Roll.RARITY_SCALE = 10000

function Roll.new()
  return setmetatable({ maps = {} }, Roll)
end

-- Gold rolls three kinds and this layer sees two: "water" is surfing, and
-- everything else -- grass, caves, towers, the Ruins -- reads the grass
-- table, exactly as Gen 1's "indoor" path does.
local function bucketFor(terrain)
  return terrain == "water" and "water" or "grass"
end

Roll.bucketFor = bucketFor

-- row: { species, levels, weight, active = fn? }
--
-- `active` is how a row can be gated on an event flag without being added and
-- removed: the row stays in the table and answers for itself.
function Roll:add(mapId, terrain, row)
  local byMap = self.maps[mapId]
  if not byMap then
    byMap = {}
    self.maps[mapId] = byMap
  end
  local kind = bucketFor(terrain)
  local rows = byMap[kind]
  if not rows then
    rows = {}
    byMap[kind] = rows
  end
  rows[#rows + 1] = row
  return row
end

function Roll:rows(mapId, terrain)
  local byMap = self.maps[mapId]
  return byMap and byMap[bucketFor(terrain)] or nil
end

local function activeTotal(rows)
  local total = 0
  for i = 1, #rows do
    local row = rows[i]
    if (row.weight or 0) > 0 and (not row.active or row.active()) then
      total = total + row.weight
    end
  end
  return total
end

-- Which row a draw lands on, and at what level.
--
-- The level comes out of the SAME draw rather than a second one: a row
-- carries the destination map's whole band, and the offset inside the row's
-- own window picks among them.  Reusing the entropy is what keeps the promise
-- that a map with nothing to substitute costs exactly zero extra draws -- a
-- second draw for the level would have made that "zero or one, depending".
local function pickRow(rows, pick)
  local acc = 0
  for i = 1, #rows do
    local row = rows[i]
    if (row.weight or 0) > 0 and (not row.active or row.active()) then
      local start = acc
      acc = acc + row.weight
      if pick < acc then
        local levels = row.levels
        local level = row.level
        if not level and levels and #levels > 0 then
          level = levels[1 + ((pick - start) % #levels)]
        end
        return { species = row.species, level = level }
      end
    end
  end
  return nil
end

Roll.pickRow = pickRow
Roll.activeTotal = activeTotal

-- vanilla(tables, ctx) is the rest of the hook chain, ending in Gold's own
-- roll.  ctx is what src/world/gen2/World.lua:4257 builds: mapId, terrain,
-- kind, daytime, environment, tables, data.
function Roll:roll(vanilla, tables, ctx, rng)
  local enc = vanilla(tables, ctx)
  if not enc then return nil end

  local byMap = self.maps[ctx and ctx.mapId]
  local rows = byMap and byMap[bucketFor(ctx and ctx.terrain)]
  if not rows then return enc end

  -- Sum before drawing: an all-zero map must not touch the stream.
  if activeTotal(rows) <= 0 then return enc end

  local substitute = pickRow(rows, rng(0, Roll.RARITY_SCALE - 1))
  if not substitute then return enc end

  -- The encounter Gold built is kept and edited rather than replaced: it
  -- carries the slot index the roll landed on, and other listeners on this
  -- hook -- the caught marker, a swarm mod -- read fields this layer has no
  -- business dropping.
  enc.species = substitute.species
  if substitute.level then enc.level = substitute.level end
  return enc
end

return Roll
