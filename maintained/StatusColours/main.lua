-- STATUS COLOURS -- the screen says what your party is carrying.
--
-- Gen 1 tells you a mon is poisoned while you walk by flashing the whole
-- screen black, twice, every fourth step (engine/events/poison.asm, and
-- src/world/OverworldController.lua:5736 here).  It is the loudest thing the
-- overworld ever does, it repeats for as long as the poison lasts, and what
-- it actually communicates -- "someone took a point of damage" -- would fit
-- in a colour.
--
-- So: while a party member is poisoned the world wears purple, and the tick
-- that takes the HP deepens it for a moment instead of blacking the screen
-- out.  The state is visible the whole time rather than announced twice a
-- second, which is both gentler to look at and strictly more information.
--
-- How the colour gets there matters.  This is not a purple rectangle drawn
-- over the game: it is the `render.zones` hook (src/core/Game.lua:684, "custom
-- colorization"), which hands a mod the SGB palette regions before the blit.
-- The four colours a region is drawn through are what move, so the picture
-- keeps its full range of light and dark and simply changes hue -- the same
-- thing a Super Game Boy palette swap does, and the same seam the engine's own
-- weather and lighting use.  Nothing is layered, nothing is dimmed, and text
-- drawn over the world stays as readable as it was.

return function(mod)
  local Colours = (function()
    local source, err = mod:read("colours.lua")
    if not source then
      mod.log:error("cannot read colours.lua (%s)", tostring(err))
      return nil
    end
    local chunk, compileError = load(source, "@colours.lua")
    if not chunk then
      mod.log:error("colours.lua did not compile: %s", tostring(compileError))
      return nil
    end
    local ok, value = pcall(chunk)
    if not ok then
      mod.log:error("colours.lua failed to run: %s", tostring(value))
      return nil
    end
    return value
  end)()
  if not Colours then
    mod.log:error("STATUS COLOURS is not installing: its colour table is "
      .. "unreadable, and a tint with no colours is nothing")
    return
  end

  -- ------- the rows

  local schema = {
    { key = "enabled", type = "toggle", label = "STATUS COLOURS",
      default = true },

    -- The world half.  Off leaves the overworld exactly as the engine draws
    -- it, black flash and all, and keeps whatever the other rows turn on.
    { key = "world", type = "toggle", label = "TINT THE WORLD",
      default = true, visible_if = { key = "enabled", equals = true } },

    -- Which conditions the world reacts to at all.  POISON is the default and
    -- not a timid one: poison is the condition doing something to you while
    -- you walk, which is why it is the one the game already interrupts for.
    -- PARALYSIS lasts until a town and would paint the world yellow for an
    -- hour to say something no step changes.
    { key = "world_scope", type = "choice", label = "WORLD REACTS TO",
      default = "poison",
      choices = { { "poison", "POISON" }, { "any", "ANY STATUS" } },
      visible_if = { key = "world", equals = true } },

    { key = "depth", type = "choice", label = "DEPTH", default = "normal",
      choices = { { "subtle", "SUBTLE" }, { "normal", "NORMAL" },
                  { "strong", "STRONG" } },
      visible_if = { key = "enabled", equals = true } },

    -- The damage tick.  On, the engine's two black pulses are swallowed and
    -- the tint deepens over the same frames instead.  Off puts the vanilla
    -- flash back while keeping the resting colour, for someone who wants the
    -- colour but still wants to be told.
    { key = "replace_flash", type = "toggle", label = "REPLACE FLASH",
      default = true, visible_if = { key = "world", equals = true } },

    -- ------- which states get a colour
    --
    -- One row each, because the whole argument for the feature is that a
    -- colour is quieter than a flash -- and eight colours nobody asked for
    -- would be louder than one flash.
    { key = "psn", type = "toggle", label = "POISON", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "tox", type = "toggle", label = "BAD POISON", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "brn", type = "toggle", label = "BURN", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "frz", type = "toggle", label = "FREEZE", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "par", type = "toggle", label = "PARALYSIS", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "slp", type = "toggle", label = "SLEEP", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "fainted", type = "toggle", label = "FAINTED GREY", default = true,
      visible_if = { key = "enabled", equals = true } },
    { key = "lowhp", type = "toggle", label = "LOW HP", default = true,
      visible_if = { key = "enabled", equals = true } },
  }
  mod.options:define(schema)

  local DEFAULTS = {}
  for _, row in ipairs(schema) do DEFAULTS[row.key] = row.default end

  local function opt(key)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return DEFAULTS[key] end
    return value
  end

  local function on(key)
    local value = opt(key)
    return value and true or false
  end

  -- The engine's own low-health threshold is a fifth of max HP, which is what
  -- the low-health alarm uses; matching it means the colour and the sound
  -- agree rather than each having an opinion.
  local LOW_HP_FRACTION = 0.2

  -- What OverworldState:applyFieldPoison sets the counter to.  Only the floor
  -- for the very first frame: the live counter is watched instead, so a mod
  -- that lengthens the flash gets a longer deepening rather than a clipped one.
  local POISON_FLASH_FRAMES = 12

  -- ------- what the party is carrying

  local function allowedSet()
    local allowed = {}
    for _, entry in ipairs(Colours.STATUSES) do
      if on(entry.key) then allowed[entry.key] = true end
    end
    return allowed
  end

  local function worldAllowed()
    local allowed = allowedSet()
    if opt("world_scope") == "any" then return allowed end
    -- POISON means the two poisons and nothing else.  Fainted is deliberately
    -- not in here: a fainted mon is not doing anything to you as you walk, and
    -- a world greyed out for the rest of the route is a punishment the game
    -- never asked for.
    return { psn = allowed.psn, tox = allowed.tox }
  end

  local function partyOf(game)
    local save = game and game.save
    local party = save and save.party
    if type(party) ~= "table" then return nil end
    return party
  end

  -- ------- is the world the thing on screen
  --
  -- The engine's own test rather than an approximation: src/core/Game.lua
  -- takes the stack's visible base and asks whether it is the overworld.  True
  -- while walking and while a text box sits over the map; false in a battle,
  -- where the status is already on the HUD and a tinted battle would be
  -- fighting Gen1BattleUI's own colours; false in a full-screen menu.
  local function overworldIsBase(game)
    if not (game and game.overworld and game.stack) then return false end
    local ok, base = pcall(function() return game.stack:visibleBase() end)
    if not ok or base == nil then return false end
    local states = game.stack.states
    return type(states) == "table" and states[base] == game.overworld
  end

  -- ------- the tick
  --
  -- poisonFlash is the engine's counter for the two black pulses.  Taking it
  -- to zero is what swallows the flash: OverworldState:draw is the only place
  -- that reads it, and it draws only while it is above zero, so zeroing it
  -- removes the flash and nothing else.
  --
  -- The value is captured before it is cleared, because it is the whole
  -- signal: it says a tick landed and how far through it is.
  local flashPeak = POISON_FLASH_FRAMES

  local function takeFlash(game)
    local world = game and game.overworld
    if type(world) ~= "table" then return 0 end
    local pulse = tonumber(world.poisonFlash or 0) or 0
    if pulse <= 0 then return 0 end
    if pulse > flashPeak then flashPeak = pulse end
    if on("replace_flash") then world.poisonFlash = 0 end
    return pulse
  end

  -- ------- the zones

  -- With no zones at all the screen is drawn in plain DMG greys, and there is
  -- nothing to tint until we say what is being tinted: the four greys the
  -- extracted art actually uses.  PaletteFX names them, so this is the
  -- engine's own answer rather than four numbers guessed here.
  local function baseZones(zones)
    if type(zones) == "table" and zones[1] then return zones, false end
    local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
    if not ok or type(PaletteFX) ~= "table"
        or type(PaletteFX.whole) ~= "function" then
      return zones, false
    end
    return { PaletteFX.whole(PaletteFX.GRAYS) }, true
  end

  local function tintZones(zones, key, amount)
    local out = {}
    for i = 1, #zones do
      local zone = zones[i]
      if type(zone) ~= "table" or zone.colors == nil or zone.colors == false then
        -- colors == false is the trueColor opt-out: a rect that blits with no
        -- shader so full-colour art survives the pass.  Tinting it is not
        -- possible, and pretending otherwise would drop the opt-out.
        out[i] = zone
      else
        local tinted = {}
        for k, v in pairs(zone) do tinted[k] = v end
        tinted.colors = Colours.apply(zone.colors, key, amount)
        out[i] = tinted
      end
    end
    return out
  end

  mod.hooks:wrap("render.zones", function(next, game, zones)
    local out = next(game, zones)
    if not on("enabled") or not on("world") then return out end
    if not overworldIsBase(game) then return out end

    local party = partyOf(game)
    if not party then return out end

    local key = Colours.worstIn(party, on("lowhp") and LOW_HP_FRACTION or nil,
      worldAllowed())
    -- Only swallow the flash when a colour is going to replace it.  With
    -- POISON switched off the player has said they do not want the tint, and
    -- letting the engine's flash fire is the honest reading of that.
    local pulse = key and takeFlash(game) or 0
    if not key then return out end

    local amount = Colours.amountFor(opt("depth"), pulse, flashPeak)
    local base = baseZones(out)
    if type(base) ~= "table" or not base[1] then return out end
    return tintZones(base, key, amount)
  end)

  -- What the world is wearing, for anything that wants to agree with it: the
  -- menu tinting that follows this, and any mod that would rather read the
  -- answer than work it out again.
  mod.exports.statusColours = {
    keyFor = function(monster)
      return Colours.keyFor(monster, on("lowhp") and LOW_HP_FRACTION or nil)
    end,
    tintFor = function(key)
      local entry = Colours.entry(key)
      if not entry or not on(key) then return nil end
      return entry.tint, entry.desaturate and true or false
    end,
    apply = function(colors, key, amount)
      if not key or not on(key) then return colors end
      return Colours.apply(colors, key, amount or Colours.amountFor(opt("depth")))
    end,
    depth = function() return Colours.amountFor(opt("depth")) end,
  }

  mod.log:info("STATUS COLOURS installed: the world wears what the party is "
    .. "carrying, and the poison tick deepens it instead of blacking out")
end
