-- SPRINT on FireRed, LeafGreen and Emerald.
--
-- Gen1Sprint exists to give Red what FireRed already has: B held, twice the
-- walking speed.  So on a GBA cart there is nothing to add to the run itself.
-- What there is, is the two places the cart still says no:
--
--   * before the Running Shoes are in the bag, B does nothing at all
--     (FLAG_SYS_B_DASH -- pokefirered src/field_player_avatar.c, pokeemerald
--     src/bike.c:1056).  RUN BEFORE THE SHOES lifts that.
--   * Emerald will not run on a map whose header says so, which is every
--     building in Hoenn (`allowRunning`, pokeemerald src/bike.c:1056).  RUN
--     INDOORS lifts that.  FireRed and LeafGreen have no such rule and the
--     row changes nothing there.
--
-- What it does NOT lift is the cart's own per-tile rule -- long grass, hot
-- springs, the Pacifidlog logs, the Fortree bridge on an even elevation --
-- because those are not about permission: the player sprite has no running
-- frames that read right on them.  Nor underwater, nor on a bicycle.
--
-- One wrap on `Player.canDash`, which `Player.update` asks once per step.
-- The cart's own answer is asked first and a yes is never second-guessed, so
-- with both rows off -- or SPRINT off -- it is the untouched game.

return function(mod)
  mod.options:define({
    { key = "enabled", type = "toggle", label = "SPRINT", default = true },
    { key = "early", type = "toggle", label = "RUN BEFORE THE SHOES",
      default = true,
      help = "B runs from the first step, not from the Running Shoes on.",
      visible_if = { key = "enabled", equals = true } },
    { key = "indoors", type = "toggle", label = "RUN INDOORS",
      default = true,
      help = "Emerald: run in buildings too. FireRed already lets you.",
      visible_if = { key = "enabled", equals = true } },
  })

  local okP, Player = pcall(require, "src.core.game3.player")
  if not okP or type(Player) ~= "table" or type(Player.canDash) ~= "function" then
    mod.log:warn("src.core.game3.player has no canDash; SPRINT has nothing to reach")
    return
  end

  local function on(key)
    return mod.options:get(key) ~= false
  end

  -- Through `require`, never `package.loaded`: inside the mod sandbox
  -- `package` is a shim whose `loaded` is empty (src/mods/LegacyCompat.lua
  -- packageShim), so a lookup there finds nothing on a real boot.  These are
  -- all loaded by the time the player can take a step; the require is a
  -- table lookup.
  local function engine(name)
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then return module end
    return nil
  end

  -- The field rules this cart runs by: `running` is Emerald's (flag name,
  -- header rule, tile rules); FireRed's profile has none and runs on the
  -- flag alone.
  local function runningRules()
    local okProfile, Profile = pcall(require, "src.core.game3.profile")
    if not okProfile or type(Profile) ~= "table"
        or type(Profile.forSession) ~= "function" then
      return nil, nil
    end
    local ok, row = pcall(Profile.forSession)
    if not ok or type(row) ~= "table" then return nil, nil end
    return type(row.field) == "table" and row.field.running or nil, row
  end

  local function hasShoes(store, rules, row)
    local okFlags, Flags = pcall(require, "src.core.game3.scripting.flags")
    if not okFlags or type(Flags) ~= "table" then return false end
    local id
    if rules and rules.flag and type(Flags.forVersion) == "function" then
      local okIds, ids = pcall(Flags.forVersion, row and row.id)
      id = okIds and type(ids) == "table" and ids.IDS and ids.IDS[rules.flag]
    elseif type(Flags.IDS) == "table" then
      id = Flags.IDS.SYS_B_DASH
    end
    if id == nil then return false end
    local ok, set = pcall(Flags.getFlag, store, nil, id)
    return ok and set == true
  end

  -- The tile half of the cart's `runningDisallowed`, without the header half.
  local function tileForbids(rules)
    if not rules then return false end
    local Collision = engine("src.core.game3.collision")
    if not Collision or type(Collision.behavior) ~= "function" then
      return false
    end
    local okB, beh = pcall(Collision.behavior, Player.cellX, Player.cellY)
    if not okB or beh == nil then return false end
    local okMB, MB = pcall(require, "src.core.game3.mb")
    if not okMB or type(MB) ~= "table" or type(MB.id) ~= "function" then
      return false
    end
    for _, name in ipairs(rules.behaviors or {}) do
      if beh == MB.id(name) then return true end
    end
    for _, name in ipairs(rules.evenElevation or {}) do
      if beh == MB.id(name)
          and (tonumber(Player.currentElevation) or 0) % 2 == 0 then
        return true
      end
    end
    return false
  end

  local function headerForbids(rules)
    if not (rules and rules.mapHeader) then return false end
    local Collision = engine("src.core.game3.collision")
    local def = Collision and Collision._mapDef or nil
    return type(def) == "table" and tonumber(def.allowRunning) == 0
  end

  local base = Player.canDash
  Player.canDash = function(...)
    if base(...) then return true end
    if not on("enabled") then return false end
    local early, indoors = on("early"), on("indoors")
    if not early and not indoors then return false end

    -- The field is not scripted yet: the cart's own refusal, and not one
    -- this is about.
    local Space = engine("src.core.game3.scripting.space")
    local store = Space and type(Space.getStore) == "function"
      and Space.getStore() or nil
    if not store then return false end
    if Player.underwater or Player.biking then return false end

    local rules, row = runningRules()
    if not early and not hasShoes(store, rules, row) then return false end
    if tileForbids(rules) then return false end
    if headerForbids(rules) and not indoors then return false end
    return true
  end

  mod.exports.canDash = Player.canDash
end
