-- The LINK CABLE: a consumable that runs one trade evolution (SPEC 3).
--
-- Why an item and not a level threshold: a level-up rule evolves every
-- Kadabra the player owns whether they wanted it or not, and B-cancelling out
-- of it every level is a bad opt-out.  The item leaves the choice with the
-- player and keeps the "something happened to trigger this" feel.  Consumable
-- rather than reusable keeps a real, if small, cost on each evolution rather
-- than making the whole mechanic free after one purchase.
--
-- Where it is sold and what it costs, decided: Celadon Department Store 4F,
-- the shelf that already sells the four evolution stones, for the same 2100
-- they cost.  A LINK CABLE buys exactly one evolution, the same as a stone
-- does, so pricing it anywhere else would need an argument that parity does
-- not.
--
-- The break is the point.  The cable does not quietly vanish from the bag; it
-- dies on screen, and that beat is what makes the consumable read as flavour
-- rather than as a tax.  Four rules hold it together:
--
--   * the evolution runs with via = "TRADE", which EvolutionState reads as
--     non-cancelable (`cancelable = (via ~= "TRADE" and via ~= "ITEM")`,
--     matching evolution.asm Evolution_CheckForCancel).  Thematically exact,
--     and it removes an entire failure mode: the player cannot cancel midway
--     and be left wondering whether the cable was spent.
--   * the break message comes AFTER the evolution resolves.  The cable works,
--     then it fails.  Reversed, it reads as the evolution failing.
--   * it breaks ONLY on success, and is consumed only then.  This is a
--     deliberate divergence from evolution stones, which BagMenu consumes
--     before evolving; a consumed item with nothing to show for it is the one
--     outcome that would make this feel like a tax.
--   * the beats are spaced periods, ". . .", which is the engine's own idiom
--     (the fishing no-nibble pause in OverworldController).

local M = {}

local ITEM = "LINK_CABLE"
local NAME = "LINK CABLE"
local PRICE = 2100
-- Two sounds, because the break is two events.  ZAP is the fault itself, on
-- the "ZzZzap!" page; SNAP is the aftermath, on the page that says the cable
-- broke.  One sound covering both had to be either the arc or the silence
-- afterwards, and it was the silence.
local ZAP = "SFX_GEN151_CABLE_ZAP"
local SFX = "SFX_GEN151_CABLE_SNAP"

-- Celadon Mart 4F's clerk.  text_pointers has "deep" merge semantics, under
-- which a list APPENDS rather than replaces, so this adds a row to the shelf
-- and leaves the four stones exactly where they were.
local MART_MAP = "CeladonMart4F"
local MART_TEXT = "TEXT_CELADONMART4F_CLERK"

-- Bag.remove's rule, without requiring the module: drop the count, and drop
-- the id out of the bag order when it hits zero.
local function takeOne(save, id)
  local inventory = save and save.inventory
  if not inventory or not inventory[id] then return false end
  inventory[id] = inventory[id] - 1
  if inventory[id] <= 0 then
    inventory[id] = nil
    local order = save.bagOrder
    if order then
      for i = #order, 1, -1 do
        if order[i] == id then table.remove(order, i) end
      end
    end
  end
  return true
end

local function tradeEvolutionOf(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  for _, evo in ipairs((def or {}).evolutions or {}) do
    if evo.method == "TRADE" and evo.species then return evo.species end
  end
  return nil
end

-- An electric snap in the game's own timbre.  Nothing in Gen 1's twenty-odd
-- effects is electric -- Turn_Off_PC is the closest "the machine stopped"
-- fallback -- so this registers a real one rather than borrowing a poor fit.
-- ChipAsm is one of the three engine modules the mod surface points authors
-- at, so this needs no permission.
local function registerSfx(mod)
  local ok, ChipAsm = pcall(require, "src.audio.ChipAsm")
  if not ok or not ChipAsm then
    mod.log:warn("ChipAsm unavailable; the cable will snap silently")
    return false
  end
  local built, program = pcall(ChipAsm.sfx, {
    channels = {
      -- a fast downward sweep on the noise-adjacent square, then a short
      -- bright tick: "the current stopped" rather than "something exploded"
      { hw = 1, program = {
        { pitchSweep = { pace = 2, subtract = true, shift = 4 } },
        { squareNote = { len = 3, volume = 15, fade = 2, frequency = 0x7A0 } },
        { squareNote = { len = 2, volume = 11, fade = 3, frequency = 0x740 } },
        { squareNote = { len = 5, volume = 8, fade = 5, frequency = 0x6C0 } },
      } },
      { hw = 2, program = {
        { squareNote = { len = 2, volume = 12, fade = 2, frequency = 0x7B4 } },
        { squareNote = { len = 6, volume = 6, fade = 6, frequency = 0x700 } },
      } },
    },
  })
  if not built then
    mod.log:warn("cable snap sfx failed to assemble (%s); the cable will "
      .. "snap silently", tostring(program))
    return false
  end
  mod.content.sfx:register(SFX, program)
  return true
end

-- The arc.  Where the snap is two square channels going quiet, this is the
-- noise channel doing what noise is for: parameter bit 3 selects the 7-bit
-- polynomial, the short buzzy one the ROM reaches for when something is
-- meant to sound like a machine rather than like a drum, and the three
-- bursts are the flicker before it lets go.  The square channel sweeps UP
-- underneath it -- the snap sweeps down -- so the pair reads as a rise and
-- then a stop rather than as the same sound twice.
local function registerZap(mod)
  local ok, ChipAsm = pcall(require, "src.audio.ChipAsm")
  if not ok or not ChipAsm then return false end
  local built, program = pcall(ChipAsm.sfx, {
    channels = {
      { hw = 1, program = {
        { pitchSweep = { pace = 1, shift = 3 } },
        { squareNote = { len = 2, volume = 15, fade = -7, frequency = 0x600 } },
        { squareNote = { len = 2, volume = 13, fade = -7, frequency = 0x6C0 } },
        { squareNote = { len = 3, volume = 11, fade = 6, frequency = 0x760 } },
      } },
      { hw = 4, program = {
        { noiseNote = { len = 1, volume = 15, fade = 1, parameter = 0x18 } },
        { noiseNote = { len = 1, volume = 11, fade = 2, parameter = 0x28 } },
        { noiseNote = { len = 1, volume = 15, fade = 1, parameter = 0x18 } },
        { noiseNote = { len = 2, volume = 13, fade = 2, parameter = 0x21 } },
        { noiseNote = { len = 4, volume = 10, fade = 5, parameter = 0x38 } },
      } },
    },
  })
  if not built then
    mod.log:warn("cable zap sfx failed to assemble (%s); the ZzZzap page "
      .. "will be silent", tostring(program))
    return false
  end
  mod.content.sfx:register(ZAP, program)
  return true
end

function M.install(mod, ctx)
  local romText = ctx.romText

  mod.content.items:register(ITEM, {
    id = ITEM,
    name = NAME,
    price = PRICE,
    -- opens the party picker: a cable is used ON a Pokemon
    needsTarget = true,
    tossable = true,
  })

  mod.content.text_pointers:patch(MART_MAP, {
    [MART_TEXT] = { mart = { ITEM } },
  })

  local sfx = { snap = registerSfx(mod), zap = registerZap(mod) }

  -- item.use wraps the WHOLE dispatch, which is what this needs: the live
  -- game, the bag list, and the party picker, none of which an item_effects
  -- `use` function receives.  Everything that is not a LINK CABLE falls
  -- straight through, so with the mod installed and the cable unbought,
  -- using any other item is byte-for-byte what it was.
  mod.hooks:wrap("item.use", function(nextLink, game, battle, id, target,
                                      list, moveIndex, picker)
    if id ~= ITEM then
      return nextLink(game, battle, id, target, list, moveIndex, picker)
    end
    -- In battle there is nothing to plug into.  Falling through gives the
    -- engine's own "OAK: ... not the time to use that!" refusal rather than
    -- a second wording of it.
    if battle then
      return nextLink(game, battle, id, target, list, moveIndex, picker)
    end

    local TextBox = mod.ui.TextBox
    local function closePicker()
      if picker then picker:close() end
    end

    local into = target and tradeEvolutionOf(game.data, target.species)
    if not into then
      game.stack:push(TextBox.new(game,
        romText(game.data, "_ItemUseNoEffectText",
          "It won't have any\neffect."), closePicker))
      return
    end

    local speciesDef = game.data.pokemon[target.species]
    local oldName = target.nickname or (speciesDef and speciesDef.name)
      or target.species

    -- The last point at which nothing has happened yet, and therefore the
    -- one place a cancel can mean anything.  Everything after it is a trade
    -- evolution, which the cartridge has never let anyone call off: B during
    -- the animation is ignored on purpose (EvolutionState reads via="TRADE"
    -- as non-cancelable, src/ui/EvolutionState.lua), the way it is ignored
    -- for a stone.  So the question goes here, before the machine starts,
    -- and B on it is NO.
    --
    -- It also carries the one line of description Gen 1 has nowhere else to
    -- put.  The mart list is a name and a price and the bag is a name and a
    -- count -- item descriptions arrive in Gen 2 -- so the sentence that
    -- explains why a cable evolves a POKeMON with nobody on the other end
    -- has to be said by the item as it is used, or not at all.
    local function begin()

      -- The cable goes in and the machine hums.  Trade_Machine is what
      -- src/ui/TradeAnim.lua plays when a trade starts, so the player has
      -- already heard it at the Cable Club -- the strongest diegetic choice
      -- available.  The spaced periods are the engine's own beat idiom.
      game.stack:push(TextBox.new(game, ". . .", function()
        -- The "is evolving!" line STAYS up: the evolution screen clears rows
        -- 0-11 only, so this rides underneath the whole animation exactly the
        -- way the vanilla level-up evolution's box does.
        local intro
        intro = TextBox.new(game,
          romText(game.data, "_IsEvolvingText", "What?\n%s is\nevolving!",
                  oldName),
          nil,
          { stay = { onShown = function()
              -- via = "TRADE": EvolutionState reads that as non-cancelable,
              -- so it always completes, so it always breaks.
              mod.ui.push(game, "EvolutionState", target, into, function()
                -- EvolutionState has popped itself and printed "evolved
                -- into"; the intro box beneath is ours to take down.
                if game.stack:top() == intro then game.stack:pop() end
                M.breakCable(mod, game, ctx, sfx, closePicker, list)
              end, "TRADE")
            end } })
        game.stack:push(intro)
      end, TextBox.soundOpts(game, "Trade_Machine")))
    end

    game.stack:push(TextBox.new(game,
      "An old LINK CABLE,\nmodified."
        .. "\fUse it on " .. oldName .. "?",
      nil,
      { choice = function(yes)
          if yes then return begin() end
          -- Nothing was consumed and nothing evolved, so the only thing to
          -- undo is the party picker this opened over the bag.
          closePicker()
        end }))
  end)
end

-- Consumed here and nowhere else: on the far side of an evolution that
-- actually happened.
function M.breakCable(mod, game, ctx, sfx, closePicker, list)
  local TextBox = mod.ui.TextBox
  takeOne(game.save, ITEM)

  -- keep an open bag list honest about the count, the way BagMenu's own
  -- consume does after an evolution stone
  if list and list.items then
    for i, item in ipairs(list.items) do
      if item.value == ITEM then
        local left = game.save.inventory[ITEM]
        if left then item.right = "x" .. left else table.remove(list.items, i) end
        break
      end
    end
    list.index = math.min(list.index or 1, math.max(1, #list.items))
  end

  -- Three boxes rather than one string with page breaks in it, because a
  -- sound is armed per BOX: TextBox fires auto.sound when the last page of
  -- the box it is on has typed out, so ". . .\fZzZzap!\fbroke!" can only ever
  -- carry one sound, at the end.  Split, each beat gets its own.
  --
  --   ". . ."     silent -- the pause before anything is wrong
  --   "ZzZzap!"   the arc, on preSound: the box comes up, the zap fires, and
  --               only then does the word type, so the sound lands WITH the
  --               card rather than after the player has finished reading it
  --   "broke!"    the snap, the way it has always been
  local on = ctx.sfx()
  local function play(name)
    return function()
      return require("src.core.Sound").play(game.data, name)
    end
  end

  local function broke()
    game.stack:push(TextBox.new(game, "The " .. NAME .. "\nbroke!",
      closePicker, (on and sfx.snap) and TextBox.soundOpts(game, SFX)
        or nil))
  end

  local function zap()
    game.stack:push(TextBox.new(game, "ZzZzap!", broke,
      (on and sfx.zap) and { preSound = play(ZAP) } or nil))
  end

  game.stack:push(TextBox.new(game, ". . .", zap))
end

return M
