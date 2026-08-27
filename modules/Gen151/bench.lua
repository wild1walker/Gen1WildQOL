-- The test bench (not part of normal play).
--
-- Everything Gen151 does to the encounter tables is covered by headless
-- tests.  What those cannot reach is anything that has to be seen or heard:
-- whether "ZzZzap" renders, whether the cable snap sounds like an electrical
-- fault or like a mistake, whether the AREA caption fits its box, whether
-- AREA really blinks a nest on the maps Gen151 added to -- and whether a
-- very-rare tier is a satisfying hunt or just a long one.
--
-- Reaching those in normal play means buying a cable, finding a Kadabra,
-- surfing to Cinnabar and walking through grass a few thousand times.  This
-- collapses that into a menu.
--
-- This lived in a companion mod, gen151_debug, for one release and a half.
-- That was the wrong shape: a bench you have to find, download and import
-- separately is a bench that is not there when you want it, and twice it was
-- not.  It is a file in the mod now, behind an option that defaults off, so
-- reaching it is two presses from a screen the player is already on.
--
-- Off, nothing here runs and nothing here registers.  On, it drives only the
-- public seams any mod has -- mod.world, mod.ui, and one high-priority wrap
-- on `encounter.roll` that sits ABOVE Gen151's own.

local M = {}


-- What the kit hands over, and why each one is in it.
local KIT_ITEMS = {
  { id = "LINK_CABLE", count = 5, why = "four trade evolutions and a spare" },
  { id = "SUPER_ROD", count = 1, why = "the two Super Rod placements" },
  { id = "GOOD_ROD", count = 1, why = "the rod Gen151 does NOT touch" },
  { id = "OLD_ROD", count = 1, why = "ditto" },
  { id = "POKE_FLUTE", count = 1, why = "the Route 12/16 sleepers" },
  { id = "SILPH_SCOPE", count = 1, why = "Pokemon Tower" },
}

-- One of each trade evolution's pre-form, so all four cables have somewhere
-- to go, and so the party is never empty when a forced battle starts.
local KIT_PARTY = {
  { "KADABRA", 25 }, { "MACHOKE", 30 }, { "GRAVELER", 30 }, { "HAUNTER", 30 },
}

local MEW_FLAGS = {
  "GEN151_MEW_DIARY_1", "GEN151_MEW_DIARY_2",
  "GEN151_MEW_DIARY_3", "GEN151_MEW_DIARY_4",
}
local MEW_FOUND = "GEN151_MEW_FOUND"

-- The list of things that need a human, in the order they are cheapest to
-- check.  Printed by the CHECKLIST row so the bench says what it is for.
local CHECKLIST = {
  "1 CABLE SFX.\nZap, then snap?",
  "2 BREAK BOX.\fDoes ZzZzap render\nand land AFTER\fthe evolution?",
  "3 KIT, then use a\nLINK CABLE\fon the KADABRA.\nB should cancel.",
  "4 SPAWNS ON,\nthen walk.\fEvery battle is a\nGEN151 one.",
  "5 POKeDEX, then\nAREA\fon a species you\nhave NOT met.\fIs there a hint\nunder the map?\fNeeds GEN1DEX:\nits screen now.",
  "6 DEX FILL, then\nAREA again.\fNest on the right\nmap?",
  "7 MEW: flip it\nOFF.\fAREA shows no\nnest.\fFlip ON. It does.",
  "8 CELADON MART 4F.\fIs LINK CABLE on\nthe shelf at 2100?",
  "9 DEX WRAP,\nif AREA will not\fopen on an entry\nyou have not met.",
}


-- ctx carries what the bench reads out of the resolver: the applied slot rows,
-- the Super Rod rows, and the gated-row reconciler MEW needs.
function M.install(mod, ctx)

  -- ------------------------------------------------------ the placement index

  local byMap, mapOrder, seenMap = {}, {}, {}
  local function index(row, kind)
    local key = row.map .. "|" .. kind
    local list = byMap[key]
    if not list then
      list = {}
      byMap[key] = list
    end
    list[#list + 1] = row
    if not seenMap[row.map] then
      seenMap[row.map] = true
      mapOrder[#mapOrder + 1] = row.map
    end
  end
  for _, row in ipairs(ctx.rows or {}) do
    index(row, row.method == "water" and "water" or "grass")
  end
  for _, row in ipairs(ctx.fishing or {}) do index(row, "rod") end
  table.sort(mapOrder)

  -- ------------------------------------------------------------- small tools

  local function say(game, text, onDone)
    game.stack:push(mod.ui.TextBox.new(game, text, onDone))
  end

  -- The console's own warp pops the whole stack before it moves the player.
  -- Same idea, without reaching for the overworld module: pop down to the
  -- object mod.world already resolves, so a battle or a warp starts from a
  -- clean stack instead of from under three menus.
  local function toOverworld(game)
    local ow = mod.world and mod.world:overworld()
    if not ow then return nil, "no overworld" end
    local guard = 0
    while game.stack:top() and game.stack:top() ~= ow and guard < 64 do
      game.stack:pop()
      guard = guard + 1
    end
    if game.stack:top() ~= ow then return nil, "could not reach the overworld" end
    return ow
  end

  -- Bag.add's rule, without requiring the module.
  local function giveItem(save, id, count)
    save.inventory = save.inventory or {}
    save.bagOrder = save.bagOrder or {}
    if not save.inventory[id] then
      save.bagOrder[#save.bagOrder + 1] = id
    end
    save.inventory[id] = math.min(99, (save.inventory[id] or 0) + count)
  end

  local function sound(game, name)
    local opts = mod.ui.TextBox.soundOpts(game, name)
    return opts and opts.auto and opts.auto.sound
  end

  -- --------------------------------------------------------------- the forcer
  --
  -- Wrapped ABOVE Gen151 (higher priority runs first), and it calls next()
  -- before it decides anything -- so the encounter RATE is still the vanilla
  -- roll's answer.  This forces WHAT you meet, never WHETHER you meet it,
  -- which is the only way the walk still feels like the real thing.
  local force = { on = false, seen = 0 }

  mod.hooks:wrap("encounter.roll", function(nextLink, encDef, ctx)
    local enc = nextLink(encDef, ctx)
    if not enc or not force.on then return enc end
    local kind = (ctx and ctx.terrain) == "water" and "water" or "grass"
    local rows = byMap[(ctx and ctx.mapId or "") .. "|" .. kind]
    if not rows or #rows == 0 then return enc end
    -- round robin rather than random: every placement on the map turns up,
    -- in order, so a walk covers the whole map's additions instead of
    -- rolling the same one six times
    force.seen = force.seen + 1
    local row = rows[(force.seen - 1) % #rows + 1]
    return { species = row.species, level = (row.levels or {})[1] or enc.level }
  end, FORCE_PRIORITY)

  mod.hooks:wrap("encounter.fishing", function(nextLink, rod, mapId, pool)
    local enc = nextLink(rod, mapId, pool)
    if not enc or not force.on then return enc end
    local rows = byMap[(mapId or "") .. "|rod"]
    if not rows or #rows == 0 then return enc end
    force.seen = force.seen + 1
    local row = rows[(force.seen - 1) % #rows + 1]
    return { species = row.species, level = (row.levels or {})[1] or enc.level }
  end, FORCE_PRIORITY)

  -- ------------------------------------------------------------- the actions

  local function actKit(game, list)
    local save = game.save
    for _, entry in ipairs(KIT_ITEMS) do
      if game.data.items[entry.id] then
        giveItem(save, entry.id, entry.count)
      end
    end
    list:close()
    local ow, err = toOverworld(game)
    if not ow then
      say(game, "Bag filled.\fThe party needs\nthe overworld:\f" .. tostring(err))
      return
    end
    local rows = {}
    for _, mon in ipairs(KIT_PARTY) do
      if game.data.pokemon[mon[1]] then
        rows[#rows + 1] = { "give_pokemon", mon[1], mon[2], true }
      end
    end
    local ok, why = mod.world:queueScript(rows)
    if not ok then
      say(game, "Bag filled.\nParty: " .. tostring(why))
    end
  end

  local function actCableSfx(game)
    local play = sound(game, "SFX_GEN151_CABLE_SNAP")
    if not play then
      -- The sfx is registered by linkcable.lua, which only runs when TRADE
      -- EVOS is LINK CABLE -- CABLE SOUND decides whether the snap PLAYS,
      -- not whether it exists, so naming it here sent the last reader to
      -- the wrong switch.
      say(game, "No cable sound\nis registered.\fIn MODS, Gen151,\fis TRADE EVOS set\nto LINK CABLE?")
      return
    end
    play()
  end

  -- The exact box the cable prints, without spending one: this is the row
  -- that answers "does ZzZzap render" in about four seconds.
  local function actBreakBox(game)
    local opts = mod.ui.TextBox.soundOpts(game, "SFX_GEN151_CABLE_SNAP")
    game.stack:push(mod.ui.TextBox.new(game,
      ". . .\fZzZzap!\fThe LINK CABLE\nbroke!", nil, opts))
  end

  local function actHum(game)
    local play = sound(game, "Trade_Machine")
    if play then play() end
  end

  local function actSpawnHere(game, list)
    local here = mod.world and mod.world:current()
    local mapId = here and here.mapId
    local rows = {}
    for _, kind in ipairs({ "grass", "water", "rod" }) do
      for _, row in ipairs(byMap[(mapId or "") .. "|" .. kind] or {}) do
        rows[#rows + 1] = row
      end
    end
    if #rows == 0 then
      say(game, "Nothing is placed\non\f" .. tostring(mapId) .. ".\fTry GO TO.")
      return
    end
    local items = {}
    for _, row in ipairs(rows) do
      local def = game.data.pokemon[row.species]
      items[#items + 1] = {
        label = (def and def.name) or row.species,
        right = "L" .. tostring((row.levels or {})[1] or "?"),
        row = row,
      }
    end
    game.stack:push(mod.ui.ListMenu.new(game, "SPAWN HERE", items, {
      onChoose = function(item, inner)
        inner:close()
        list:close()
        if not toOverworld(game) then return end
        local ok, why = mod.world:startWildBattle(
          item.row.species, (item.row.levels or {})[1] or 5)
        if not ok then say(game, tostring(why)) end
      end,
    }))
  end

  local function actGoTo(game, list)
    local items = {}
    for _, mapId in ipairs(mapOrder) do
      items[#items + 1] = { label = mapId:gsub("_", " "), map = mapId }
    end
    game.stack:push(mod.ui.ListMenu.new(game, "GO TO", items, {
      onChoose = function(item, inner)
        inner:close()
        list:close()
        if not toOverworld(game) then return end
        local ok, why = mod.world:warpTo(item.map, 5, 5, "down")
        if not ok then say(game, tostring(why)) end
      end,
    }))
  end

  local function mewOn()
    return mod.world and mod.world:getFlag(MEW_FOUND) == true
  end

  -- Whether Gen151 has a MEW row to gate at all.  With MEW EVENT switched
  -- off, the gate is never installed, so flipping the flag moves nothing and
  -- the row was quietly doing nothing at all -- which is precisely what it
  -- looked like from the outside.
  local function mewPlaced()
    for _, row in ipairs(ctx.rows or {}) do
      if row.species == "MEW" then return true end
    end
    return false
  end

  local function actMew(game, list, item)
    if not mewPlaced() then
      say(game, "MEW is not placed.\fTurn MEW EVENT on\fin this mod's own\noptions.")
      return
    end
    local turnOn = not mewOn()
    for _, flag in ipairs(MEW_FLAGS) do
      mod.world:setFlag(flag, turnOn or nil)
    end
    mod.world:setFlag(MEW_FOUND, turnOn or nil)
    -- ask Gen151 to reconcile the encounter table with the flag, which is
    -- what the dex AREA screen reads
    if type(ctx.syncGated) == "function" then ctx.syncGated() end
    item.label = turnOn and "MEW: FOUND" or "MEW: HIDDEN"
    -- The label changing is the only thing this used to do, and a two-word
    -- label two rows down is not a confirmation.  Say it.
    say(game, turnOn
      and "Journals read.\fMEW is in the\ntable now."
      or "Journals cleared.\fMEW is out of\nthe table.")
  end

  local function actDexFill(game)
    local dex = game.save.pokedex
    if not dex then
      say(game, "This save has no\nPOKeDEX yet.")
      return
    end
    local n = 0
    for id, def in pairs(game.data.pokemon) do
      if def.dex and not dex.seen[id] then
        dex.seen[id] = true
        n = n + 1
      end
    end
    say(game, ("Marked %d species\nas SEEN."):format(n)
      .. "\fAREA works on any\nentry now.")
  end

  -- Every link that has to hold for a press on an undiscovered dex entry to
  -- open AREA, named.  This exists because the last report of that not
  -- working could not be reproduced from the outside, and the difference
  -- between "the rows were replaced" and "the A handler was replaced" decides
  -- which fix is the right one.  Most of that chain is Gen1Dex's now -- the
  -- screen is its screen -- so most of this line comes back from its probe;
  -- what this mod adds is whether its own words were ever handed over.
  local function actDexWrap(game)
    if type(ctx.dexProbe) ~= "function" then
      say(game, "AREA HINTS is off\nin this mod's\foptions, or\fGEN1DEX is not\ninstalled -- and\fthat screen is\nits screen.")
      return
    end
    say(game, ctx.dexProbe(game))
  end

  local function actChecklist(game)
    say(game, table.concat(CHECKLIST, "\f"))
  end

  -- ---------------------------------------------------------------- the bench

  local SCREEN = "Gen151DebugBench"

  mod.content.screens:register(SCREEN, {
    new = function(game)
      local items = {
        { label = "CHECKLIST", act = function(_, _) actChecklist(game) end },
        { label = "KIT", act = actKit },
        { label = force.on and "SPAWNS: ON" or "SPAWNS: OFF",
          act = function(_, list, item)
            force.on = not force.on
            item.label = force.on and "SPAWNS: ON" or "SPAWNS: OFF"
          end },
        { label = "SPAWN HERE", act = actSpawnHere },
        { label = "GO TO", act = actGoTo },
        { label = "CABLE SFX", act = function(_, _) actCableSfx(game) end },
        { label = "CABLE HUM", act = function(_, _) actHum(game) end },
        { label = "BREAK BOX", act = function(_, list)
            list:close()
            actBreakBox(game)
          end },
        { label = mewOn() and "MEW: FOUND" or "MEW: HIDDEN", act = actMew },
        { label = "DEX FILL", act = function(_, _) actDexFill(game) end },
        { label = "DEX WRAP", act = function(_, _) actDexWrap(game) end },
      }
      return mod.ui.ListMenu.new(game, "GEN151 BENCH", items, {
        footer = ("%d rows on %d maps"):format(
          #(ctx.rows or {}) + #(ctx.fishing or {}), #mapOrder),
        onChoose = function(item, list)
          if item.act then item.act(game, list, item) end
        end,
      })
    end,
  })

  -- ------------------------------------------------------------- two doors
  --
  -- The bench first had one way in, appended to OPTIONS, and that turned out
  -- to be no way in at all: OPTIONS shows FOUR rows at a time
  -- (OptionRows.VISIBLE) over a list about thirty long on a desktop build, so
  -- an appended row sat seven screenfuls down, under a moreArrow, at the very
  -- bottom.  Opening OPTIONS and concluding it is not there is the correct
  -- reading of what that screen shows.
  --
  -- So: two doors, both above the fold, and neither of them an install.

  -- One, in OPTIONS, spliced next to MODS rather than appended.  MODS is
  -- where the player just was -- the bench is switched on from Gen151's own
  -- options, one screen inside it -- so this lands in the screenful they are
  -- looking at on the way back out.  next() first, and append if some other
  -- mod removed the MODS row, so nothing here can orphan the entry or eat
  -- another mod's rows.
  mod.hooks:wrap("ui.options.rows", function(nextLink, game, rows)
    local out = nextLink(game, rows)
    if type(out) ~= "table" then return out end
    local row = {
      id = "gen151_bench",
      label = "GEN151 BENCH",
      value = function() return force.on and "FORCED" or "OPEN" end,
      activate = function(g) mod.ui.push(g, SCREEN) end,
    }
    local at = #out + 1
    for i, existing in ipairs(out) do
      if existing.id == "mods" then
        at = i + 1
        break
      end
    end
    table.insert(out, at, row)
    return out
  end)

  -- Two, at the top of the START menu, which is the door that cannot be
  -- missed: it is a short list, the bench belongs at hand while walking
  -- through grass, and a mod that replaces the OPTIONS screen wholesale
  -- cannot take this one away as well.  It displaces POKeDEX by one row,
  -- which is why the option that gets here defaults off.
  --
  -- Menu:select pops the menu BEFORE it calls onSelect (src/ui/Menu.lua), so
  -- a plain push here lands on a clean stack -- the same shape POKeDEX uses.
  mod.hooks:wrap("ui.start_menu.items", function(nextLink, game, items)
    local out = nextLink(game, items)
    if type(out) ~= "table" then return out end
    table.insert(out, 1, {
      label = "BENCH",
      onSelect = function() mod.ui.push(game, SCREEN) end,
    })
    return out
  end)

  mod.log:info("bench installed: %d rows on %d maps; START -> BENCH, or "
    .. "OPTIONS -> GEN151 BENCH (beside MODS)",
    #(ctx.rows or {}) + #(ctx.fishing or {}), #mapOrder)
end

return M
