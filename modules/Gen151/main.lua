-- Gen151 -- every one of the 151 obtainable renewably, in one save, on one
-- version, without trading, while every vanilla encounter keeps its exact
-- vanilla behaviour.
--
-- The wiring lives here; the deciding lives elsewhere:
--
--   placements.lua  the single source of truth: species -> map, method,
--                   level, rarity, gate, justification
--   build.lua       placements + the pristine data -> roll rows and slot
--                   appends, and the "is this species already renewable
--                   here?" question that makes version detection unnecessary
--   roll.lua        the two-stage roll: vanilla exactly, then substitution
--   rarity.lua      the tier table the whole mod shares
--   hints.lua       generated hint vocabulary
--   linkcable.lua   the consumable trade-evolution item
--   dexhints.lua    what the AREA map says about a spawn this mod placed,
--                   handed to Gen1Dex's screen through its provider hook
--   legendaries.lua the four statics, retryable until caught
--   mewgate.lua     the Mansion journals, and the spawn they unlock
--   bench.lua       the test bench, behind an option that defaults off
--
-- The AREA screen used to be here, and is not any more.  Opening AREA on an
-- entry you have never met, the box under the map and the presses that take
-- it down all live in Gen1Dex now -- the mod that owns the POKeDEX and draws
-- the row the press lands on.  What is left is the sentence: dexhints.lua
-- registers one provider with that screen and answers for the species this
-- mod placed, withholds MEW's answer while its gate is shut, and passes on
-- the other 128 for Gen1Dex to read out of the live encounter tables.
--
-- That leaves one permission, engine_internals, and one call behind it: the
-- cable's own sound effect (linkcable.lua) reaches src.core.Sound, which the
-- mod surface has no facade for.  Everything else goes through mod.content,
-- mod.hooks, mod.events, mod.options, mod.ui, mod.world and mod.game.

local MOD_ID = "gen151"

-- A file this mod ships, compiled in this mod's own sandbox.  mod:read plus
-- load is the documented way to reach one: a mod's directory is not on
-- package.path, and require() would only find it by accident of where the
-- mod happens to be installed.
local function submodule(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing from %s -- reinstall the mod; the whole "
      .. "spawn layer is skipped", name, mod.path)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s did not compile: %s -- reinstall the mod", name,
      tostring(err))
    return nil
  end
  local ok, value = pcall(chunk)
  if not ok then
    mod.log:error("%s failed to load: %s -- reinstall the mod", name,
      tostring(value))
    return nil
  end
  return value
end

-- The line the game itself prints, with our wording as backup: on a
-- localized or total-conversion import the extracted label is the one the
-- player recognizes.  A slot count that does not match what we can fill
-- means the extracted line cannot carry this sentence, so the literal
-- stands in rather than printing one with a hole in it (the rule
-- src/core/RomText.lua follows).
local function romText(data, label, fallback, ...)
  local text = data and data.text and data.text[label]
  local args = { ... }
  if type(text) ~= "string" then
    if #args == 0 then return fallback end
    return (fallback:format(...))
  end
  if #args == 0 then return text end
  local slots = 0
  for _ in text:gmatch("%b{}") do slots = slots + 1 end
  if slots ~= #args then return (fallback:format(...)) end
  local i = 0
  return (text:gsub("%b{}", function()
    i = i + 1
    return tostring(args[i])
  end))
end

return function(mod)
  local options = mod.options:define{
    { key = "enabled", type = "toggle", label = "GEN151", default = true },

    -- SPEC 7: every independent decision gets its own row.  The single
    -- biggest complaint about the existing all-151 mod is that it is
    -- all-or-nothing; someone who wants the version exclusives but not a
    -- wild Mew should not have to fork it.
    { key = "exclusives", type = "toggle", label = "EXCLUSIVES",
      default = true, visible_if = { key = "enabled", equals = true } },
    { key = "gifts", type = "toggle", label = "GIFT MONS", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "fossils", type = "toggle", label = "FOSSILS", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "snorlax", type = "toggle", label = "SNORLAX", default = true,
      visible_if = { key = "enabled", equals = true } },

    { key = "trade_evolutions", type = "choice", label = "TRADE EVOS",
      default = "link_cable",
      choices = { { "LINK CABLE", "link_cable" }, { "OFF", "off" } },
      visible_if = { key = "enabled", equals = true } },
    { key = "cable_sfx", type = "toggle", label = "CABLE SOUND",
      default = true,
      visible_if = { key = "trade_evolutions", equals = "link_cable" } },

    -- An invention rather than a restoration, and it shipped off for that
    -- reason.  On, now, by the author's call: a mod called Gen151 that leaves
    -- 151 out of the box is answering a question nobody asked it.  The
    -- caution the default was expressing is still all there in the design --
    -- the gate is four journals in an optional late-game dungeon, MEW is
    -- absent from the encounter table until the flag flips so AREA cannot
    -- spoil it, and the toggle is right here for anyone who wants the
    -- cartridge's own answer instead.
    { key = "mew", type = "toggle", label = "MEW EVENT", default = true,
      visible_if = { key = "enabled", equals = true } },

    -- A percentage over the whole tier table, so the ladder keeps its shape.
    { key = "rarity", type = "number", label = "RARITY %", default = 100,
      min = 0, max = 500, step = 25,
      visible_if = { key = "enabled", equals = true } },

    -- The test bench.  Off is the shipping state and off is what a player
    -- gets; on, the START menu grows a BENCH row that forces this mod's
    -- spawns, hands over the kit and plays the cable sounds on demand.  It
    -- lives here rather than in a companion mod because a bench you have to
    -- download and import separately is a bench that is not there when you
    -- want it.
    { key = "bench", type = "toggle", label = "TEST BENCH", default = false,
      visible_if = { key = "enabled", equals = true } },

    -- The one place "every species has a route" did not hold: a legendary's
    -- route can be permanently destroyed by pressing the wrong button, and
    -- the countermeasure players use -- save in front of it, reset on a bad
    -- outcome -- is a workaround rather than a mechanic.  ONCE is the
    -- cartridge's behaviour for anyone who wants the saving throw back.
    { key = "legendaries", type = "choice", label = "LEGENDARIES",
      default = "until_caught",
      choices = { { "STAY TIL CAUGHT", "until_caught" }, { "ONE SHOT", "once" } },
      visible_if = { key = "enabled", equals = true } },

    -- On, the AREA map's caption names the map, the level band and the tier
    -- for every spawn this mod placed -- on Gen1Dex's screen, which is where
    -- that caption lives; without Gen1Dex installed there is no screen to
    -- write on and this row does nothing.  Off leaves that screen saying
    -- whatever it reads out of the encounter tables on its own, which is the
    -- setting for anyone who would rather find the additions the hard way.
    { key = "hints", type = "toggle", label = "AREA HINTS", default = true,
      visible_if = { key = "enabled", equals = true } },
  }

  -- The loader hands a STORED option back verbatim; it does not check it
  -- against the schema the mod defines today (src/mods/Loader.lua, the
  -- options.get arm: stored value first, row.default only when there is no
  -- stored value at all).  So an options.lua written against an older
  -- version of this mod answers today's rows with yesterday's values.
  --
  -- That is not hypothetical, it is what shipped: HINTS was a three-way
  -- choice through 1.0.x and a toggle from 1.1.0, so an upgraded install
  -- answered `opt("hints") == true` with the string "dex".  False.  The whole
  -- dex surface silently did not install -- no AREA on an undiscovered entry,
  -- no line under the map -- while the row itself still read ON, because a
  -- non-false value renders as on.  Three separate-looking faults, one stale
  -- string.
  --
  -- So every row is checked against its own schema rather than the one that
  -- caught fire: a stored value that is not valid for the row it belongs to
  -- is not a setting, it is a leftover.
  local LEGACY = {
    -- HINTS: AREA ONLY meant "leave the dex alone", which is what OFF means
    -- now; the other two both wanted hints, so they are ON.  Falling back to
    -- the default instead would have handed hints back to somebody who had
    -- turned them off on purpose.
    hints = { area = false, dex = true, notes = true },
  }

  local schema = {}
  for _, row in ipairs(options or {}) do schema[row.key] = row end

  local repaired = {}
  local function opt(key)
    local value = mod.options:get(key)
    local row = schema[key]
    if not row then return value end

    local fixed = value
    local legacy = LEGACY[key]
    if legacy and type(value) == "string" and legacy[value] ~= nil then
      fixed = legacy[value]
    elseif row.type == "toggle" then
      if type(value) ~= "boolean" then fixed = row.default end
    elseif row.type == "number" then
      if type(value) ~= "number" then
        fixed = row.default
      elseif row.min and value < row.min then
        fixed = row.min
      elseif row.max and value > row.max then
        fixed = row.max
      end
    elseif row.type == "choice" then
      local known = false
      for _, choice in ipairs(row.choices or {}) do
        if choice[2] == value then known = true end
      end
      if not known then fixed = row.default end
    end

    if fixed ~= value and not repaired[key] then
      repaired[key] = true
      mod.log:warn("the saved value for %s is %s, which this version's %s "
        .. "row cannot mean -- reading it as %s.  Open this mod's options "
        .. "and set the row to write the new value down.",
        key, tostring(value), tostring(row.type), tostring(fixed))
    end
    return fixed
  end

  -- Published for anyone who wants the placement table.  Filled in below;
  -- declared here so an early return still leaves a well-formed handle
  -- behind.
  mod.exports.version = mod.version
  mod.exports.rows = {}
  mod.exports.fishing = {}
  mod.exports.hints = nil
  mod.exports.hintSurface = opt("hints")
  mod.exports.enabled = false

  if opt("enabled") ~= true then
    mod.log:info("switched off in its own options; nothing registered")
    return
  end

  local Rarity = submodule(mod, "rarity.lua")
  local Roll = submodule(mod, "roll.lua")
  local Build = submodule(mod, "build.lua")
  local Placements = submodule(mod, "placements.lua")
  local Hints = submodule(mod, "hints.lua")
  if not (Rarity and Roll and Build and Placements and Hints) then return end

  -- Read vanilla through the registries.  :each() enumerates the base
  -- table's ids as well as the registered ones, and the entry chunk runs
  -- BEFORE the merge, so what comes back here is the pristine dataset -- no
  -- other mod's patches have landed yet.  That is exactly what both jobs
  -- below need: the vanilla slot count for stage one, and an honest answer to
  -- "does this species already have a renewable source on this cartridge".
  local source = {
    eachEncounter = function() return mod.content.encounters:each() end,
    encounter = function(id) return mod.content.encounters:get(id) end,
    eachPokemon = function() return mod.content.pokemon:each() end,
    field = function(key) return mod.content.field:get(key) end,
  }
  if mod.content.pokemon:get("MEW") == nil then
    mod.log:warn("the species table has no MEW, so this is not a Kanto "
      .. "dataset -- the spawn layer is skipped and nothing is patched")
    return
  end

  local resolved = Build.resolve(Placements, source, {
    rarity = Rarity,
    multiplier = opt("rarity"),
    features = {
      exclusives = opt("exclusives") == true,
      gifts = opt("gifts") == true,
      fossils = opt("fossils") == true,
      snorlax = opt("snorlax") == true,
      mew = opt("mew") == true,
    },
  })
  for _, warning in ipairs(resolved.warnings) do
    mod.log:warn("placement skipped -- %s", warning)
  end

  -- ------------------------------------------------------------ the roll

  local mew = submodule(mod, "mewgate.lua")
  local mewGate = mew and mew.new(mod, { romText = romText })

  local layer = Roll.new()
  for _, row in ipairs(resolved.rows) do
    layer:setVanillaCount(row.map, row.method, row.vanillaCount)
  end
  for _, row in ipairs(resolved.rows) do
    layer:add(row.map, row.method, {
      species = row.species, levels = row.levels, weight = row.weight,
      active = row.gated == "mew" and mewGate and mewGate.unlocked or nil,
    })
  end
  for _, row in ipairs(resolved.fishing) do
    layer:addFishing(row.map, row.rod, {
      species = row.species, levels = row.levels, weight = row.weight,
    })
  end

  -- The data layer: appends only, never a bare slots list, never a `buckets`
  -- key.  These are what makes the dex AREA screen light up the right maps
  -- for free (SPEC 6a), which is why slot placement is preferred over the
  -- Super Rod wherever the choice exists.
  for mapId, byKind in pairs(resolved.appends) do
    local payload = {}
    for kind, slots in pairs(byKind) do
      payload[kind] = { slots = { __append = slots } }
    end
    mod.content.encounters:patch(mapId, payload)
  end

  local random = love and love.math and love.math.random
  mod.hooks:wrap("encounter.roll", function(nextLink, encDef, ctx)
    return layer:roll(nextLink, encDef, ctx, (ctx and ctx.rng) or random)
  end)
  mod.hooks:wrap("encounter.fishing", function(nextLink, rod, mapId, pool)
    return layer:fish(nextLink, rod, mapId, pool, random)
  end)

  local placed = {}
  for _, row in ipairs(resolved.rows) do placed[row.species] = true end
  for _, row in ipairs(resolved.fishing) do placed[row.species] = true end
  local count = 0
  for _ in pairs(placed) do count = count + 1 end
  mod.log:info("%d species placed across %d rows (%d skipped)", count,
    #resolved.rows + #resolved.fishing, #resolved.skipped)

  -- --------------------------------------------------------- the features

  if mewGate then mewGate.install(resolved.rows) end

  if opt("trade_evolutions") == "link_cable" then
    local cable = submodule(mod, "linkcable.lua")
    if cable then
      cable.install(mod, {
        romText = romText,
        sfx = function() return opt("cable_sfx") == true end,
      })
    end
  end

  local dexProbe
  if opt("hints") == true then
    local dexhints = submodule(mod, "dexhints.lua")
    if dexhints then
      dexProbe = dexhints.install(mod, {
        hints = Hints,
        rows = resolved.rows,
        fishing = resolved.fishing,
        unlocked = mewGate and mewGate.unlocked or nil,
      })
    end
  end

  if opt("legendaries") == "until_caught" then
    local legendaries = submodule(mod, "legendaries.lua")
    if legendaries then legendaries.install(mod, {}) end
  end

  -- Last, so the bench's high-priority wrap on encounter.roll goes on above a
  -- chain that is already complete, and so a fault in it cannot cost a player
  -- the spawn layer.
  if opt("bench") == true then
    local bench = submodule(mod, "bench.lua")
    if bench then
      bench.install(mod, {
        rows = resolved.rows,
        fishing = resolved.fishing,
        syncGated = mewGate and mewGate.sync or function() end,
        dexProbe = dexProbe,
      })
    end
  end

  mod.exports.rows = resolved.rows
  mod.exports.fishing = resolved.fishing
  -- Reconcile the runtime-conditional rows -- today that is MEW -- with the
  -- flags they are gated on.  Gen151 calls this itself on every save load, so
  -- nothing needs it in normal play; it is published because a mod that flips
  -- GEN151_MEW_FOUND from outside has no other way to ask for the encounter
  -- table to catch up, and a stale table is what the dex AREA screen reads.
  mod.exports.syncGated = mewGate and mewGate.sync or function() end
  mod.exports.hints = Hints
  mod.exports.hintSurface = opt("hints")
  mod.exports.enabled = true
  mod.exports.id = MOD_ID
end
