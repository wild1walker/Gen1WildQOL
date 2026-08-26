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

-- ---------------------------------------------------------------- the faint gate
--
-- Upstream's XP bar keeps drawing after the player's Pokemon faints.
--
-- The engine clears the player HUD the moment the mon goes down -- the name,
-- the level and the HP bar all disappear behind the "<NAME> fainted!" box --
-- but `battle.player` is still a table and the overlay's own guards
-- (`safari`, `demo`, `showPlayerBack`, the intro slide) are all still false.
-- So the bar carries on being drawn into the empty space where the HUD was:
-- a blue stripe floating over nothing until the battle moves on.
--
-- The fix is upstream's own idiom, applied to the side it was missed on. The
-- caught-indicator feature in this same mod draws over the *enemy* HUD and
-- guards itself with an `enemyHudVisible` predicate whose last clause is
-- `not battle.enemy.fainted`. The XP bar draws over the *player* HUD and has
-- no matching predicate. This is that predicate.
--
-- It is applied here rather than by editing the vendored feature file, so
-- upstream's source stays byte-identical to what it publishes and a sync
-- brings the next version in cleanly. If upstream fixes this, the guard
-- becomes a no-op rather than a conflict.

-- `fainted` is the flag the engine sets on a battler and the one upstream
-- already reads for the enemy. The HP check behind it is belt and braces: it
-- is what Gen1Follower, Gen1SoundQOL and exp_share all use to decide whether
-- a Pokemon is still standing, and it covers the frame between the HP hitting
-- zero and the flag being set.
function Common.playerHudVisible(battle)
  local player = battle and battle.player
  if type(player) ~= "table" then return false end
  if player.fainted then return false end
  local mon = player.mon
  if type(mon) == "table" and (tonumber(mon.hp) or 1) <= 0 then return false end
  return true
end

-- Wrap every overlay a feature registers in a predicate, without the feature
-- or the shared host knowing.  The host keeps one overlay list for the whole
-- bundle, so the gate has to sit on the individual overlay rather than on the
-- host -- the caught marker draws through the same host and must not inherit
-- the XP bar's gate.
local function gated(host, predicate)
  return {
    add = function(_, overlay)
      local base = overlay.draw
      if type(base) == "function" then
        overlay.draw = function(battle, state, context)
          if not predicate(battle) then return end
          return base(battle, state, context)
        end
      end
      return host:add(overlay)
    end,
    install = function() return host:install() end,
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
--   gate       optional predicate; the feature's battle overlays only draw
--              when it returns true.  See Common.playerHudVisible.
function Common.install(mod, path, wantsBattle, gate)
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
    if services.battle and type(gate) == "function" then
      services.battle = gated(services.battle, gate)
    end
  end

  feature.install(mod, services)
  return { feature = feature, services = services, generation = generation }
end

return Common
