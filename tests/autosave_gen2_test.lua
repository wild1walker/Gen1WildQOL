-- AUTO SAVE on Gold, Silver and Crystal.
--
-- The bug this file is the regression test for did not look like a bug from
-- anywhere: no error, no warning, no line on the boot feed, the row reading
-- ON in the menu and the INTERVAL row under it.  AUTO SAVE simply never wrote
-- a file on a Gen 2 boot, because every question it asks about the map was
-- asked as `game.overworld` -- Red's OverworldState singleton, which Gold
-- does not have.  `writeWindow` opens with `if not (ow and ow.player)`, so it
-- answered false on every frame of every playthrough, and `writeUnderCover`
-- returned before it looked at anything.
--
-- So the assertions here are mostly of the form "this is ever true", which is
-- a weak-looking shape for a test and is exactly the right one: the thing
-- that was wrong is that a whole family of answers was constant.
--
-- The two questions with the most ways to go wrong are the ones whose answer
-- is REVERSED between the games -- an empty stack is "no menu is open" on Red
-- and "the player is standing on the map" on Gold -- so both are driven from
-- both sides here.
--
-- Run:  luajit tests/autosave_gen2_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

-- ------------------------------------------------------------- the harness

local generation = 2
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  get = function() return generation == 2 and "gold" or "red" end,
}

local function fakeMod(stored)
  local self = {
    id = "gen1_wild_qol",
    path = ".",
    exports = {},
    stored = stored or {},
    hooked = {},
  }
  self.options = {
    define = function() end,
    get = function(_, key) return self.stored[key] end,
    set = function(_, key, value) self.stored[key] = value end,
  }
  self.save = { get = function(_, _, fallback) return fallback end,
                set = function() end }
  self.cache = { read = function() end, write = function() end }
  self.storage = { read = function() end, write = function() end,
                   delete = function() end }
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    self.log[level] = function() end
  end
  self.hooks = { wrap = function(_, name, fn) self.hooked[name] = fn end }
  -- Recorded rather than dropped: `state.dirty` is set from the engine's own
  -- progress events, and "is there anything to save" is the gate the QUIT
  -- offer turns on.
  self.listeners = {}
  self.events = {
    on = function(_, name, fn)
      self.listeners[name] = self.listeners[name] or {}
      table.insert(self.listeners[name], fn)
    end,
    once = function(_, name, fn) self.events.on(_, name, fn) end,
  }
  function self.emit(name, payload)
    for _, fn in ipairs(self.listeners[name] or {}) do fn(payload) end
  end
  self.content = {}
  self.boxes = {}
  self.ui = {
    push = function() end,
    TextBox = { new = function(_game, text, _, opts)
      local box = { text = text, opts = opts }
      self.boxes[#self.boxes + 1] = box
      return box
    end },
  }
  self.world = {}
  self.find = function() return nil end
  function self:read() return nil end
  return self
end

-- SAVE ON LOADS off, which is what puts a window back on the route -- with it
-- on there is deliberately none, and "no window on the route" is the right
-- answer on both games rather than the bug under test.
local function install(gen)
  generation = gen
  local mod = fakeMod({ on_load = false })
  load_("modules/Gen1AutoSave/main.lua")(mod)
  return mod
end

local function stackOf(...)
  local states = { ... }
  local stack
  stack = {
    states = states,
    top = function() return states[#states] end,
    push = function(_, s) states[#states + 1] = s end,
    pop = function() return table.remove(states) end,
  }
  return stack
end

-- A world Gold's shape: not a stack state, with a player on it.
local function goldGame(world, ...)
  world = world or {}
  world.player = world.player or { moving = false }
  return { world = world, stack = stackOf(...) }, world
end

-- ---------------------------------------------------------------- on Gold

do
  io.write("a window exists at all on Gold\n")
  local mod = install(2)
  local writeWindow = mod.exports.writeWindow
  local state = mod.exports.veilState
  ok(type(writeWindow) == "function", "writeWindow is exposed")

  -- A real stop: STILL_FOR seconds of standing on the map doing nothing.
  local game, world = goldGame()
  state.stillFor = 5
  state.inBattle, state.outcomePending = false, false

  eq(writeWindow(game), true,
     "standing still on Gold's map is a window -- which before 0.32.24 it "
     .. "could not be, because `game.overworld` is nil there and the first "
     .. "line refused the frame")

  world.player.moving = true
  eq(writeWindow(game), false, "mid-stride is not")
  world.player.moving = false

  world.heldDir = "up"
  eq(writeWindow(game), false,
     "and neither is a direction held: Gold keeps that answer as a field "
     .. "where Red keeps it as OverworldState:dirHeld")
  world.heldDir = nil

  world.textbox = true
  eq(writeWindow(game), false, "a conversation is not a window")
  world.textbox = nil

  world.mapSetup = { phase = "out" }
  eq(writeWindow(game), false,
     "nor is a door: RunMapSetupScript is Gold's transitioning, and a write "
     .. "taken there is the animation being cut rather than covered")
  world.mapSetup = nil

  world.fieldMove = { phase = "step" }
  eq(writeWindow(game), false,
     "nor a field move's tail, which is a queued script on the cart")
  world.fieldMove = nil

  eq(writeWindow(game), true, "and with all of them clear, a window again")

  local menu = goldGame(world, { screenId = "Gen2PackMenu" })
  eq(writeWindow(menu), false,
     "a screen over the world is a refusal, not a window -- the write that "
     .. "wants a covered screen comes through loadScreenWrite instead")
end

do
  io.write("the two reversed questions\n")
  local mod = install(2)
  local screenOver, freeRoam = mod.exports.screenOver, mod.exports.freeRoam

  local plain = goldGame()
  eq(screenOver(plain), false,
     "an empty stack on Gold is the player standing on the map")
  eq(freeRoam(plain), true, "which is free roam")

  local open = goldGame(nil, { screenId = "Gen2StartMenu" })
  eq(screenOver(open), true, "one state on the stack is a screen over it")
  eq(freeRoam(open), false, "and not free roam")

  eq(screenOver({ stack = stackOf() }), false,
     "with no world at all there is nothing to be over")
end

do
  io.write("Gold's veil belongs to the world\n")
  local mod = install(2)
  local veilStepping, fullyVeiled = mod.exports.veilStepping,
                                    mod.exports.fullyVeiled
  local state = mod.exports.veilState

  -- World:runMapSetup's ramp: fadeLevel walks 1/4 .. 1 in FADE_STEPS, holds
  -- at 1 for MAP_LOAD_WHITE_FRAMES while the map loads, then walks back down.
  local game, world = goldGame()
  world.fade, world.fadeLevel = "white", 0.5
  eq(veilStepping(game), true, "half way down the ramp is an animation")
  eq(fullyVeiled(game), false, "and no window")

  state.veiled = 0
  world.fadeLevel = 1
  eq(veilStepping(game), false, "at full white it is not moving")
  eq(fullyVeiled(game), false,
     "the first frame of the hold is still not enough: this frame being "
     .. "solid says nothing about the next")
  eq(fullyVeiled(game), true,
     "the second is -- and Gold's hold is thirteen frames, so asking for two "
     .. "costs the same one frame it costs on Red's staircase")

  world.fade, world.fadeLevel = nil, nil
  eq(fullyVeiled(game), false, "and the moment the veil lifts, no")

  -- A mod's own fade is still a STATE on either game, and still has the first
  -- word about what is on the screen.
  local ramp = { alpha = function() return 0.4 end }
  local overRamp = goldGame(nil, ramp)
  eq(veilStepping(overRamp), true, "a state's own alpha() is asked first")
end

-- ----------------------------------------------------------------- on Red

do
  io.write("and none of it changed on Red\n")
  local mod = install(1)
  local writeWindow = mod.exports.writeWindow
  local screenOver, freeRoam = mod.exports.screenOver, mod.exports.freeRoam
  local state = mod.exports.veilState

  -- Red's overworld IS the stack state, and Game holds it at `overworld`.
  local ow = { player = { moving = false }, scriptMoves = {} }
  local game = { overworld = ow, stack = stackOf(ow) }

  state.stillFor = 5
  state.inBattle, state.outcomePending = false, false
  eq(writeWindow(game), true, "standing still on the route is still a window")
  eq(screenOver(game), false,
     "the overworld being the top state is NOT a screen over it")
  eq(freeRoam(game), true, "it is free roam")

  local menu = { overworld = ow, stack = stackOf(ow, { name = "BAG" }) }
  eq(screenOver(menu), true, "a menu on top of it is")
  eq(freeRoam(menu), false, "and is not free roam")
  eq(writeWindow(menu), false, "and is a refusal")

  ow.transitioning = true
  eq(writeWindow(game), false, "a warp's fade is still read off the overworld")
  ow.transitioning = nil

  ow.engaging = true
  eq(writeWindow(game), false,
     "and so is the trainer-spotted hold, which Gold has no pair of flags "
     .. "for because there it is an applymovement inside a script")
  ow.engaging = nil

  -- The empty stack, which is the reversal in one line.
  eq(freeRoam({ overworld = ow, stack = stackOf() }), false,
     "an empty stack on Red is NOT free roam -- there is no overworld on it")
end

-- ------------------------------------------------------- how big a GB pixel is

do
  io.write("the indicator's scale\n")

  -- Gold's payload.  Game2:viewport builds all of it from Chrome.fitScale,
  -- which is computed in LOVE window units, and publishes gameWidth as
  -- 160 * scale -- so `scale` there is ALREADY units per GB pixel.
  local gold = install(2).exports.hudScale
  ok(type(gold) == "function", "hudScale is exposed")

  local sx, sy = gold({ scale = 2, dpiX = 3, dpiY = 3,
                        gameWidth = 320, gameHeight = 288 }, 320)
  eq(sx, 2, "a POKe BALL on Gold is drawn at the payload's own scale")
  eq(sy, 2, "on both axes")

  -- The bug, stated as the number it produced: dividing by the DPI a second
  -- time left an eight-pixel ball two thirds of a unit across on a 3x phone,
  -- which is what "super tiny" was.
  ok(sx ~= 2 / 3, "and NOT that scale divided by the display's DPI again")

  -- Red's payload.  `scale` is Sp -- framebuffer pixels per GB pixel -- and
  -- gameWidth is in units, so the unit scale is Sp/dpi and always was.
  local red = install(1).exports.hudScale
  local rx, ry = red({ scale = 6, dpiX = 3, dpiY = 3,
                       gameWidth = 320, gameHeight = 288 }, 320)
  eq(rx, 2, "on Red the payload's scale is still divided by the DPI")
  eq(ry, 2, "on both axes")

  -- At DPI 1 the two payloads agree, which is why this was invisible on a
  -- plain desktop and only ever reported from a phone.
  eq(({ gold({ scale = 4, dpiX = 1, dpiY = 1 }, 640) })[1], 4,
     "at DPI 1 Gold's answer is the scale itself")
  eq(({ red({ scale = 4, dpiX = 1, dpiY = 1 }, 640) })[1], 4,
     "and so is Red's -- the same number by two routes")

  -- A payload missing the field falls back to the playfield width, on both.
  eq(({ gold({}, 640) })[1], 4, "no scale at all falls back to gameWidth/160")
  eq(({ red({ scale = 0 }, 640) })[1], 4, "and so does a scale of zero")
end

-- --------------------------------------------------- ON QUIT, on both games
--
-- Red's START menu rows are CALLBACKS: `{ label, onSelect = function() ... }`.
-- Gold's are VALUES: `{ label, value = "quit", desc, translateLabel }`, and
-- `StartMenu:choose` dispatches on the value.  So a hook that only wrapped
-- `onSelect` skipped Gold's QUIT row entirely and the save was never offered
-- -- reported as "doesn't ask you to save before quitting", which is exactly
-- what it did: nothing, silently.

local function quitRow(mod, game, row)
  local hook = mod.hooked["ui.start_menu.items"]
  assert(type(hook) == "function", "the START menu hook was never wrapped")
  local out = hook(function(_g, items) return items end, game, { row })
  for _, entry in ipairs(out) do
    if entry.label == "QUIT" then return entry end
  end
  return nil
end

-- Everything quitSaveOffered asks of the game, in Gold's shape.
local function quitGame(mod)
  local game, world = goldGame({ script = nil, fade = nil })
  game.save = { player = { name = "GOLD" } }
  game.writeSave = function() return true end
  game.returnToTitle = function() game.quit = (game.quit or 0) + 1 end
  return game, world
end

do
  io.write("Gold's QUIT row is a value, not a callback\n")
  local mod = install(2)
  mod.stored.enabled = true
  mod.stored.onquit = true
  local game = quitGame(mod)
  -- the shape src/ui/gen2/StartMenu.lua builds
  local row = { label = "QUIT", value = "quit", translateLabel = true }
  local taken = quitRow(mod, game, row)

  ok(taken, "the row is still on the menu")
  eq(type(taken.onSelect), "function", "and it is taken over")
  -- Gold's own arm for a mod row is `item.onSelect and item.value == nil`, so
  -- the two are exclusive there: taking the row means taking the value off it.
  eq(taken.value, nil,
     "with the value removed, or Gold would dispatch on it and never reach "
     .. "the callback")
end

do
  io.write("with something to save, QUIT offers to save\n")
  local mod = install(2)
  mod.stored.enabled = true
  mod.stored.onquit = true
  local game = quitGame(mod)
  -- the player has walked a step, which is what marks the save dirty
  mod.emit("world.stepped", {})
  local row = quitRow(mod, game, { label = "QUIT", value = "quit" })
  local menu = { items = {}, list = {} }
  game.stack:push(menu)

  row.onSelect(game)
  eq(#mod.boxes, 1, "one box goes up")
  ok(mod.boxes[1] and mod.boxes[1].text:find("SAVE"),
     "and it says it is going to save, rather than saving behind a box that "
     .. "says nothing about it")
  eq(mod.boxes[1] and mod.boxes[1].opts and mod.boxes[1].opts.defaultNo, true,
     "with NO preselected, the way the cart's own QUIT box is")
  eq(menu.phase, nil, "the cart's own confirm does not also run")
  eq(game.quit, nil, "and nothing has quit yet")
end

do
  io.write("with nothing to save, the cart's own QUIT box is put back\n")
  local mod = install(2)
  mod.stored.enabled = true
  mod.stored.onquit = true
  local game = quitGame(mod)
  -- no progress events: a clean save has nothing to offer, and the vanilla
  -- prompt is the honest one because it promises nothing
  local row = quitRow(mod, game, { label = "QUIT", value = "quit" })
  local menu = { items = {}, list = {} }
  game.stack:push(menu)

  row.onSelect(game)
  eq(#mod.boxes, 0, "no offer")
  -- StartMenu:choose's own quit arm, which is what the value would have hit
  eq(menu.phase, "confirm", "the cart's confirm comes up instead")
  eq(menu.confirmChoice, 2, "with NO preselected, exactly as the cart sets it")
  eq(game.quit, nil, "and nothing has quit")
end

do
  io.write("Red's QUIT row is still a callback and still wrapped\n")
  local mod = install(1)
  mod.stored.enabled = true
  mod.stored.onquit = true
  local game = quitGame(mod)
  mod.emit("world.stepped", {})
  local ran = 0
  local row = quitRow(mod, game,
    { label = "QUIT", onSelect = function() ran = ran + 1 end })
  eq(type(row.onSelect), "function", "the row is wrapped")
  row.onSelect()
  eq(#mod.boxes, 1, "and the offer goes up in front of the engine's prompt")
  eq(ran, 0, "which replaces it rather than stacking on it")
end

do
  io.write("ON QUIT off leaves the row alone\n")
  local mod = install(2)
  mod.stored.enabled = true
  mod.stored.onquit = false
  local game = quitGame(mod)
  local row = quitRow(mod, game, { label = "QUIT", value = "quit" })
  eq(row.value, "quit", "the value is untouched")
  eq(row.onSelect, nil, "and no callback is put on it")
end

io.write(("autosave gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
