-- The statics, retryable until they are caught.
--
-- Vanilla's rule is the same cruelty it is in Red: a static is not a rare
-- encounter, it is a saving throw.  Knock LUGIA out by accident, or panic and
-- run, and that species is gone from the file forever.  The countermeasure
-- players actually use is to save in front of it and reset on a bad outcome,
-- which is not a mechanic, it is a workaround for one.
--
-- Gen151 fixes this by clearing EVENT_BEAT_<SPECIES> and putting the object
-- back.  That is exactly what NOT to do here, and finding out why is most of
-- what this file knows.
--
-- ------- why the flag is never touched
--
-- Gen 1's EVENT_BEAT_* flags mean one thing.  Gen 2's EVENT_FOUGHT_* flags
-- are load-bearing for unrelated progression:
--
--   EVENT_FOUGHT_SUDOWOODO   the GOLDENROD flower shop and the ROUTE 35 gate
--   EVENT_FOUGHT_SNORLAX     a VICTORY ROAD GATE object, and IRWIN's gossip
--   EVENT_FOUGHT_SUICUNE     the WISE TRIO and the TIN TOWER entrance --
--                            which is to say HO-OH's entire chain
--   EVENT_FOUGHT_HO_OH       four separate reads in TIN TOWER 1F
--
-- Clearing EVENT_FOUGHT_SUICUNE to give a player their SUICUNE back could
-- take HO-OH away from them.  So nothing here writes an event flag at all.
--
-- ------- what it does instead
--
-- Each static's object carries its OWN visibility flag, which is what
-- `disappear` sets and what World:appearObject clears
-- (src/world/gen2/World.lua:1932) -- separate from the FOUGHT flag entirely.
-- The map's MAPCALLBACK_OBJECTS hides the object again on every load, reading
-- the FOUGHT flag; this puts it back afterwards, on every entry, reading
-- whether the player actually owns the species.
--
-- So the flag stays set, every script that depends on it keeps its answer,
-- and the bird is standing on its perch again.  It is idempotent by
-- construction: it can run on every map entry forever and do nothing until
-- there is something to do, and it quietly repairs a save that lost one
-- before this mod was installed.
--
-- ------- SUDOWOODO, and the claim that was wrong about it
--
-- This file used to exclude SUDOWOODO, on the grounds that Route 36 runs
-- `variablesprite SPRITE_WEIRD_TREE, SPRITE_TWIN` after the battle, so what
-- came back would be a twin carrying a twin's script.  Half of that is true
-- and the important half is not.  The engine's own note on the command:
--
--     the sheet changes and NOTHING else does ... the object STRUCT is never
--     touched, so its coordinates, its facing, its FROZEN_F and its identity
--     as wLastTalked all survive.       src/world/gen2/Npc.lua:274
--
-- The object keeps SudowoodoScript, and that script checks ONE thing --
-- whether the player is carrying the SQUIRTBOTTLE.  It never reads
-- EVENT_FOUGHT_SUDOWOODO.  So a restored tree is a restored encounter, and
-- the only thing the swapped sheet costs is that it looks wrong.
--
-- Which is worth fixing anyway, so the sprite slot is reverted too: the
-- object's `sprite` field is the literal 244 ($f4 SPRITE_WEIRD_TREE), a slot
-- id rather than a sheet, so what it draws is whatever wVariableSprites[4]
-- holds.  Putting back the value the map started with puts the tree back.
--
-- ------- SUICUNE, which needed a different answer entirely
--
-- Crystal's SUICUNE is the one static that genuinely cannot be un-hidden.
-- Its object script is `ObjectEvent`, the generic do-nothing: the battle
-- lives in TinTower1FSuicuneBattleScript, reached from a map SCENE, and the
-- callback that would re-appear the object is behind
-- `checkevent EVENT_GOT_RAINBOW_WING` -- so for any player who has gone on to
-- HO-OH, the scene can never run again no matter what is restored.
--
-- So it is not restored.  It is put back where GOLD and SILVER keep it: the
-- roamers.  Crystal seeds only RAIKOU and ENTEI
-- (src/core/gen2/Roamers.lua:74), but the roam machinery is not two beasts
-- wide -- CheckEncounterRoamMon picks `value % 4`, so slots 1, 2 and 3 are
-- all live -- and a third slot is the same code path the other two already
-- run.  A Crystal player who lost SUICUNE gets it roaming Johto, exactly as
-- the other two cartridges would have given it to them.

local Statics = {}

-- species -> { map, object }
--
-- The object names are the cart's own object_const_def labels, which is what
-- the map def carries and what WorldAPI:toggleObject matches on.  Every one
-- of the three has an UNGUARDED script -- faceplayer, text, loadwildmon,
-- startbattle -- so an object that is back on the map is an encounter that is
-- back, with no flag to clear and no scene to re-enter.
Statics.ROSTER = {
  LUGIA = { map = "WHIRL_ISLAND_LUGIA_CHAMBER",
            object = "WHIRLISLANDLUGIACHAMBER_LUGIA" },
  HO_OH = { map = "TIN_TOWER_ROOF", object = "TINTOWERROOF_HO_OH" },
  SNORLAX = { map = "VERMILION_CITY", object = "VERMILIONCITY_BIG_SNORLAX" },
  -- The sprite slot is $f4 SPRITE_WEIRD_TREE minus SPRITE_VARS ($f0), which
  -- the `variablesprite` macro has already subtracted by the time the VM sees
  -- it (src/script/gen2/Vm.lua:463).  Same number on all three cartridges.
  SUDOWOODO = { map = "ROUTE_36", object = "ROUTE36_WEIRD_TREE",
                spriteSlot = 4 },
}

-- Which map to act on, so a sweep costs one table lookup rather than three.
Statics.BY_MAP = {}
for species, row in pairs(Statics.ROSTER) do
  Statics.BY_MAP[row.map] = { species = species, object = row.object,
                              spriteSlot = row.spriteSlot }
end

-- Gen 2 spells it `caught`, where Gen 1 spells it `owned`
-- (src/core/gen2/Save.lua:252).  Reading the Gen 1 name here would have
-- returned nil for every species, and nil is indistinguishable from "not
-- caught" -- so every static would have been restored forever, including for
-- a player holding the Pokemon.
function Statics.owns(save, species)
  local dex = save and save.pokedex
  local caught = dex and dex.caught
  return (caught and caught[species]) and true or false
end

-- Whether this map's static should be standing there.
function Statics.wants(save, mapId)
  local row = Statics.BY_MAP[mapId]
  if not row then return nil end
  if Statics.owns(save, row.species) then return nil end
  return row
end

-- ---------------------------------------------------------- SUICUNE, again
--
-- Crystal only, and behind a condition that cannot fire early: the player has
-- SEEN Suicune and does not have it.  Seen is written when a battle starts,
-- and the only Suicune battle in Crystal is the one at TIN TOWER -- the Route
-- 36, Route 42 and CIANWOOD sightings are overworld sprites walking past and
-- write nothing to the dex.  So this is exactly "you met it and lost it",
-- read off the save with no event flag touched in either direction.
function Statics.wantsRoamingSuicune(save)
  local dex = save and save.pokedex
  if type(dex) ~= "table" then return false end
  local seen = (dex.seen and dex.seen.SUICUNE) and true or false
  local caught = (dex.caught and dex.caught.SUICUNE) and true or false
  if not seen or caught then return false end
  -- Already out there: a beast mid-roam is left completely alone.
  for _, slot in ipairs((save.roamers) or {}) do
    if type(slot) == "table" and slot.species == "SUICUNE" then return false end
  end
  return true
end

-- Seed the third slot.  CheckEncounterRoamMon picks `value % 4`, so 1, 2 and
-- 3 are all live and a third beast needs no special case anywhere -- it is
-- the same code path RAIKOU and ENTEI already run.
function Statics.seedRoamingSuicune(save, row)
  if not (type(save) == "table" and type(row) == "table" and row.species) then
    return false
  end
  local list = save.roamers
  -- No roamer list at all means the beasts were never released, which means
  -- the player cannot have fought SUICUNE either.  Nothing to repair.
  if type(list) ~= "table" then return false end
  local slot = list[3]
  if type(slot) == "table" and slot.species ~= nil then return false end
  list[3] = { species = row.species, level = row.level, map = row.map, hp = 0 }
  return true
end

-- ------------------------------------------------------------- the roamers
--
-- RAIKOU and ENTEI are the same loss through a different door: no object and
-- no flag, just a save slot that BattleEnd_HandleRoamMons empties when the
-- beast is caught OR beaten (src/core/gen2/Roamers.lua:412-421 -- `win` and
-- `caught` are the same branch).  A slot keeps its INDEX, which is what says
-- which beast it was, so the roster refills it.
--
-- Deliberately not restored: hp.  A roamer that came back at the health it
-- fled with would be the same beast; this is a fresh one, which is the whole
-- point of it being back at all.
function Statics.restoreRoamers(save, roster, owns)
  local list = save and save.roamers
  if type(list) ~= "table" or type(roster) ~= "table" then return {} end
  local back = {}
  for index, row in ipairs(roster) do
    local slot = list[index]
    -- An emptied slot has neither species nor map (Roamers.active), and that
    -- is the only shape refilled: a beast still out there is left alone, hp
    -- and position and all.
    if type(slot) == "table" and slot.species == nil and slot.map == nil
        and row.species and not owns(row.species) then
      slot.species = row.species
      slot.level = row.level
      slot.map = row.map
      slot.hp = 0
      back[#back + 1] = row.species
    end
  end
  return back
end

-- ------------------------------------------------------------- installing

function Statics.install(mod)
  -- The roster the beasts are refilled from.  Required rather than
  -- reconstructed: the order of the rows is what identifies a slot, and a
  -- hand-written order that drifted from the cart's would put ENTEI back as
  -- RAIKOU.  The bundle already declares engine_internals.
  local okRoamers, Roamers = pcall(require, "src.core.gen2.Roamers")
  if not okRoamers then Roamers = nil end

  local function save()
    return mod.game and mod.game.save or nil
  end

  local function owns(species)
    return Statics.owns(save(), species)
  end

  -- "gen1" | "gs" | "crystal" -- SUICUNE roams on two of the three already.
  local function lineage()
    local okReq, GameVersion = pcall(require, "src.core.GameVersion")
    if not okReq or type(GameVersion) ~= "table" then return nil end
    if type(GameVersion.engine) ~= "function" then return nil end
    local okCall, value = pcall(GameVersion.engine)
    return okCall and value or nil
  end

  -- Put a variable sprite slot back to the value the map started with.
  --
  -- The wanted value is read off the world's own initialSprites rather than
  -- written down here: that is where the engine itself gets it when it fills
  -- an empty slot (src/world/gen2/World.lua:712), so this cannot disagree
  -- with the map.
  --
  -- Both copies are written, because they answer at different times: the save
  -- seeds the table on the next World build, and the live table is what the
  -- current session draws from.  If the sheet is still stale for this one
  -- visit -- the object may already have spawned by the time map.entered
  -- fires -- it corrects itself on the next entry, and the ENCOUNTER works
  -- either way, because the script never depended on the sheet.
  local function revertSprite(slot)
    if not slot then return false end
    local okWorld, world = pcall(function() return mod.world:overworld() end)
    if not okWorld or type(world) ~= "table" then return false end
    local wanted
    for _, row in ipairs(world.initialSprites or {}) do
      if row.slot == slot then
        wanted = row.sprite
        break
      end
    end
    if wanted == nil then return false end
    local record = save()
    if record then
      record.variableSprites = record.variableSprites or {}
      record.variableSprites[slot] = wanted
    end
    if type(world.variableSprites) == "table" then
      world.variableSprites[slot] = wanted
    end
    return true
  end

  -- Returns what it put back, for the log and for the bench.
  function Statics.sweep(mapId)
    local record = save()
    local back = {}
    if not record then return back end

    local row = mapId and Statics.wants(record, mapId)
    if row and mod.world then
      -- toggleObject only resolves for the loaded map, which is exactly the
      -- map that was just entered.  A failure is not worth a warning every
      -- time the player walks through: the object may legitimately be
      -- visible already, which is the steady state once it is back.
      local ok = pcall(function()
        return mod.world:toggleObject(mapId, row.object, true)
      end)
      if ok then
        -- Order matters: the sheet is put back BEFORE the object is counted,
        -- so a tree that came back looking like a twin is still a tree in the
        -- log rather than two separate mysteries.
        if row.spriteSlot then revertSprite(row.spriteSlot) end
        back[#back + 1] = row.species
      end
    end

    -- Crystal's SUICUNE, put back where the other two cartridges keep it.
    if Roamers and lineage() == "crystal"
        and Statics.wantsRoamingSuicune(record) then
      local row
      for _, entry in ipairs(Roamers.SPECIES or {}) do
        if entry.species == "SUICUNE" then row = entry end
      end
      if row and Statics.seedRoamingSuicune(record, row) then
        mod.log:info("SUICUNE was never caught, so it is roaming Johto -- "
          .. "which is what GOLD and SILVER would have done with it")
      end
    end

    if Roamers then
      local okRoster, roster = pcall(Roamers.roster,
        mod.game and mod.game.data and mod.game.data.gen2Encounters)
      if okRoster and type(roster) == "table" then
        for _, species in ipairs(
            Statics.restoreRoamers(record, roster, owns)) do
          back[#back + 1] = species
          mod.log:info("%s was never caught, so it is roaming again", species)
        end
      end
    end

    return back
  end

  mod.events:on("map.entered", function(event)
    Statics.sweep(event and event.mapId)
  end)

  -- A save loaded straight onto a static's map gets no map.entered for it on
  -- some boot paths, so the current map is swept on load too.  Idempotent, so
  -- a doubled call costs nothing.
  local function sweepHere()
    local here = mod.world and mod.world:current()
    Statics.sweep(here and here.mapId)
  end
  mod.events:on("save.loaded", sweepHere)
  mod.events:on("game.ready", sweepHere)
end

return Statics
