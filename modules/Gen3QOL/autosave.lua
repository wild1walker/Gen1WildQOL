-- AUTO SAVE on FireRed, LeafGreen and Emerald.
--
-- Gen1AutoSave is two and a half thousand lines because Red's save shares a
-- frame with a sync engine, a quit confirm, rollback copies and a dozen
-- screens that are not safe to write under.  None of that machinery is on a
-- GBA boot, and the cart answers the one question that matters itself:
-- `Game3:quickSaveAllowed()` is the engine's own "could the player press
-- START and save right now" -- in the field, no script pending, no window up,
-- START allowed, SAVE offered (pokeemerald src/overworld.c:1445).  So this
-- marks a save DUE and writes it through the cart's own `saveGame` on the
-- first frame that question says yes and the player is not mid-step.
--
-- Due after: a battle, a catch, an evolution, or stepping onto a different
-- map -- AFTER EVENTS -- and, if INTERVAL is set, every so much play time.
-- Never more often than once every MIN_GAP seconds, so a run through three
-- doors is one save rather than three.  A fresh load or a fresh save resets
-- the clock: nothing is new yet.
--
-- And never a NEW GAME the player has not saved.  A GBA cart has one save
-- file, and NEW GAME starts over it without a word (src/ui/game3/boot.lua);
-- the cart only asks "There is already a saved file. Is it okay to overwrite
-- it?" when the player saves by hand.  An autosave there would write a new
-- game over a forty-hour one -- and the next would take the backup with it --
-- so a new game is left alone until the player's own START > SAVE has made it
-- the save on the cart.  CONTINUE is a save the player already chose.
--
-- The indicator is a Poke Ball in the corner of the game screen for a
-- moment after each write, drawn on `render.hud` in window pixels so it
-- needs no font and sits outside the GBA's own windows.

local MIN_GAP = 15         -- seconds between two autosaves, at the least
local SHOW_FOR = 1.6       -- seconds the indicator stays up

return function(mod)
  mod.options:define({
    { key = "enabled", type = "toggle", label = "AUTO SAVE", default = true,
      help = "Save progress automatically while you play." },
    { key = "interval", type = "choice", label = "INTERVAL", default = 0,
      choices = {
        { "OFF", 0 }, { "1 MIN", 60 }, { "2 MIN", 120 }, { "5 MIN", 300 },
        { "10 MIN", 600 }, { "15 MIN", 900 },
      },
      help = "An extra save every so much play time. Off: events cover it.",
      visible_if = { key = "enabled", equals = true } },
    { key = "events", type = "toggle", label = "AFTER EVENTS", default = true,
      help = "Save after battles, catches, evolutions and new areas.",
      visible_if = { key = "enabled", equals = true } },
    { key = "notify", type = "choice", label = "INDICATOR", default = "ball",
      choices = { { "OFF", "off" }, { "POKE BALL", "ball" } },
      help = "How an autosave announces itself.",
      visible_if = { key = "enabled", equals = true } },
  })

  local state = {
    armed = false,     -- this playthrough is the save on the cart; see above
    due = false,       -- an event has happened since the last write
    clock = 0,         -- seconds of play since the last write
    since = MIN_GAP,   -- seconds since the last write, or since load
    shown = nil,       -- seconds left on the indicator
    map = nil,         -- the map the last map.entered was for
    writes = 0,
  }

  local function on() return mod.options:get("enabled") ~= false end
  local function events() return mod.options:get("events") ~= false end
  local function interval() return tonumber(mod.options:get("interval")) or 0 end

  local function settle()
    state.due, state.clock, state.since = false, 0, 0
  end

  local function mark()
    if on() and events() then state.due = true end
  end

  mod.events:on("battle.ended", mark)
  mod.events:on("pokemon.caught", mark)
  mod.events:on("pokemon.evolved", mark)
  mod.events:on("map.entered", function(event)
    local id = type(event) == "table" and (event.mapId or event.map or event.id)
      or nil
    if type(id) == "table" then id = id.id end
    if id ~= nil and id ~= state.map then
      -- The map a game boots onto is where the save already stands.  The
      -- engine says which one that is (`via = "boot"`), and on CONTINUE it
      -- enters it BEFORE it raises save.loaded (Game3:_handleBootAction), so
      -- that event cannot be the one to forget the map by.
      local boot = type(event) == "table" and event.via == "boot"
      if state.map ~= nil and not boot then mark() end
      state.map = id
    end
  end)
  mod.events:on("save.loaded", function() settle(); state.armed = true end)
  mod.events:on("save.created", function()
    settle(); state.map = nil; state.armed = false
  end)
  -- The player's own START > SAVE, or anybody else's write: it is a save, and
  -- whatever it wrote is now the save on the cart.  This never writes while
  -- unarmed, so a write seen then was the player's.
  mod.events:on("save.writing", function() settle(); state.armed = true end)

  local function standing()
    -- `require`, not `package.loaded`: the sandbox's package is a shim.
    local ok, Player = pcall(require, "src.core.game3.player")
    if not ok or type(Player) ~= "table" then return true end
    return not Player.moving
  end

  local function mayWrite(game)
    if not state.armed then return false end
    if type(game) ~= "table" or type(game.saveGame) ~= "function" then
      return false
    end
    if type(game.quickSaveAllowed) == "function" then
      local ok, allowed = pcall(game.quickSaveAllowed, game)
      if not ok or not allowed then return false end
    elseif game.phase ~= "field" then
      return false
    end
    return standing()
  end

  local function write(game)
    local ok, written = pcall(game.saveGame, game)
    settle()
    if ok and written ~= false then
      state.writes = state.writes + 1
      if mod.options:get("notify") ~= "off" then state.shown = SHOW_FOR end
      return true
    end
    mod.log:warn("autosave did not write: %s", tostring(ok and "refused" or written))
    return false
  end

  mod.hooks:wrap("core.update", function(nextFn, game, dt, ...)
    local results = { nextFn(game, dt, ...) }
    dt = tonumber(dt) or 0
    if state.shown then
      state.shown = state.shown - dt
      if state.shown <= 0 then state.shown = nil end
    end
    if not on() then return (table.unpack or unpack)(results) end
    state.since = state.since + dt
    state.clock = state.clock + dt
    local every = interval()
    if every > 0 and state.clock >= every then state.due = true end
    if state.due and state.since >= MIN_GAP and mayWrite(game) then
      write(game)
    end
    return (table.unpack or unpack)(results)
  end)

  -- ------- the indicator: a Poke Ball in the top-right of the game screen
  mod.hooks:wrap("render.hud", function(nextFn, game, viewport, ...)
    nextFn(game, viewport, ...)
    if not state.shown or type(viewport) ~= "table" then return end
    local g = love and love.graphics
    if not g then return end
    local scale = tonumber(viewport.scale) or 1
    local r = 5 * scale
    local x = (viewport.gameX or 0) + (viewport.gameWidth or 0) - r - 4 * scale
    local y = (viewport.gameY or 0) + r + 4 * scale
    local alpha = math.min(1, state.shown / 0.4)
    g.setColor(0.97, 0.23, 0.20, alpha)
    g.arc("fill", x, y, r, math.pi, 2 * math.pi)
    g.setColor(1, 1, 1, alpha)
    g.arc("fill", x, y, r, 0, math.pi)
    g.setColor(0.1, 0.1, 0.1, alpha)
    g.setLineWidth(math.max(1, scale))
    g.circle("line", x, y, r)
    g.line(x - r, y, x + r, y)
    g.setColor(1, 1, 1, alpha)
    g.circle("fill", x, y, r * 0.35)
    g.setColor(0.1, 0.1, 0.1, alpha)
    g.circle("line", x, y, r * 0.35)
  end)

  mod.exports.state = state
  mod.exports.write = write
end
