-- Gen1Remember: a POKéMON can be taught a move it has forgotten.
--
-- Gen 1 has no move reminder.  A move that scrolled off the top of the four
-- slots on the way up is gone for the rest of the save, and the only thing
-- the cartridge ever offers back is a TM you have to own.  This puts a
-- REMEMBER row in the popup you already open on a POKéMON and hands the move
-- back, out of the learnset it should have had it from.
--
-- Two surfaces, one screen behind both:
--
--   the party menu   through the engine's own ui.party.submenu hook, which
--                    is built for this -- HandlePartyMenuInput dispatches a
--                    hook-injected row by calling its onSelect, so the row
--                    needs no engine change and no permission
--   the box          through the extension point Gen1BillsBox publishes on
--                    its own popup, asked for at game.ready rather than at
--                    load so no load order has to be true for it to work
--
-- Not in battle.  The submenu there is SWITCH / STATS / CANCEL and the hook
-- carries ctx.battle to say so; a move learned mid-turn is a mechanic, not a
-- convenience, and this mod is the second thing.
--
-- The two siblings are loaded rather than required because a mod cannot put
-- itself on package.path: mod:read hands back the file's source from wherever
-- the mod actually lives (an installed directory, or inside an imported
-- .zip), and load() names the chunk after that path so a syntax error in
-- relearn.lua reports as relearn.lua and not as a line in this file.  The
-- same pattern the rest of the set uses.

local function loadSibling(mod, name)
  local source, readErr = mod:read(name)
  if not source then
    mod.log:error("%s is missing (%s); reinstall the mod", name,
                  tostring(readErr or "unknown read error"))
    return nil
  end
  local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s did not compile: %s", name, tostring(compileErr))
    return nil
  end
  local ok, value = pcall(chunk)
  if not ok then
    mod.log:error("%s failed to run: %s", name, tostring(value))
    return nil
  end
  return value
end

return function(mod)
  mod.options:define({
    -- The REMEMBER row in the party menu's per-mon popup.  This is the one
    -- surface that needs nothing else installed, so it is the one that is on.
    { key = "party_row", type = "toggle", label = "PARTY REMEMBER",
      default = true },
    -- The same row in the box popup, which only exists with Gen1BillsBox
    -- installed.  On by default and simply inert without it: a toggle that
    -- turns nothing off is better than one that appears and disappears with
    -- another mod.
    { key = "box_row", type = "toggle", label = "BOX REMEMBER",
      default = true },
    -- Moves from the forms this POKéMON evolved out of, not just its own.
    -- Off is the later-generation move reminder's rule -- current species
    -- only -- for anyone who wants evolving to be a door that shuts.
    { key = "pre_evolutions", type = "toggle", label = "PRE-EVO MOVES",
      default = true },
    -- A POKéMON with nothing to remember carries no row at all.  Off leaves
    -- the row in place everywhere, where it says so instead: the setting for
    -- anyone who would rather the popup keep the same shape on every
    -- POKéMON than tell them something before they press it.
    { key = "hide_empty", type = "toggle", label = "HIDE WHEN EMPTY",
      default = true },
  })

  local Relearn = loadSibling(mod, "relearn.lua")
  local makeScreen = loadSibling(mod, "screen.lua")
  if type(Relearn) ~= "table" then
    mod.log:error("the relearn table did not build; nothing is installed")
    return
  end

  -- Published before the screen is built, and whether or not it builds: these
  -- are pure functions of the dataset and a mon, and a mod that wants the
  -- answer without opening a popup should get it even from an install whose
  -- UI half failed.
  mod.exports.pool = Relearn.pool
  mod.exports.chain = Relearn.chain
  mod.exports.any = Relearn.any

  local Screen
  if type(makeScreen) == "function" then
    local ok, built = pcall(makeScreen, mod, Relearn)
    if ok and type(built) == "table" then Screen = built end
  end
  if not Screen then
    mod.log:error("the REMEMBER popup did not build; no row is added")
    return
  end
  mod.exports.open = Screen.open
  mod.exports.teach = Screen.teach
  mod.exports.available = Screen.available

  local Strings = require("src.core.Strings")

  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  -- Whether this POKéMON should carry the row right now.  Wrapped in pcall
  -- because it is asked from inside somebody else's menu build: a party menu
  -- that fails to OPEN is a great deal worse than one without a REMEMBER row,
  -- so a throw in here costs the row and nothing else.
  local function shouldOffer(game, mon)
    if not option("hide_empty", true) then return true end
    local ok, available = pcall(Screen.available, game, mon)
    if not ok then
      mod.log:warn("the pool could not be read for this POKéMON (%s); the "
        .. "row is left off rather than shown as a refusal", tostring(available))
      return false
    end
    return available
  end

  local function row(game, mon)
    return {
      label = Strings("REMEMBER"),
      -- The party menu dispatches a hook-injected row as onSelect(mon, game)
      -- (src/ui/PartyMenu.lua); the box provider has no arguments to give and
      -- calls it bare.  Taking both and falling back on the pair this row was
      -- built for is what lets one row serve both callers.
      onSelect = function(whichMon, whichGame)
        Screen.open(whichGame or game, whichMon or mon)
      end,
    }
  end

  -- ------- the party menu
  --
  -- Appended after the vanilla rows rather than inserted among them.  The
  -- order at the FRONT of that list is load bearing: DisplayFieldMoveMonMenu
  -- indexes wFieldMoves with menu items 0..n-1, so the field moves have to
  -- stay at the top and STATS / SWITCH at the bottom of what the engine
  -- built.  The end of the list is the one place a new row is free.
  --
  -- next() first and then decorate, so a mod that inserted a row of its own
  -- still has it.
  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local out = next(game, items, mon, ctx)
    if type(out) ~= "table" then return out end
    if not option("party_row", true) then return out end
    -- SWITCH / STATS / CANCEL, mid-battle: not a place to be teaching moves
    if ctx and ctx.battle then return out end
    if not (mon and mon.species) then return out end
    if not shouldOffer(game, mon) then return out end
    out[#out + 1] = row(game, mon)
    return out
  end)

  -- ------- the box
  --
  -- Gen1BillsBox owns its popup and publishes a provider registry on it, the
  -- same shape Gen1Dex publishes for its AREA caption.  Asked for at
  -- game.ready rather than at load because load order is not something this
  -- mod should have to be right about: priority ties break by id, optional
  -- dependencies do not order anything, and a player can install the two in
  -- either order.  By game.ready every mod that is going to load has.
  --
  -- game.ready also fires on a hot reload, which is why the registration is
  -- owner-keyed: without an owner the second load would stack a second
  -- provider closed over the first load's tables, and the stale one would be
  -- the one that answered.
  mod.events:on("game.ready", function()
    if not option("box_row", true) then return end
    local box = mod.find("Gen1BillsBox")
    local actions = box and box.exports and box.exports.actions
    if not (actions and type(actions.provide) == "function") then return end
    local ok, err = pcall(actions.provide, function(game, mon, pane)
      -- the party half of the box is the party menu's own list; one REMEMBER
      -- row per POKéMON is enough, and the box pane is the one the party
      -- menu cannot reach
      if not option("box_row", true) then return nil end
      if not (mon and mon.species) then return nil end
      if not shouldOffer(game, mon) then return nil end
      return { row(game, mon) }
    end, mod.id)
    if not ok then
      mod.log:warn("Gen1BillsBox refused the REMEMBER row (%s); the party "
        .. "menu still has it", tostring(err))
      return
    end
    mod.log:info("the box popup has REMEMBER too")
  end)

  mod.log:info("POKéMON can be taught what they forgot")
end
