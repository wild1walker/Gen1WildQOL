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

    -- Which conditions the world reacts to at all.
    --
    -- DAMAGING is the default: the statuses that take HP.  In Gen 1 that is
    -- poison, bad poison and burn -- HandlePoisonBurnLeechSeed is one routine
    -- over the three of them (src/battle/BattleState.lua:2778) -- and it is
    -- the honest line to draw, because a colour that means "this is costing
    -- you HP" is worth wearing and a colour that means "this will be awkward
    -- in your next battle" is not.
    --
    -- Only poison ticks in the field, so only poison ever deepens; burn shows
    -- its colour while you walk and does its damage in battle.  That is the
    -- point rather than an inconsistency: the world says what the party is
    -- carrying, and it is carrying a burn.
    --
    -- POISON narrows it to the one the game itself interrupts for.  ANY STATUS
    -- opens it to the rest -- worth knowing that paralysis lasts until a town,
    -- so it will paint the world yellow for an hour to say something no step
    -- changes.
    { key = "world_scope", type = "choice", label = "WORLD REACTS TO",
      default = "damaging",
      choices = { { "damaging", "DAMAGING" }, { "poison", "POISON" },
                  { "any", "ANY STATUS" } },
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

  -- forward-declared: pendingFor is defined with the drawing, and the last
  -- game seen is what the overworld's draw reads the party from.
  local pendingFor, currentGame

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

  -- Fainted is in none of the narrowed sets, deliberately.  A fainted mon is
  -- not doing anything to you as you walk, and a world greyed out for the rest
  -- of the route is a punishment the game never asked for.  Its colour is for
  -- the party and box lists, where it answers "which of these can still
  -- fight", and FAINTED GREY still governs it there.
  local SCOPES = {
    poison   = { psn = true, tox = true },
    damaging = { psn = true, tox = true, brn = true },
  }

  local function worldAllowed()
    local allowed = allowedSet()
    local scope = SCOPES[opt("world_scope")]
    if not scope then return allowed end   -- ANY STATUS, or an unknown value
    local out = {}
    for key in pairs(scope) do out[key] = allowed[key] end
    return out
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

  -- ------- how the colour reaches the screen
  --
  -- A colour filter over the finished frame, which is what this always should
  -- have been.  Two earlier attempts went through the rendering rather than
  -- over it and both failed in the same way -- they were correct against the
  -- seam they used and invisible in the game:
  --
  --   * SGB palette zones.  A map drawn from a full-colour GBC atlas has no
  --     four-colour palette to shift; sgbWorldZones returns an empty list
  --     outright under RED++, so there was nothing to tint.
  --   * A rectangle inside the overworld's own draw, multiplied.  The
  --     overworld draws into a canvas of its own and the multiply did not
  --     survive the composite.
  --
  -- `render.hud` is the engine's own answer to "draw over the completed render
  -- pipeline" (src/core/Game.lua:699).  It runs after every pass, in screen
  -- space, with the playfield's exact geometry handed over -- so there is no
  -- canvas to guess at, no blend mode to match, and no colour mode that can
  -- opt out of it.  A filter over the picture, the way a coloured lens is.
  --
  -- It covers the playfield only, never the margins or the on-screen pad,
  -- because the viewport says where the game actually is.

  local function paint(g, key, amount, view)
    local entry = Colours.entry(key)
    if not entry then return end
    local r, gr, b
    if entry.desaturate then
      r, gr, b = 0.32, 0.32, 0.36
    else
      local t = entry.tint
      r, gr, b = t[1] / 255, t[2] / 255, t[3] / 255
    end
    local x = (view and view.gameX) or 0
    local y = (view and view.gameY) or 0
    local w = (view and view.gameWidth) or 160
    local h = (view and view.gameHeight) or 144
    g.push("all")
    -- Named rather than assumed: push("all") saves whatever was bound, and the
    -- pipeline may have left a shader or a different blend behind.
    if g.setShader then g.setShader() end
    if g.setBlendMode then g.setBlendMode("alpha", "alphamultiply") end
    -- The alpha tops out near the 0.45 the vanilla poison flash uses, so the
    -- strongest this gets is about as strong as the thing it took away -- in
    -- colour, and never a blackout.
    g.setColor(r, gr, b, amount * 0.6)
    g.rectangle("fill", x, y, w, h)
    g.pop()
  end

  local function graphics()
    return mod.__graphics or (love and love.graphics)
  end

  mod.hooks:wrap("render.hud", function(next, game, view)
    local result = next(game, view)
    if not on("enabled") or not on("world") then return result end
    -- The engine's own test for "the map is what is on screen": false in a
    -- battle, where the status is already on the HUD, and false under a
    -- full-screen menu, which is opaque and becomes the visible base itself.
    if not overworldIsBase(game) then return result end

    local party = partyOf(game)
    if not party then return result end
    local key = Colours.worstIn(party, on("lowhp") and LOW_HP_FRACTION or nil,
      worldAllowed())
    -- Only swallow the flash when a colour is going to replace it.  With
    -- POISON switched off the player has said they do not want the tint, and
    -- letting the engine's flash fire is the honest reading of that.
    local pulse = key and takeFlash(game) or 0
    if not key then return result end

    local g = graphics()
    if not g then return result end
    local amount = Colours.amountFor(opt("depth"), pulse, flashPeak)
    if not pcall(paint, g, key, amount, view) then
      mod.log:warn("STATUS COLOURS could not draw the filter; standing down")
    end
    return result
  end)

  -- What the world is wearing, for anything that wants to agree with it.
  --
  -- Gen1Dex, Gen1Party and Gen1BillsBox each already build a per-POKéMON SGB
  -- zone out of PaletteFX.monPal, so tinting a POKéMON's own picture is a
  -- question of running those four colours through this before the zone is
  -- made.  Three screens, one table: the alternative was three copies of the
  -- colours drifting apart the first time one was edited.
  local api = {
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
    -- The condition as a DRAW colour: what to set before drawing a POKeMON so
    -- the picture wears it.  Multiplied by the art, so white is untouched and
    -- a colour lerped toward the tint shifts the hue while keeping the art's
    -- own light and dark.
    --
    -- This exists because a palette zone cannot do the job everywhere.  Zones
    -- reach only art that goes through the shade-remap pass, and full-colour
    -- icon and sprite packs sit that pass out by design -- so the party and
    -- the box tinted nothing at all for anyone running one.  A draw colour
    -- reaches both, and living here rather than in each screen means the three
    -- of them keep agreeing.
    --
    -- nil means "draw it as it is": no condition, or its row switched off.
    drawColour = function(monster)
      local key = Colours.keyFor(monster,
        on("lowhp") and LOW_HP_FRACTION or nil)
      if not key or not on("enabled") or not on(key) then return nil end
      local entry = Colours.entry(key)
      if not entry then return nil end
      local amount = Colours.amountFor(opt("depth"))
      if entry.desaturate then
        local grey = 1 - amount * 0.45
        return { grey, grey, grey }
      end
      local t = entry.tint
      return { 1 - amount * (1 - t[1] / 255),
               1 - amount * (1 - t[2] / 255),
               1 - amount * (1 - t[3] / 255) }
    end,
    -- Whether the feature is doing anything at all, so a caller can skip the
    -- work rather than apply a tint of zero.
    active = function() return on("enabled") end,
  }

  -- Siblings inside this bundle reach it by name through the registry; the
  -- screens that need it are outside, in the other half, so it also goes on
  -- the bundle's own exports where the engine's mod.find already looks.
  mod.exports.statusColours = api
  if type(mod.publish) == "function" then mod.publish("statusColours", api) end

  -- ------- the stats page
  --
  -- Gen1Party and Gen1BillsBox colour their own lists by asking the table
  -- above.  The stats page is the engine's own screen (src/ui/SummaryMenu.lua)
  -- and no mod here owns it, so this one decorates it: it is the one place a
  -- POKeMON's full picture is shown with its status printed beside it, and a
  -- purple picture next to the word POISONED is the whole idea of the feature
  -- in a single screen.
  --
  -- The Pokedex is deliberately not in this list.  A dex entry is a page about
  -- a SPECIES -- Gen1Dex never touches a mon instance and never reads the
  -- party -- so there is no status there to show.  RATTATA is not poisoned;
  -- your RATTATA is.
  --
  -- Through the picture's PALETTE, not by painting over it, and the difference
  -- is the whole white box behind the POKeMON.  Painting the rect was tried
  -- and it is wrong: the zone covers the picture WELL, background included, so
  -- a rectangle over it turns that white square the colour of the tint and the
  -- screen grows a lavender block.  A palette shift moves the four colours the
  -- picture is drawn through, and the well's background is colour 0 of the
  -- species palette -- an off-white -- so it stays an off-white.
  --
  -- The cost is honest: a picture drawn from full-colour art sits the
  -- shade-remap pass out by design, so this tints nothing for such a pack.
  -- The alternative was a lavender box for everyone, which is worse than no
  -- tint for some.  Tinting the sprite and not its background needs the seam
  -- to set a colour around the sprite's own draw, and the engine does not
  -- offer one here.
  --
  -- The whole-screen entry is the HP-bar palette and is skipped, or the bar
  -- would stop meaning what it means.
  local function tintSummary()
    if not (mod.content and mod.content.screens) then return end
    local ok, err = pcall(function()
      mod.content.screens:register("SummaryMenu", {
        new = function(game, ...)
          local got, Builtin = pcall(require, "src.ui.SummaryMenu")
          if not got or type(Builtin) ~= "table"
              or type(Builtin.new) ~= "function" then
            error("statuscolours: no builtin summary screen to decorate", 0)
          end
          local state = Builtin.new(game, ...)
          local inherited = state.sgbPalettes or Builtin.sgbPalettes
          if type(inherited) ~= "function" then return state end
          state.sgbPalettes = function(self, g)
            local zones = inherited(self, g)
            if not on("enabled") or type(zones) ~= "table" then return zones end
            local monster = self.mon
            local key = monster and Colours.keyFor(monster,
              on("lowhp") and LOW_HP_FRACTION or nil)
            if not key or not on(key) then return zones end
            local amount = Colours.amountFor(opt("depth"))
            local out = {}
            for i = 1, #zones do
              local zone = zones[i]
              local whole = type(zone) == "table"
                and (zone.w or 0) >= 160 and (zone.h or 0) >= 144
              if type(zone) ~= "table" or zone.colors == nil
                  or zone.colors == false or whole then
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
          return state
        end,
      })
    end)
    if not ok then
      mod.log:warn("STATUS COLOURS is not colouring the stats page (%s) -- "
        .. "the engine's own screen stands", tostring(err))
    end
  end
  tintSummary()

  mod.log:info("STATUS COLOURS installed: the world wears what the party is "
    .. "carrying, and the poison tick deepens it instead of blacking out")
end
