-- The four legendaries, retryable until caught.
--
-- Vanilla's rule, and the engine's own comment on it
-- (src/script/Commands.lua, Commands.static_battle):
--
--   beatFlag ... is the EVENT_BEAT_* event set by EndTrainerBattle
--   (home/trainers.asm) on ANY non-blackout end -- win, catch or flee alike
--   -- which is why a fled legendary never returns.
--
-- So on the cartridge a legendary is not a rare encounter, it is a saving
-- throw: knock it out by accident, or panic and run, and that species is gone
-- from the file forever.  The countermeasure players actually use is to save
-- in front of it and reset on a bad outcome, which is not a mechanic, it is a
-- workaround for one.
--
-- This mod's whole premise is that every species has a route.  Four of them
-- having a route you can permanently destroy by pressing the wrong button was
-- the one place that premise did not hold, and "they keep their vanilla
-- statics" was the reason given rather than an argument for it.
--
-- What changes: nothing about the encounter.  Same object, same level, same
-- one-at-a-time.  You still get exactly ONE Articuno.  What goes away is
-- losing it forever -- beat it or flee it and it is standing there again when
-- you come back.  Renewable it is not; unlosable it now is.
--
-- ------------------------------------------------------------- how, and why
-- ------------------------------------------------------------- this way
--
-- On entering a map: if a legendary's beat flag is set and the player does
-- not own that species, clear the flag and put its object back.
--
-- The obvious alternative -- undo it at battle.ended -- does not work, and the
-- ordering is why.  static_battle runs the battle, THEN sets the flag, THEN
-- hides the object, so battle.ended fires before either.  Reacting to
-- flag.changed instead lands between the two: the flag would be cleared and
-- the object hidden a moment later, which destroys the only signal that
-- anything needs restoring.  Waiting until the map is next entered puts the
-- whole sequence safely in the past, and makes the restore idempotent -- it
-- can run on every map entry forever and do nothing until there is something
-- to do.
--
-- The cost is that the object comes back when you re-enter rather than the
-- instant the battle ends.  Cheap, and it reads as the bird having gone back
-- to its perch.
--
-- Nothing here is a hardcoded map list.  The flag is EVENT_BEAT_<SPECIES> and
-- the object is <MAP>_<SPECIES> -- both derived, both confirmed against the
-- engine's own tables (src/save_convert/data/toggle_objects.lua:
-- SEAFOAMISLANDSB4F_ARTICUNO, POWERPLANT_ZAPDOS, VICTORYROAD2F_MOLTRES,
-- CERULEANCAVEB1F_MEWTWO).

local M = {}

-- The sole exception to "everything renewable", and now the sole exception to
-- "everything renewable AND unlosable".  Mew is not here: its own gate is a
-- flag this mod owns, and it is a wild encounter rather than a static.
M.SPECIES = { "ARTICUNO", "ZAPDOS", "MOLTRES", "MEWTWO" }

function M.flagFor(species) return "EVENT_BEAT_" .. species end

-- Whether an object on a map belongs to this species.  The engine names a
-- static's object for the map it stands on and the thing standing there, so
-- the suffix is the test.
function M.objectIsFor(name, species)
  local suffix = "_" .. species
  return type(name) == "string" and #name > #suffix
    and name:sub(-#suffix) == suffix
end

function M.install(mod, ctx)
  local function owned(species)
    local save = mod.game and mod.game.save
    local dex = save and save.pokedex
    return (dex and dex.owned and dex.owned[species]) and true or false
  end

  -- Returns the species it put back, for the log and for the suite.
  function M.restore(mapId)
    local world = mod.world
    local save = mod.game and mod.game.save
    if not (world and save and mapId) then return {} end
    local toggles = (save.objectToggles or {})[mapId] or {}
    local back = {}

    for _, species in ipairs(M.SPECIES) do
      local flag = M.flagFor(species)
      -- Owning it is the whole test.  A player who caught it keeps the
      -- cartridge's behaviour exactly; a player who did not is the one this
      -- exists for.  It also quietly repairs a save that lost one before this
      -- mod was installed, which is a good thing to be able to say.
      if world:getFlag(flag) == true and not owned(species) then
        -- A hidden object named for this species is what says the map being
        -- entered is the one it stands on.  The flag alone does not: it is
        -- global, so acting on it anywhere would clear Articuno's flag while
        -- the player walked onto Route 1 -- Articuno's own map would then
        -- never see it set, and the bird would stay gone for good.  Exactly
        -- the bug this file exists to fix, reintroduced one layer up.
        local hidden = {}
        for name, visible in pairs(toggles) do
          if visible == false and M.objectIsFor(name, species) then
            hidden[#hidden + 1] = name
          end
        end
        if #hidden > 0 then
          for _, name in ipairs(hidden) do
            world:toggleObject(mapId, name, true)
          end
          world:setFlag(flag, nil)
          back[#back + 1] = species
          mod.log:info("%s was not caught, so it is back on %s", species, mapId)
        end
      end
    end
    return back
  end

  mod.events:on("map.entered", function(event)
    M.restore(event and event.mapId)
  end)

  -- A save loaded straight into a legendary's map gets no map.entered for it
  -- in some boot paths, so the current map is swept on load too.  Idempotent,
  -- so a doubled call costs nothing.
  local function sweepHere()
    local here = mod.world and mod.world:current()
    M.restore(here and here.mapId)
  end
  mod.events:on("save.loaded", sweepHere)
  mod.events:on("game.ready", sweepHere)

  mod.log:info("the four legendaries stay until they are caught")
end

return M
