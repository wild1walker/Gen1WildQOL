-- Running one upstream Quality of Life feature on its own.
--
-- Upstream ships XP BAR, POKéDEX INDICATOR, LOCATION BANNERS and EASY
-- INTERACTIONS as a single mod behind a single QUALITY OF LIFE submenu.  In
-- this bundle each is a feature in its own right, because they have nothing to
-- do with each other: wanting easy HM use is no reason to want an XP bar, and
-- the whole point of the bundle menu is that you switch on the parts you want.
--
-- Splitting them means supplying by hand the two things upstream's own
-- main.lua supplied: the `generation` probe, and a `services.options.value`
-- the feature files call to read their rows.  Both are small, and doing it
-- this way leaves every upstream feature file untouched -- they are vendored
-- exactly as published and re-read on every sync.

local Common = {}

local function loaderFor(mod)
  return function(path, ...)
    local source, readError = mod:read(path)
    if not source then
      mod.log:error("cannot read %s (%s)", path, tostring(readError))
      return nil
    end
    local chunk, compileError = load(source, "@" .. tostring(mod.path) .. "/" .. path)
    if not chunk then
      mod.log:error("%s did not compile: %s", path, tostring(compileError))
      return nil
    end
    local ok, value = pcall(chunk, ...)
    if not ok then
      mod.log:error("%s failed to run: %s", path, tostring(value))
      return nil
    end
    return value
  end
end

-- A feature's rows are its own `option` plus one per subfeature, flattened.
-- `aliases` maps a stored value that is no longer in the choice list onto one
-- that is -- upstream uses it to carry an old boolean row forward onto a
-- choice row, and dropping it would silently reset those players.
local function flatten(feature, schema, aliases)
  if feature.option then
    schema[#schema + 1] = feature.option
    if feature.option.aliases then
      aliases[feature.option.key] = feature.option.aliases
    end
  end
  for _, sub in ipairs(feature.subfeatures or {}) do
    flatten(sub, schema, aliases)
  end
  return schema, aliases
end

-- Build the one service object every upstream feature file expects.
--
-- `services.options.value(game, key)` is called with a game the feature
-- happens to have on hand; the bundle reads through the facade instead, which
-- already resolves the live save and the row default.  The game argument is
-- accepted and ignored, which is what keeps the upstream call sites working
-- unedited.
function Common.services(mod, generation, aliases)
  return {
    generation = generation,
    options = {
      value = function(_, key)
        local value = mod.options:get(key)
        local map = aliases[key]
        if map and map[value] ~= nil then return map[value] end
        return value
      end,
    },
  }
end

-- The battle overlay host is the one thing two features share: the XP bar and
-- the caught marker both draw into it, and it should wrap `battle.draw` once
-- rather than once per feature.  It is parked on the bundle's shared table for
-- exactly that reason.
function Common.battleService(mod, load_)
  local shared = mod.shared
  if shared and shared.qolBattle then return shared.qolBattle end
  local overlays = load_("qol_battle_overlays.lua")
  if not overlays then return nil end
  local service = overlays.new(mod)
  if shared then
    shared.qolBattle = service
    -- Installed once, after every feature has had its chance to add an
    -- overlay: `install` subscribes to battle.started, and an overlay added
    -- afterwards would miss the battle already in progress.
    mod.events:once("mods.loaded", function() service:install() end)
  else
    service:install()
  end
  return service
end

-- The whole of a split feature's install, for the common case.
--
--   path       upstream feature file, vendored as published
--   wantsBattle  true for the two that draw over a battle
function Common.install(mod, path, wantsBattle)
  local load_ = loaderFor(mod)

  local generationModule = load_("qol_generation.lua")
  if not generationModule then return end
  local generation = generationModule.new(mod)

  local feature = load_(path, generation)
  if type(feature) ~= "table" or type(feature.install) ~= "function" then
    mod.log:error("%s is not a feature module", path)
    return
  end

  -- Upstream gates each feature on the generation it supports; Gold draws its
  -- own XP bar, so that one is Gen 1 only.  A feature that does not apply to
  -- this boot installs nothing and says so once.
  if not generation:supports(feature.games) then
    mod.log:info("not supported on this generation; skipped")
    return
  end

  local schema, aliases = flatten(feature, {}, {})
  mod.options:define(schema)

  local services = Common.services(mod, generation, aliases)
  if wantsBattle and generation.value == 1 then
    services.battle = Common.battleService(mod, load_)
  end

  feature.install(mod, services)
  return { feature = feature, services = services, generation = generation }
end

return Common
