-- Gold's four GENERIC creature sheets, and the nine POKeMON standing on them.
--
-- The Gen 2 arm of MAP POKeMON was built on a claim that turned out to be
-- false -- written into its own comment: "Gold's are not generic -- each has
-- its own sheet -- and the sprite is NAMED after what it is".  Gold carries
-- the same four generic sheets Red does (spriteOrder [76]-[79]):
--
--     SPRITE_MONSTER   SPRITE_FAIRY   SPRITE_BIRD   SPRITE_DRAGON
--
-- They sit BELOW the SPRITE_POKEMON block, so the extractor gives them no
-- `species`, and their names are not species either -- so every POKeMON on one
-- kept the cart's art.  One sheet really does serve several species:
-- SPRITE_MONSTER is Joey's RATTATA on Route 30 and Jasmine's AMPHAROS in the
-- lighthouse.
--
-- So the fix is a written table, and a written table is exactly the thing that
-- rots.  This file checks it against the CART's own data rather than against
-- itself:
--
--   * the four sheet ids are read out of `tools/rom_manifest_crystal.json`'s
--     spriteOrder, so a rename upstream fails here;
--   * every species named is checked against that manifest's speciesOrder;
--   * every map id is checked against its mapOrder;
--   * and the row count is pinned, so an object added without a species -- or
--     a doll quietly promoted into the table -- has to be looked at.
--
-- The rows themselves were read off pret/pokecrystal's maps/*.asm.  What this
-- cannot check is that Route 30's cell (5,24) really is a Rattata; that is in
-- the commit message, with the script label that says so.
--
-- Run:  luajit tests/mapmons_gen2_generic_test.lua
--       (needs an engine tree for the manifest; SKIPs without one)

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
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    candidates[#candidates + 1] = prefix .. "/gen1recomp"
    candidates[#candidates + 1] = prefix .. "/bryanthaboi/gen1recomp"
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/tools/rom_manifest_crystal.json")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("mapmons_gen2_generic: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end

local function slurp(path)
  local handle = assert(io.open(path), path)
  local text = handle:read("*a")
  handle:close()
  return text
end

-- ---- the cart's own lists, scraped out of the manifest
--
-- A whole JSON parser would be a dependency for three arrays; each of these is
-- a flat list of quoted strings under its own key, so the key is found and the
-- strings up to the closing bracket are taken.

local manifest = slurp(ENGINE .. "/tools/rom_manifest_crystal.json")
local function listOf(key)
  local body = manifest:match('"' .. key .. '"%s*:%s*%[(.-)%]')
  assert(body, key .. " not found in rom_manifest_crystal.json")
  local out, seen = {}, {}
  for name in body:gmatch('"([^"]*)"') do
    out[#out + 1] = name
    seen[name] = true
  end
  return out, seen
end
local spriteList, spriteSet = listOf("spriteOrder")
local _, speciesSet = listOf("speciesOrder")
local _, mapSet = listOf("mapOrder")
ok(#spriteList > 100, "the manifest's sprite table was read")

-- ---- the shipped table

local source = slurp("modules/Gen1Follower/main.lua")

local sheets = {}
do
  local body = source:match("local GEN2_GENERIC_SHEETS = {(.-)}")
  assert(body, "GEN2_GENERIC_SHEETS not found in Gen1Follower/main.lua")
  for name in body:gmatch("(SPRITE_[%u_]+)%s*=%s*true") do sheets[#sheets + 1] = name end
end

local rows, byMap = {}, {}
do
  local body = source:match("local GEN2_OVERWORLD_MON = {(.-)\n  }")
  assert(body, "GEN2_OVERWORLD_MON not found in Gen1Follower/main.lua")
  local map
  for line in body:gmatch("[^\n]+") do
    local name = line:match("^%s*([%u][%u%d_]*)%s*=")
    if name then map = name; byMap[map] = byMap[map] or 0 end
    local x, y, sheet, species =
      line:match("{%s*(%d+)%s*,%s*(%d+)%s*,%s*\"(SPRITE_[%u_]+)\"%s*,%s*\"([%u%d_]+)\"%s*}")
    if x then
      rows[#rows + 1] = { map = map, x = tonumber(x), y = tonumber(y),
                          sheet = sheet, species = species }
      byMap[map] = (byMap[map] or 0) + 1
    end
  end
end

-- ---- the four sheets are the cart's, by name

eq(#sheets, 4, "four generic creature sheets are named")
for _, id in ipairs(sheets) do
  ok(spriteSet[id], id .. " is a sprite the cart actually has")
end
-- And they sit below the mon block, which is WHY they carry no species and
-- why this table has to exist at all.
local firstMon = tonumber(manifest:match('"spritePokemon"%s*:%s*(%d+)'))
ok(firstMon ~= nil, "the manifest names where the mon block starts")
for _, id in ipairs(sheets) do
  local at
  for i, name in ipairs(spriteList) do if name == id then at = i break end end
  ok(at and firstMon and at < firstMon,
     id .. " is below the SPRITE_POKEMON block, so it carries no species")
end

-- ---- every row names a real map and a real species

eq(#rows, 9, "nine POKeMON stand on those four sheets")
for _, row in ipairs(rows) do
  local where = ("%s (%d,%d)"):format(row.map, row.x, row.y)
  ok(mapSet[row.map], where .. ": the map id is one the cart has")
  ok(speciesSet[row.species], where .. ": " .. row.species .. " is a real species")
  local named = false
  for _, id in ipairs(sheets) do if id == row.sheet then named = true end end
  ok(named, where .. ": " .. row.sheet .. " is one of the four")
end

-- ---- the shape of the answer, pinned
--
-- Thirteen objects in the game use these sheets.  Nine are POKeMON and four
-- are DOLLS -- three in the Copycat's house, one in the Fan Club -- and the
-- dolls are deliberately absent.  If a later pass adds rows, this is the
-- assertion that asks whether a doll just got promoted.

eq(byMap.ROUTE_30, 2, "Route 30's two battling POKeMON are both here")
eq(byMap.MOUNT_MOON_SQUARE, 2, "and both Mt Moon Square CLEFAIRY")
ok(byMap.COPYCATS_HOUSE_2F == nil, "the Copycat's three dolls are NOT here")
ok(byMap.POKEMON_FAN_CLUB == nil, "and neither is the Fan Club's CLEFAIRY doll")

-- One sheet, two species -- the case the name half could never have covered,
-- and the reason a per-object table is needed rather than a per-sheet rewrite.
local monsterSpecies = {}
for _, row in ipairs(rows) do
  if row.sheet == "SPRITE_MONSTER" then monsterSpecies[row.species] = true end
end
ok(monsterSpecies.RATTATA and monsterSpecies.AMPHAROS,
   "SPRITE_MONSTER is RATTATA in one place and AMPHAROS in another")

-- ---- and the arm that uses it is wired in

ok(source:find("gen2MapMonSpecies(npc)", 1, true) ~= nil,
   "the resync asks for a map POKeMON's species")
ok(source:find("npc.pokepcVanillaSpriteDef", 1, true) ~= nil,
   "and remembers the cart's def, so the option can go back off")

io.write(("mapmons_gen2_generic: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
