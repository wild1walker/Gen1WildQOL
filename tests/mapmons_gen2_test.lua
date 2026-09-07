-- The POKeMON standing on a Gold map, and the moment their sheet is chosen.
--
-- Gold's overworld POKeMON are SPRITE_POKEMON_* records that already name a
-- species and point at that mon's PARTY MENU icon, so this mod rewrites the
-- record in place and the id maps one-to-one.  That shape was right.  The
-- TIMING was not.
--
-- The rewrite ran from the follower's onMapEntered wrapper, whose comment says
-- it goes "before the map's own objects are built".  True on Red.  On Gold
-- `Follower.onMapEntered` is called from the TAIL of `World:setMap` -- after
-- `rebuildPeople`, which is what builds the map's people -- and
-- `NPC.new(mapId, obj, spriteDef)` calls `SpriteRenderer.new` on the spot.
-- The sheet is baked at construction, so every map POKeMON was already
-- wearing the cart's icon by the time the record changed.
--
-- Which is exactly why the FOLLOWER looked right and they did not: onMapEntered
-- builds the follower, so it is the one entity made after the rewrite.
--
-- Two things are asserted here: the refresh now runs ahead of the build, and
-- the pooled NPCs a rebuild hands straight back are re-pointed behind it --
-- `World:pooledNpc` returns the same instance on a revisit and
-- `NPC:setSpriteDef` early-returns on a def it already has, which ours always
-- is.
--
-- Run:  luajit tests/mapmons_gen2_test.lua

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

-- ---- the engine's shapes, reduced to what the fix touches

local SpriteRenderer = {
  -- Baked at construction, the way NPC.new does it.
  new = function(def, id)
    return { image = def and def.image, id = id }
  end,
}

local World = {}
local built
-- The day-care pair's def is built on the fly and cached on the WORLD, not in
-- the sprite table -- their species is whatever is being bred, so there is no
-- fixed SPRITE_* row for them.
World.breedmonSpriteDef = function(world, species)
  -- An empty slot: the cart answers nil rather than a sprite, because the
  -- object's own event flag stays set until a mon is actually in there.
  if type(species) ~= "string" then return nil end
  world.breedmonSprites = world.breedmonSprites or {}
  local hit = world.breedmonSprites[species]
  if hit then return hit end
  local def = {
    id = "SPRITE_DAY_CARE_MON",
    image = "assets/generated/icons/gen2/" .. species:lower() .. ".png",
    frames = 2, walker = false,
    spriteType = "POKEMON_SPRITE", species = species,
  }
  world.breedmonSprites[species] = def
  return def
end
-- rebuildPeople's own loop: a pooled NPC comes straight back, a fresh one is
-- constructed from whatever the record says RIGHT NOW.
World.rebuildPeople = function(world)
  built = built or {}
  world.npcs = {}
  for _, obj in ipairs(world.objects) do
    local npc = world.pool[obj.key]
    if not npc then
      local def = world.sprites[obj.sprite]
      -- The shape src/world/gen2/Npc.lua really builds: the MAP OBJECT under
      -- `def`, the map id beside it, and `setSpriteDef` -- which early-returns
      -- on the table it already holds and rebuilds the renderer otherwise.
      -- The generic-sheet arm reads all three, so a stub without them would
      -- pass while the game crashed.
      npc = { id = obj.key, spriteDef = def, mapId = obj.mapId or "ROUTE_30",
              def = obj.def or { sprite = obj.sprite },
              sprite = SpriteRenderer.new(def, obj.key) }
      npc.setSpriteDef = function(self, spriteDef)
        if not spriteDef or spriteDef == self.spriteDef then return false end
        self.spriteDef = spriteDef
        self.sprite = SpriteRenderer.new(spriteDef, self.id)
        return true
      end
      world.pool[obj.key] = npc
      built[#built + 1] = "built:" .. obj.key
    else
      built[#built + 1] = "pooled:" .. obj.key
    end
    world.npcs[#world.npcs + 1] = npc
  end
end
package.loaded["src.world.gen2.World"] = World

-- ---- the shipped arm

local function shipped()
  local handle = assert(io.open("modules/Gen1Follower/main.lua"))
  local source = handle:read("*a")
  handle:close()
  local resync = source:match(
    "(  local function resyncGen2OverworldMons%(world%).-\n  end)\n")
  assert(resync, "could not find resyncGen2OverworldMons")
  local install = source:match(
    "(  local function installGen2MapMons%(%).-\n  end)\n")
  assert(install, "could not find installGen2MapMons")
  -- The generic-sheet arm the resync now calls into, lifted with it: the two
  -- tables and the two functions that read them.  Supplying stand-ins for
  -- these would let this file agree with a table it never checked, which is
  -- the whole thing tests/mapmons_gen2_generic_test.lua exists to stop.
  local sheets = source:match("(  local GEN2_GENERIC_SHEETS = {.-\n  })\n")
  assert(sheets, "could not find GEN2_GENERIC_SHEETS")
  local table_ = source:match("(  local GEN2_OVERWORLD_MON = {.-\n  })\n")
  assert(table_, "could not find GEN2_OVERWORLD_MON")
  local species = source:match(
    "(  local function gen2MapMonSpecies%(npc%).-\n  end)\n")
  assert(species, "could not find gen2MapMonSpecies")
  local monDef = source:match(
    "(  local gen2MapMonDefs = {}\n  local function gen2MapMonDef%(game, species, sheetId%).-\n  end)\n")
  assert(monDef, "could not find gen2MapMonDef")
  -- The installer also closes over the per-record rewrite and the option, so
  -- the day-care wrap can reach both.
  return assert(load(
    "local isGen2, SpriteRenderer, refreshOverworldMonDefs, repointMonDef,"
      .. " overworldMonsEnabled, TRUE_COLOR_ART, mod, dexForSpecies,"
      .. " spritesFor = ...\n"
      .. sheets .. "\n" .. table_ .. "\n" .. species .. "\n" .. monDef .. "\n"
      .. resync .. "\n" .. install .. "\nreturn installGen2MapMons, resyncGen2OverworldMons",
    "@Gen1Follower"))
end

local OUR_SHEET = "mods/assets/sprites/follower_016.png"
local CART_ICON = "assets/generated/icons/gen2/pidgey.png"

local refreshed
local enabled = true
local function refreshOverworldMonDefs(game)
  refreshed = (refreshed or 0) + 1
  built = built or {}
  built[#built + 1] = "refresh"
  for _, def in pairs(game.data.gen2Sprites) do
    if def.spriteType == "POKEMON_SPRITE" then
      def.image = enabled and OUR_SHEET or CART_ICON
    end
  end
end

-- The shipped per-record rewrite, lifted the same way, so the day-care wrap is
-- driven by the real thing rather than a stand-in.
local repointMonDef do
  local handle = assert(io.open("modules/Gen1Follower/main.lua"))
  local source = handle:read("*a")
  handle:close()
  local body = source:match(
    "(  local function repointMonDef%(id, def, enabled, trueColor, walks%).-\n  end)\n")
  assert(body, "could not find repointMonDef")
  repointMonDef = assert(load(
    "local gen2MonOriginals, dexForSpecies, assetPath, followerVisualScale = ...\n"
      .. body .. "\nreturn repointMonDef", "@Gen1Follower"))(
    {},
    function(name) return name and 1 or nil end,
    function() return OUR_SHEET end,
    function() return 1 end)
end

local installGen2MapMons, resyncGen2OverworldMons =
  shipped()(true, SpriteRenderer, refreshOverworldMonDefs, repointMonDef,
            function() return enabled end, false,
            { log = { warn = function() end } },
            function(name) return name and 1 or nil end,
            function(game) return game and game.data and game.data.gen2Sprites end)

eq(installGen2MapMons(), true, "the map POKeMON arm installs on Gold")
eq(installGen2MapMons(), true, "and a second install is a no-op")

-- ---- a route with a POKeMON and a person on it

local function scene()
  built = {}
  refreshed = 0
  local sprites = {
    SPRITE_POKEMON_PIDGEY = {
      id = "SPRITE_POKEMON_PIDGEY", spriteType = "POKEMON_SPRITE",
      species = "PIDGEY", image = CART_ICON,
    },
    SPRITE_YOUNGSTER = {
      id = "SPRITE_YOUNGSTER", spriteType = "WALKING_SPRITE",
      image = "assets/generated/sprites/youngster.png",
    },
  }
  local world = {
    sprites = sprites,
    pool = {},
    objects = {
      { key = "ROUTE_30_obj_1", sprite = "SPRITE_POKEMON_PIDGEY" },
      { key = "ROUTE_30_obj_2", sprite = "SPRITE_YOUNGSTER" },
    },
  }
  world.game = { data = { gen2Sprites = sprites } }
  return world
end

local function npcNamed(world, key)
  for _, npc in ipairs(world.npcs) do
    if npc.id == key then return npc end
  end
end

-- ---- the ordering, which is the bug

do
  local world = scene()
  World.rebuildPeople(world)
  eq(built[1], "refresh",
     "the sheets are chosen BEFORE the map's people are built")
  eq(refreshed, 1, "and chosen once per rebuild")

  local mon = npcNamed(world, "ROUTE_30_obj_1")
  eq(mon.sprite.image, OUR_SHEET,
     "so the POKeMON standing on the route wears this mod's sheet")

  local person = npcNamed(world, "ROUTE_30_obj_2")
  eq(person.sprite.image, "assets/generated/sprites/youngster.png",
     "and the YOUNGSTER beside them is untouched")
end

-- ---- a revisit, where the NPC is handed back rather than rebuilt

do
  local world = scene()
  World.rebuildPeople(world)
  local first = npcNamed(world, "ROUTE_30_obj_1")

  -- Walk away and come back: pooledNpc answers with the same instance, so
  -- nothing is constructed and NPC:setSpriteDef would refuse the def it
  -- already holds.  Put the cart's icon back on the renderer to stand for an
  -- NPC that was pooled from before the record was ours.
  first.sprite = SpriteRenderer.new({ image = CART_ICON }, first.id)
  built = {}
  World.rebuildPeople(world)

  eq(built[2], "pooled:ROUTE_30_obj_1", "the POKeMON was pooled, not rebuilt")
  eq(npcNamed(world, "ROUTE_30_obj_1"), first, "and it is the same instance")
  eq(first.sprite.image, OUR_SHEET,
     "which is re-pointed at this mod's sheet anyway")
end

-- ---- MAP POKEMON off puts the cart's icons back

do
  local world = scene()
  World.rebuildPeople(world)
  eq(npcNamed(world, "ROUTE_30_obj_1").sprite.image, OUR_SHEET, "on to begin with")

  enabled = false
  World.rebuildPeople(world)
  eq(npcNamed(world, "ROUTE_30_obj_1").sprite.image, CART_ICON,
     "OFF is the cart's own icon back, on the live POKeMON")
  enabled = true
end

-- ---- the resync alone, which is what an option flip calls

do
  local world = scene()
  World.rebuildPeople(world)
  local mon = npcNamed(world, "ROUTE_30_obj_1")
  local person = npcNamed(world, "ROUTE_30_obj_2")
  local personSprite = person.sprite

  mon.spriteDef.image = "something/else.png"
  resyncGen2OverworldMons(world)
  eq(mon.sprite.image, "something/else.png",
     "the resync follows the record it is given")
  eq(person.sprite, personSprite,
     "and does not rebuild a renderer that is not a POKeMON's")
end

do
  local world = scene()
  World.rebuildPeople(world)
  local mon = npcNamed(world, "ROUTE_30_obj_1")
  local before = mon.sprite
  resyncGen2OverworldMons(world)
  eq(mon.sprite, before,
     "a renderer already showing the right sheet is left exactly alone")
end

do
  ok(pcall(resyncGen2OverworldMons, nil) , "no world is not an error")
  ok(pcall(resyncGen2OverworldMons, {}), "and neither is a world with no people")
end

-- ---- and WHICH sprite table the mod writes into
--
-- 0.32.48 fixed the moment the records are rewritten and the POKeMON still
-- wore the cart's icons, because the rewrite was landing on the wrong TABLE.
-- A Gen 2 boot has two, holding the same data:
--
--   data.sprites       what src/core/Data.lua loads, under the Gen 1 key
--   data.gen2Sprites   what Game2 loads separately at :1044, "namespaced so
--                      nothing collides with the Gen 1 keys of the same idea"
--
-- World:dataTable("gen2Sprites", ...) and PartyMenu.new both read the SECOND,
-- so it is the one every overworld NPC and every party icon is built from.
--
-- The block above could not catch that: it stubs the refresh, so it never
-- reaches the real chooser -- and its `game.data` carries only gen2Sprites,
-- which is not the shape a real boot has.  So the shipped chooser is lifted
-- out and asked directly, with BOTH tables present, which is the case that
-- was wrong.

do
  local handle = assert(io.open("modules/Gen1Follower/main.lua"))
  local source = handle:read("*a")
  handle:close()
  local body = source:match("(  local function spritesFor%(game%).-\n  end)\n")
  assert(body, "could not find spritesFor in the module")
  local make = assert(load("local isGen2 = ...\n" .. body
    .. "\nreturn spritesFor", "@Gen1Follower"))

  local gen1Table, gen2Table = { which = "sprites" }, { which = "gen2Sprites" }
  local both = { data = { sprites = gen1Table, gen2Sprites = gen2Table } }

  local onGold = make(true)
  eq(onGold(both).which, "gen2Sprites",
     "on Gold the mod writes into the table World and PartyMenu read")

  local onRed = make(false)
  eq(onRed(both).which, "sprites", "on Red it is still the Gen 1 key")

  -- Neither arm may go blind when its own key is the one missing.
  eq(onGold({ data = { sprites = gen1Table } }).which, "sprites",
     "Gold falls back rather than finding nothing")
  eq(onRed({ data = { gen2Sprites = gen2Table } }).which, "gen2Sprites",
     "and so does Red")
  eq(onGold({ data = {} }), nil, "no table at all is nil, not an error")
  eq(onGold(nil), nil, "and neither is no game")
end

-- ---- the OTHER half: POKeMON drawn as ordinary walking sprites
--
-- The SPRITE_POKEMON_* block ($80 up) is the mon dolls, and they carry a
-- `species`.  The OverworldSprites half below $60 carries POKeMON too --
-- SUDOWOODO among them -- as plain walking sheets with no species field, and
-- those kept the cart's art.
--
-- Red needed a written table of fifty-three names because its objects share
-- five GENERIC sheets and the species is genuinely lost.  Gold's are not
-- generic and the sprite is NAMED after what it is, so the name is the answer
-- -- and asking data.pokemon whether the rest of the id is a species covers
-- every name in the cart's block without enumerating one, while never firing
-- on a person or a prop.

do
  local handle = assert(io.open("modules/Gen1Follower/main.lua"))
  local source = handle:read("*a")
  handle:close()
  local dolls = source:match("(  local BIG_DOLLS = %b{})")
  assert(dolls, "could not find BIG_DOLLS")
  local body = source:match(
    "(  local function speciesFromSpriteId%(game, id%).-\n  end)\n")
  assert(body, "could not find speciesFromSpriteId")
  local speciesFromSpriteId = assert(load(
    "local dexForSpecies = ...\n" .. dolls .. "\n" .. body
      .. "\nreturn speciesFromSpriteId", "@Gen1Follower"))(
    function(name) return name ~= "MISSINGNO" and 1 or nil end)

  local game = { data = { pokemon = {
    SUDOWOODO = {}, TAUROS = {}, LAPRAS = {}, SNORLAX = {}, ONIX = {},
    MISSINGNO = {},
  } } }

  eq(speciesFromSpriteId(game, "SPRITE_SUDOWOODO"), "SUDOWOODO",
     "a sprite named after a species IS that species")
  eq(speciesFromSpriteId(game, "SPRITE_TAUROS"), "TAUROS", "and so is another")

  -- People and props are named after neither.
  eq(speciesFromSpriteId(game, "SPRITE_YOUNGSTER"), nil,
     "a person is not a POKeMON")
  eq(speciesFromSpriteId(game, "SPRITE_POKE_BALL"), nil, "nor is a prop")
  eq(speciesFromSpriteId(game, "SPRITE_FLY_MON"), nil,
     "nor is a name that only sounds like one")

  -- The three dolls, which are the whole reason this is not a bare match.
  eq(speciesFromSpriteId(game, "SPRITE_BIG_SNORLAX"), nil,
     "the bedroom SNORLAX is a doll, not a SNORLAX")
  eq(speciesFromSpriteId(game, "SPRITE_BIG_LAPRAS"), nil, "so is the LAPRAS")
  eq(speciesFromSpriteId(game, "SPRITE_BIG_ONIX"), nil, "and the ONIX")

  -- A species this mod has no sheet for keeps the cart's art: better the
  -- cart's own than the wrong POKeMON.
  eq(speciesFromSpriteId(game, "SPRITE_MISSINGNO"), nil,
     "a species with no sheet here is left alone")

  eq(speciesFromSpriteId(game, "NOT_A_SPRITE"), nil, "a stray id is nil")
  eq(speciesFromSpriteId(game, nil), nil, "and so is no id")
  eq(speciesFromSpriteId({}, "SPRITE_SUDOWOODO"), nil,
     "and a game with no pokemon table answers nothing rather than erroring")
end

-- ---- the day-care pair, which has no row to rewrite
--
-- `World:breedmonSpriteDef` builds their def on the fly and caches it on the
-- world.  Their species is whatever is being bred, so there is no fixed
-- SPRITE_* row for them and the pass over the sprite table cannot reach one --
-- however right its timing and its table are.  The def it returns is the same
-- shape every other mon record has, so it is repointed on the way out.

do
  local world = scene()
  local def = World.breedmonSpriteDef(world, "PIDGEY")
  eq(def.image, OUR_SHEET,
     "a breedmon's def is repointed even though it is in no table")
  eq(def.species, "PIDGEY", "and still says which POKeMON it is")

  -- Cached on the world, so the second ask is the same table, already ours.
  eq(World.breedmonSpriteDef(world, "PIDGEY"), def,
     "the world's own cache still answers")
  eq(def.image, OUR_SHEET, "and it is still pointed at this mod's sheet")
end

do
  -- The saved original is keyed by SPECIES, not by the id: every breedmon
  -- shares `SPRITE_DAY_CARE_MON`, so keying on that would restore one
  -- POKeMON's cart art onto another's record the moment the pair changed.
  local world = scene()
  local first = World.breedmonSpriteDef(world, "PIDGEY")
  local second = World.breedmonSpriteDef(world, "RATTATA")
  eq(first.image, OUR_SHEET, "the first breedmon is ours")
  eq(second.image, OUR_SHEET, "and so is the one swapped in beside it")

  enabled = false
  world.breedmonSprites = nil
  local off = World.breedmonSpriteDef(world, "RATTATA")
  eq(off.image, "assets/generated/icons/gen2/rattata.png",
     "OFF is RATTATA's own cart icon back, not PIDGEY's")
  enabled = true
end

do
  local world = scene()
  eq(World.breedmonSpriteDef(world, nil), nil,
     "an empty day-care slot is still nothing")
end

-- ---- the four GENERIC sheets, where one sheet is several POKeMON
--
-- SPRITE_MONSTER carries no `species` and its name is not one either, so the
-- named arm above cannot reach it.  Two of them stand on Route 30 and are both
-- RATTATA; a third stands in the Copycat's house and is a DOLL.  The table is
-- keyed on map AND cell precisely so those come out differently.

local function genericScene()
  built = {}
  refreshed = 0
  local sprites = {
    SPRITE_MONSTER = {
      id = "SPRITE_MONSTER", spriteType = "WALKING_SPRITE",
      image = "assets/generated/sprites/monster.png", frames = 6, walker = true,
    },
  }
  local world = {
    sprites = sprites,
    pool = {},
    objects = {
      -- Route30.asm:429-430, the two Rattata of EVENT_ROUTE_30_BATTLE
      { key = "ROUTE_30_obj_6", sprite = "SPRITE_MONSTER", mapId = "ROUTE_30",
        def = { sprite = "SPRITE_MONSTER", x = 5, y = 24 } },
      { key = "ROUTE_30_obj_7", sprite = "SPRITE_MONSTER", mapId = "ROUTE_30",
        def = { sprite = "SPRITE_MONSTER", x = 5, y = 25 } },
      -- CopycatsHouse2F.asm:377, a DOLL on the same sheet
      { key = "COPYCATS_HOUSE_2F_obj_2", sprite = "SPRITE_MONSTER",
        mapId = "COPYCATS_HOUSE_2F",
        def = { sprite = "SPRITE_MONSTER", x = 2, y = 1 } },
      -- and a cell on the right map that is nobody
      { key = "ROUTE_30_obj_9", sprite = "SPRITE_MONSTER", mapId = "ROUTE_30",
        def = { sprite = "SPRITE_MONSTER", x = 11, y = 3 } },
    },
  }
  world.game = { data = { gen2Sprites = sprites } }
  return world
end

do
  local world = genericScene()
  World.rebuildPeople(world)

  local a = npcNamed(world, "ROUTE_30_obj_6")
  local b = npcNamed(world, "ROUTE_30_obj_7")
  eq(a.sprite.image, OUR_SHEET, "Route 30's first RATTATA wears this mod's sheet")
  eq(b.sprite.image, OUR_SHEET, "and so does the second")
  eq(a.spriteDef, b.spriteDef,
     "both through ONE record -- a species, not an object, owns a sheet")
  eq(a.spriteDef.species, "RATTATA", "which names the species the map gives them")
  ok(a.spriteDef ~= world.sprites.SPRITE_MONSTER,
     "and it is a clone: the cart's shared sheet is not rewritten under the doll")

  local doll = npcNamed(world, "COPYCATS_HOUSE_2F_obj_2")
  eq(doll.sprite.image, "assets/generated/sprites/monster.png",
     "the Copycat's DOLL keeps the cart's art -- it is a doll, and that is the joke")
  local nobody = npcNamed(world, "ROUTE_30_obj_9")
  eq(nobody.sprite.image, "assets/generated/sprites/monster.png",
     "and a cell no row names is left alone on the right map too")
end

-- MAP POKeMON off has to reach these as well: they are a def swap rather than
-- a record rewrite, so the OFF path above cannot put them back on its own.
do
  local world = genericScene()
  World.rebuildPeople(world)
  eq(npcNamed(world, "ROUTE_30_obj_6").sprite.image, OUR_SHEET, "on to begin with")

  enabled = false
  resyncGen2OverworldMons(world)
  eq(npcNamed(world, "ROUTE_30_obj_6").sprite.image,
     "assets/generated/sprites/monster.png",
     "OFF puts the cart's generic sheet back on a live map POKeMON")
  enabled = true
  resyncGen2OverworldMons(world)
  eq(npcNamed(world, "ROUTE_30_obj_6").sprite.image, OUR_SHEET, "and ON returns it")
end

io.write(("mapmons_gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
