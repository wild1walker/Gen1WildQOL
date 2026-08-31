-- When autosave is allowed to spend a frame, and when it is not.
--
-- The subject is the two questions modules/Gen1AutoSave/main.lua asks about
-- the frame it is looking at, and they are here rather than folded into
-- qol_features_test.lua because both of them were WRONG in the same way and
-- nothing else in the tree could have caught either:
--
--   veilStepping  is the screen in the middle of a fade right now?
--   fullyVeiled   has it been a solid colour long enough to stall under?
--
-- Both used to be answered by looking at the OVERWORLD -- `ow.transitioning`,
-- `ow.teleportOut` -- and most fades in this game are not the overworld's.
-- The end of a battle is a stack STATE with a veil of its own, and both of
-- those flags are false the whole way through it, so the frames of the fade
-- out of a battle were treated as the quietest in the game.  They are the
-- ones a player watches most closely.
--
-- Neither question needs an engine: a state is anything with an `alpha()`,
-- and a stack is a table with a `top`.  So both are driven here directly.
--
-- Run:  luajit tests/autosave_veil_test.lua

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

-- Enough of the mod table for the entry chunk to install against.  Nothing
-- here is asserted on; it exists so the file runs to the end and publishes
-- its exports.
local function fakeMod()
  local self = {
    id = "gen1_wild_qol",
    path = ".",
    exports = {},
    stored = {},
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
  self.events = { on = function() end, once = function() end }
  self.content = {}
  self.ui = { push = function() end }
  self.world = {}
  self.find = function() return nil end
  function self:read() return nil end
  return self
end

local mod = fakeMod()
local chunk = load_("modules/Gen1AutoSave/main.lua")
assert(type(chunk) == "function", "Gen1AutoSave should return an installer")
chunk(mod)

local veilStepping = mod.exports.veilStepping
local fullyVeiled = mod.exports.fullyVeiled
local state = mod.exports.veilState

ok(type(veilStepping) == "function", "veilStepping is exposed")
ok(type(fullyVeiled) == "function", "fullyVeiled is exposed")

-- A game whose stack has one state on top of it.
local function gameWith(top)
  return { stack = { states = { top }, top = function() return top end } }
end

-- The engine's own fades are palette STAIRCASES: a step is held for eight
-- frames, so a full veil is eight frames of full veil.
local function staircase(alphas)
  local s = { i = 0, alphas = alphas }
  function s:alpha() return self.alphas[self.i] or 0 end
  function s:step() self.i = self.i + 1 end
  return s
end

-- ------------------------------------------------------------ the answers

io.write("a veil that is stepping is an animation\n")
do
  eq(veilStepping(nil), false, "no game, nothing to say")
  eq(veilStepping({}), false, "no stack either")
  eq(veilStepping(gameWith({})), false,
    "a state with no alpha() is not a veil at all -- a menu, a text box")

  local fade = staircase({ [1] = 0.25, [2] = 0.5, [3] = 0.75, [4] = 1 })
  local game = gameWith(fade)
  fade:step()
  eq(veilStepping(game), true, "a quarter of the way down is moving")
  fade:step()
  eq(veilStepping(game), true, "...and half")
  fade:step()
  eq(veilStepping(game), true, "...and three quarters")
  fade:step()
  eq(veilStepping(game), false,
    "at full black it is NOT moving: that is the frame worth spending, and "
    .. "refusing it would give back the door freeze this all exists to remove")

  local live = staircase({ [1] = 0 })
  live:step()
  eq(veilStepping(gameWith(live)), false,
    "and alpha 0 is the picture itself, not a veil on its way anywhere")

  local raiser = { alpha = function() error("no") end }
  eq(veilStepping(gameWith(raiser)), false,
    "a state whose alpha() raises is not allowed to take the frame down")
end

io.write("a full veil has to have STAYED full\n")
do
  -- the engine's post-battle return: ten frames of held white, then a
  -- three-step fade.  Every version of this passed on the first frame.
  local hold = staircase({ [1] = 1, [2] = 1, [3] = 1, [4] = 2 / 3, [5] = 1 / 3 })
  local game = gameWith(hold)

  state.veiled = 0
  hold:step()
  eq(fullyVeiled(game), false,
    "the first frame of a hold is not enough: this frame being solid says "
    .. "nothing about the next one")
  hold:step()
  eq(fullyVeiled(game), true, "the second is -- the hold is real")
  hold:step()
  eq(fullyVeiled(game), true, "and it stays true for the rest of it")
  hold:step()
  eq(fullyVeiled(game), false, "the moment it starts stepping, no")
end

io.write("a LINEAR fade offers no window, and used to offer its worst frame\n")
do
  -- Gen1WildUI's BLACK OUTRO before it was given a hold: 0 -> 1 over 36
  -- frames, touching 1 on exactly one frame -- the cut, where the fade pops
  -- itself off the stack, runs the engine's own finish and pushes itself
  -- back.  The single most expensive frame of the whole outro, and the only
  -- one that ever answered yes.
  local ramp = { t = 0, frames = 36, phase = "out" }
  function ramp:alpha()
    local a = (self.phase == "out") and (self.t / self.frames)
      or (1 - self.t / self.frames)
    return math.max(0, math.min(1, a))
  end
  local game = gameWith(ramp)

  state.veiled = 0
  local windows, peaks = 0, 0
  for _ = 1, 36 do
    ramp.t = ramp.t + 1
    if ramp.t >= ramp.frames then ramp.phase, ramp.t = "in", 0 end
    if ramp:alpha() >= 1 then peaks = peaks + 1 end
    if fullyVeiled(game) then windows = windows + 1 end
  end
  for _ = 1, 36 do
    ramp.t = ramp.t + 1
    if fullyVeiled(game) then windows = windows + 1 end
  end

  eq(peaks, 1, "the ramp is at full black for exactly one frame")
  eq(windows, 0,
    "and it is not a window: a ramp has no covered moment to give, so the "
    .. "write waits for one that has")
end

io.write("a hold in the middle of a ramp IS a window\n")
do
  -- ...which is what Gen1WildUI Nightly's BLACK OUTRO does now: out, hold at
  -- the cut the way the engine's own return holds, then in.
  local outro = { t = 0, frames = 36, hold = 10, phase = "out" }
  function outro:alpha()
    if self.phase == "hold" then return 1 end
    local a = (self.phase == "out") and (self.t / self.frames)
      or (1 - self.t / self.frames)
    return math.max(0, math.min(1, a))
  end
  local game = gameWith(outro)

  state.veiled = 0
  local windows = 0
  for _ = 1, 36 do
    outro.t = outro.t + 1
    if outro.t >= outro.frames then outro.phase, outro.t = "hold", 0 end
    if fullyVeiled(game) then windows = windows + 1 end
  end
  eq(windows, 0, "nothing during the fade out")
  for _ = 1, outro.hold do
    outro.t = outro.t + 1
    if fullyVeiled(game) then windows = windows + 1 end
  end
  -- The settle frame is the CUT itself -- the frame the fade flips to "hold"
  -- on, which is also the frame it pops itself off the stack, runs the
  -- engine's finish and pushes itself back.  Spending that one on a save was
  -- the old behaviour and the whole complaint; it is now the frame that only
  -- counts, and every frame of the hold after it is a window.
  eq(windows, outro.hold,
    "so the write lands inside the hold, never on the cut")
end

io.write("a battle drops whatever the counter had\n")
do
  -- writeUnderCover clears it on the way past, so a count left over from
  -- before a battle cannot be spent on the first covered frame after it.
  local hold = staircase({ [1] = 1, [2] = 1 })
  local game = gameWith(hold)
  state.veiled = 0
  hold:step()
  fullyVeiled(game)
  eq(state.veiled, 1, "one frame counted")
  state.veiled = 0                     -- what the inBattle guard does
  hold:step()
  eq(fullyVeiled(game), false, "so the frame after a battle settles again")
end

-- ------------------------------------------- and when the ROUTE is a window

io.write("the route is not a window while a covered screen is coming\n")
do
  -- Two windows used to open on the route: STILL_FOR seconds of standing
  -- still, and SETTLE_GRACE seconds after a menu or a conversation handed
  -- control back.  Both are in plain sight -- the player is standing on the
  -- overworld looking at it -- and the second is the frame they have been
  -- WAITING for, so the hitch lands in the first stride out of a menu.
  --
  -- `quietFrame` already refused to take the grace window while SAVE ON LOADS
  -- was on; `writeWindow` did not, so on the default build a save landed the
  -- moment a menu closed. Reported as "closing menus / standing still
  -- shouldn't trigger an auto save", which is right: with a covered screen
  -- always coming there is nothing to buy on the route.
  local writeWindow = mod.exports.writeWindow
  local state = mod.exports.veilState
  ok(type(writeWindow) == "function", "the question is exposed")

  local game = { overworld = { player = { moving = false } }, stack = {} }
  state.inBattle = false
  state.clock = 100
  state.stillFor = 99          -- long past STILL_FOR
  state.settledAt = 100        -- and a menu closed this very frame

  mod.stored.on_load = true
  eq(writeWindow(game), false,
    "with SAVE ON LOADS on, neither a real stop nor a just-closed menu is a "
    .. "window: the next door takes the save instead")

  mod.stored.on_load = false
  eq(writeWindow(game), true,
    "with it off the route is the only place a save can go, so a real stop "
    .. "is a window again")

  state.stillFor = 0
  eq(writeWindow(game), true,
    "...and so is the moment a menu handed control back")

  state.settledAt = nil
  eq(writeWindow(game), false,
    "but walking on with neither is still no window at all")

  mod.stored.on_load = nil
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
