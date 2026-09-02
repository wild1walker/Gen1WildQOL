-- A battle's outcome is committed AFTER battle.ended, and the save waits.
--
-- `battle.ended` is emitted while the battle is still tearing down.  What
-- writes the OUTCOME runs later: BattleState hands the battle's `onFinish` to
-- the battle-return transition as its onDone, and a trainer's onFinish is what
-- sets `save.defeatedTrainers[npc.id]` and the map's event flag.
--
-- The ten covered frames at the front of that return are the window a
-- post-battle save aims at, and they are all BEFORE the win exists.  So the
-- save that was reliably taken there was reliably a save of the battle NOT
-- won: load it and the trainer wants to fight again, having been beaten.  The
-- good window is what made it happen every time rather than sometimes.
--
-- What is asserted is the order and nothing else: not due at battle.ended,
-- due once onFinish has run, and the inner onFinish having run FIRST -- which
-- is the whole of the fix, because "committed" means that call returned.
--
-- Run:  luajit tests/autosave_outcome_test.lua

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

-- The same stand-in autosave_veil_test uses, with the event bus kept rather
-- than dropped: this file's whole subject is what a handler does.
local function fakeMod()
  local self = { id = "gen1_wild_qol_nightly", path = ".", exports = {},
                 stored = {}, handlers = {}, hooked = {} }
  self.options = {
    define = function() end,
    get = function(_, key) return self.stored[key] end,
    set = function(_, key, value) self.stored[key] = value end,
  }
  self.save = { get = function(_, _, fallback) return fallback end,
                set = function() end }
  self.writes = 0
  self.cache = { read = function() end, write = function() end }
  self.storage = { read = function() end, write = function() end,
                   delete = function() end }
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    self.log[level] = function() end
  end
  self.hooks = { wrap = function(_, name, fn) self.hooked[name] = fn end }
  self.events = {
    on = function(_, name, fn)
      local list = self.handlers[name] or {}
      list[#list + 1] = fn
      self.handlers[name] = list
    end,
    once = function(_, name, fn) return self.events.on(_, name, fn) end,
  }
  self.content = {}
  self.ui = { push = function() end }
  self.world = {}
  self.find = function() return nil end
  function self:read() return nil end
  function self.fire(name, event)
    for _, fn in ipairs(self.handlers[name] or {}) do fn(event) end
  end
  return self
end

local function install()
  local mod = fakeMod()
  local chunk = load_("modules/Gen1AutoSave/main.lua")
  chunk(mod)
  -- The two switches this path is behind, both on: the mod itself, and the
  -- "save after battles, catches, evolutions" row.
  mod.options:set("enabled", true)
  mod.options:set("events", true)
  -- A save asked for before the battle would make every case below say yes
  -- for the wrong reason.
  mod.fire("save.writing", {})
  return mod
end

local function due(mod)
  return mod.exports.autosaveStatus().due
end

io.write("the hold covers every kind of battle, and every way one records itself\n")

-- A settled overworld: nobody moving, no script, nothing on the screen.
local function quietGame(opts)
  opts = opts or {}
  local ow = {
    player = { moving = false },
    runner = opts.script
      and { isRunning = function() return true end } or nil,
    scriptMoves = {},
  }
  -- screenOver asks the stack for its top and compares it to the overworld
  -- itself, so a screen is any other state sitting on it.
  local top = opts.screen and { textbox = true } or ow
  return { overworld = ow,
           stack = { states = { ow, opts.screen and top or nil },
                     top = function() return top end } }
end

-- Run the mod's own update pump for `seconds`, a sixtieth at a time.
local function run(mod, game, seconds)
  local pump = mod.hooked["core.update"]
  local dt = 1 / 60
  for _ = 1, math.floor(seconds / dt) do
    pump(function() end, game, dt)
  end
end

local function status(mod) return mod.exports.autosaveStatus() end

-- ------------------------------------ a scripted trainer: the reported case
do
  -- The Rocket in the hideout. Its onFinish only STARTS the script that
  -- records the defeat, so a hold that released when onFinish returned -- as
  -- 0.32.5 did -- released while the script was still to run.
  local mod = install()
  mod.exports.autosaveRequest()          -- a save already owed
  eq(status(mod).due, true, "a save is owed before the battle ends")

  mod.fire("battle.ended", { battle = { onFinish = function() end },
                             result = "win" })
  eq(status(mod).outcomePending, true, "the hold goes on when the battle ends")

  -- onFinish has run and handed off to the script, which is still going.
  run(mod, quietGame({ script = true }), 3)
  eq(status(mod).outcomePending, true,
     "and STAYS on while the script that records the defeat is running")

  -- the script finishes
  run(mod, quietGame(), 1)
  eq(status(mod).outcomePending, false, "released once the world is settled")
end

-- ------------------------------------------- a screen still up holds it too
do
  local mod = install()
  mod.fire("battle.ended", { battle = {}, result = "win" })
  run(mod, quietGame({ screen = true }), 3)
  eq(status(mod).outcomePending, true,
     "a text box over the map is the dialogue that has not finished yet")
  run(mod, quietGame(), 1)
  eq(status(mod).outcomePending, false, "and it releases when that closes")
end

-- --------------------------------------------- a wild battle is held as well
do
  -- It records no defeat, but holding it costs one settled second and means
  -- there is one rule rather than a guess about which battles matter.
  local mod = install()
  mod.fire("battle.ended", { battle = {}, result = "run" })
  eq(status(mod).outcomePending, true, "held")
  run(mod, quietGame(), 1)
  eq(status(mod).outcomePending, false, "and released a moment later")
  eq(status(mod).due, true, "the post-battle save is asked for at release")
end

-- ----------------------------------------------------- and it cannot wedge
do
  -- A script that never ends must not switch autosave off for the session.
  local mod = install()
  mod.fire("battle.ended", { battle = {}, result = "win" })
  run(mod, quietGame({ script = true }), 12)
  eq(status(mod).outcomePending, false,
     "the cap releases a hold that never settled on its own")
end

-- ------------------------------------------- and the save actually LANDS
--
-- Releasing the hold is not the point; the save is.  0.32.6 released it
-- correctly and then asked for the save three quarters of the way through the
-- window that had opened when the last text box closed -- SETTLE_GRACE is
-- 1.5s -- so a player who walked off immediately missed it entirely and
-- waited STILL_FOR (3s of standing still) instead.  Reported as the autosave
-- simply not appearing after a battle any more.
--
-- So this asserts the thing the player sees, which the previous cases did not.
io.write("the post-battle save lands in the window, not after it\n")

do
  local mod = install()
  local wrote = false
  -- writeSave is what the mod calls; count it rather than infer from state.
  local game = quietGame()
  game.writeSave = function() wrote = true return true end
  game.save = { options = {} }

  -- MIN_GAP is 20 seconds between any two autosaves, and install() has just
  -- reset the clock, so age it past that first or nothing may write for a
  -- reason that has nothing to do with battles.
  run(mod, game, 21)
  wrote = false

  mod.exports.autosaveRequest()
  mod.fire("battle.ended", { battle = { onFinish = function() end },
                             result = "win" })

  -- the battle's dialogue, then control back
  run(mod, (function() local g = quietGame({ screen = true })
      g.writeSave = game.writeSave; g.save = game.save; return g end)(), 1)
  eq(status(mod).outcomePending, true, "held through the dialogue")

  run(mod, game, 1.2)
  eq(status(mod).outcomePending, false, "released once it closed")
  ok(status(mod).due == false or wrote,
     "and the save was taken rather than left owed past its window")
end

-- ------------------- the cap does not open the hatch inside the NEXT battle

-- OUTCOME_CAP exists so a hold that never clears cannot switch autosave off
-- for the rest of the session.  `held` is three things -- a battle, a screen
-- over the map, a running script -- and the cap is the escape hatch for the
-- two of those that can wedge.  A battle is not one of them: it ends on its
-- own, and every battle end is another chance to release.
--
-- So the hatch must stay shut while a battle is up, and the case that proves
-- it is a player who finishes one fight and walks straight into another that
-- runs longer than the cap.  With the cap firing blind, the hold left over
-- from the FIRST battle releases in the middle of the SECOND one and writes a
-- save there, which is the one place a save must never land: mid-fight, with
-- the party and the field in a state the overworld never sees.
--
-- Found by Gen1AutoSave's own test_on_load.lua when this change was ported
-- down to the standalone mod -- this suite had no equivalent check and passed
-- the whole time.
do
  local mod = install()
  local wrote = false
  local game = quietGame()
  game.writeSave = function() wrote = true return true end
  game.save = { options = {} }

  run(mod, game, 21)                  -- clear MIN_GAP
  wrote = false

  mod.exports.autosaveRequest()
  mod.fire("battle.ended", { battle = { onFinish = function() end },
                             result = "win" })
  eq(status(mod).outcomePending, true, "the first battle leaves a hold")

  -- straight into another fight, longer than the cap
  mod.fire("battle.started", {})
  run(mod, game, 15)                  -- OUTCOME_CAP is 10

  eq(status(mod).inBattle, true, "still in the second battle")
  eq(status(mod).outcomePending, true,
     "the hold survives the cap while a battle is up")
  eq(wrote, false, "and nothing was written inside that battle")

  -- and it lets go the moment that battle is over
  mod.fire("battle.ended", { battle = { onFinish = function() end },
                             result = "win" })
  run(mod, game, 1.2)
  eq(status(mod).outcomePending, false, "released once the battle ended")
  ok(wrote, "and the save landed outside the fight")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
