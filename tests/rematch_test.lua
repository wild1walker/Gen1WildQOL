-- TRAINER REMATCH: which button you left the conversation with.
--
-- The feature is one wrap on world.talk and the whole of its interface is a
-- button press, so what is worth holding is the branching: who gets offered a
-- rematch, who is handed straight back to the engine, and what the two ways
-- out of the after-battle line do.
--
-- The one thing here that is not obvious and must not rot: a rematch battle
-- carries NO checkpointOrigin.  The engine's restore path keys on
-- `kind == "trainer_encounter"` and re-runs the entire first-win branch on
-- whatever it brings back -- defeatedTrainers, the header's event flag,
-- checkVictoryRewards -- so a restored rematch would hand out the badge a
-- second time.  Leaving the origin off means the checkpoint declines to
-- restore the battle, which is the failure worth having.
--
-- Run:  luajit tests/rematch_test.lua

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
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

-- ---------------------------------------------------------------- the engine
--
-- Only the four things the module reaches for, and each of them records what
-- it was asked so the test can look.

local boxes, battles

package.loaded["src.core.Strings"] = function(text) return text end

package.loaded["src.render.TextBox"] = {
  new = function(game, text, onDone, opts)
    local box = { game = game, text = text, onDone = onDone, opts = opts }
    boxes[#boxes + 1] = box
    return box
  end,
}

-- The prize, and so the price, is baseMoney times the level of the LAST mon
-- in the party as the battle actually built it -- so the fake battle carries
-- both, the way a real one does.
local BASE_MONEY, LAST_LEVEL = 40, 24        -- prize 960, price 480

-- The engine runs the trainer's data party through the trainer.party hook and
-- builds enemyParty from whatever comes back (BattleState.lua:856-878), so the
-- fake does the same -- otherwise nothing here would exercise the scaling.
local ROSTER = { { species = "WEEDLE", level = 9 },
                 { species = "KAKUNA", level = LAST_LEVEL } }

local partyHook

package.loaded["src.battle.BattleState"] = {
  newTrainer = function(game, class, party)
    local def = ROSTER
    if partyHook then
      def = partyHook(function(_, _, p) return p end, class, party or 1, ROSTER)
    end
    local enemy = {}
    for i, slot in ipairs(def) do enemy[i] = { level = slot.level } end
    local battle = {
      game = game, oppClass = class, partyIndex = party,
      trainer = { baseMoney = BASE_MONEY },
      enemyParty = enemy,
      builtParty = def,
    }
    battles[#battles + 1] = battle
    return battle
  end,
}

-- ---------------------------------------------------------------- the world

local HEADER = { after = "TEXT_ROUTE3_AFTER" }
local LINE = "I need to catch more\nPOKeMON!"

local function newWorld(options)
  options = options or {}
  local pressed = {}

  local game = {
    save = {
      money = options.money or 3000,
      -- Level matching reads the top of this.  Nil means "no party", which is
      -- how the not-scaling cases are asked for.
      party = options.party,
    },
    stack = { pushed = {}, push = function(self, state)
      self.pushed[#self.pushed + 1] = state
    end },
    input = { wasPressed = function(_, key) return pressed[key] == true end },
    data = {
      -- The price is read off the trainer's own roster now, not off a battle
      -- built to be asked, so the fake game carries one.
      trainers = {
        OPP_YOUNGSTER = { baseMoney = BASE_MONEY, parties = { [2] = ROSTER } },
      },
      text = { TEXT_ROUTE3_AFTER = LINE },
      trainerHeader = function(_, label, index)
        if options.noHeader then return nil end
        return (label == "ROUTE_3" and index == 4) and HEADER or nil
      end,
    },
  }

  local npc = {
    frozen = false,
    faced = false,
    def = { trainerClass = "OPP_YOUNGSTER", trainerParty = 2, index = 4 },
    facePlayer = function(self) self.faced = true end,
  }
  if options.notATrainer then npc.def.trainerClass = nil end

  local ow = {
    player = {},
    map = { def = { label = "ROUTE_3" } },
    trainerDefeated = function() return options.beaten ~= false end,
    pushed = nil,
    finished = nil,
    pushBattle = function(self, battle) self.pushed = battle end,
    afterBattle = function(self, result) self.finished = result end,
  }

  return { game = game, npc = npc, ow = ow,
           press = function(key) pressed[key] = true end,
           release = function(key) pressed[key] = nil end }
end

-- ------------------------------------------------------------------ the mod

local function install(stored)
  boxes, battles, partyHook = {}, {}, nil
  local w = stored or {}
  local world = newWorld(w.world or { money = w.money, party = w.party })
  local values = (stored and stored.options) or {}
  local wrapped

  local mod = {
    world = { game = world.game },
    options = {
      define = function() end,
      get = function(_, key) return values[key] end,
    },
    hooks = { wrap = function(_, name, fn)
      if name == "world.talk" then wrapped = fn end
      if name == "trainer.party" then partyHook = fn end
    end },
    log = { warn = function() end, info = function() end,
            error = function() end },
  }

  local source = assert(readFile("modules/Gen1Rematch/main.lua"))
  assert(load(source, "@modules/Gen1Rematch/main.lua"))()(mod)
  assert(wrapped, "the module did not wrap world.talk")

  world.talk = function()
    local reached = false
    wrapped(function() reached = true end, world.ow, world.npc)
    return reached
  end
  return world
end

-- ------------------------------------------------- A through, then the prompt

do
  io.write("A through a beaten trainer's line offers the rematch\n")
  local w = install()

  eq(w.talk(), false, "the wrap owns this interaction")
  eq(#boxes, 1, "one box: the trainer's own after-battle line")
  eq(boxes[1].text, LINE, "which is the line the engine would have printed")
  ok(w.npc.frozen, "the trainer is held for the conversation")
  ok(w.npc.faced, "and turned to face you, as talkTo does")

  -- A closed the box, so the press this frame is not B
  boxes[1].onDone()
  eq(#boxes, 2, "the prompt follows")
  eq(boxes[2].text,
     "Want to battle\nagain?\fThat will be\n\194\165480. OK?",
     "asking the question, then quoting half the prize")
  ok(type(boxes[2].opts.choice) == "function", "as a YES / NO")
  ok(w.npc.frozen, "still held while the question is up")

  boxes[2].opts.choice(true)
  eq(#battles, 1, "YES starts a battle")
  eq(battles[1].oppClass, "OPP_YOUNGSTER", "against the trainer you talked to")
  eq(battles[1].partyIndex, 2, "with the roster they were beaten on")
  ok(battles[1].checkpointOrigin == nil,
     "and NO checkpoint origin -- a restore would re-award the badge")
  eq(w.ow.pushed, battles[1], "the battle is pushed")

  battles[1].onFinish("win")
  eq(w.ow.finished, "win", "the overworld is told how it ended")
  ok(not w.npc.frozen, "and the trainer is let go")
end

-- ------------------------------------------------------------- B out of it

do
  io.write("B out of the line asks nothing\n")
  local w = install()
  w.talk()
  eq(#boxes, 1, "the line, as before")

  w.press("b")
  boxes[1].onDone()
  eq(#boxes, 1, "no prompt")
  eq(#battles, 0, "no battle")
  ok(not w.npc.frozen, "and the trainer is let go")
end

do
  io.write("B wins a frame that carries both\n")
  local w = install()
  w.talk()
  w.press("a")
  w.press("b")
  boxes[1].onDone()
  eq(#boxes, 1, "the cancel is read first, so nothing is offered")
end

do
  io.write("NO at the prompt is the same as never asking\n")
  local w = install()
  w.talk()
  boxes[1].onDone()
  boxes[2].opts.choice(false)
  -- Nothing of the battle exists until the fight is agreed to.  0.18.0 built
  -- one to quote the price and dropped it on a NO; the price comes off the
  -- trainer's roster now, so a NO constructs nothing at all.
  eq(#battles, 0, "no battle is even built")
  ok(w.ow.pushed == nil, "so none is pushed")
  eq(w.game.save.money, 3000, "and nothing is charged")
  ok(not w.npc.frozen, "the trainer is let go")
end

-- --------------------------------------------------------------- the price

do
  io.write("a rematch costs half of what it pays\n")
  local w = install()
  w.talk()
  boxes[1].onDone()
  boxes[2].opts.choice(true)
  -- baseMoney 40 * the LAST mon's level 24 = a 960 prize, so 480 to enter
  eq(w.game.save.money, 2520, "the stake is taken when the battle starts")

  -- the engine's own win branch pays the whole prize inside the battle
  w.game.save.money = w.game.save.money + 960
  battles[1].onFinish("win")
  eq(w.game.save.money, 3480, "and a win nets you the other half")
end

do
  io.write("a loss costs you the stake\n")
  local w = install()
  w.talk()
  boxes[1].onDone()
  boxes[2].opts.choice(true)
  battles[1].onFinish("lose")
  eq(w.game.save.money, 2520, "which is what makes the fight worth losing")
  eq(w.ow.finished, "lose", "and the overworld still hears about it")
end

do
  io.write("what you cannot afford you are not sold\n")
  local w = install({ money = 479 })
  w.talk()
  boxes[1].onDone()
  eq(#boxes, 2, "a box, but not the question")
  eq(boxes[2].text, "You don't have\nenough money.",
     "the mart's own line, for the same reason")
  ok(boxes[2].opts == nil, "no YES / NO on it")

  boxes[2].onDone()
  eq(#battles, 0, "nothing is built to tell you the price")
  ok(w.ow.pushed == nil, "nothing is fought")
  eq(w.game.save.money, 479, "and nothing is taken")
  ok(not w.npc.frozen, "the trainer is let go")

  -- exactly enough is enough
  local exact = install({ money = 480 })
  exact.talk()
  boxes[1].onDone()
  ok(boxes[2].opts and boxes[2].opts.choice, "480 buys a 480 rematch")
  eq(#battles, 0, "and the quote still costs no battle")
end

-- -------------------------------------------------- who is handed back

do
  io.write("everyone else goes to the engine untouched\n")

  local still = install({ world = { beaten = false } })
  eq(still.talk(), true, "a trainer still standing is the engine's")
  eq(#boxes, 0, "and nothing of ours is pushed")

  local mute = install({ world = { noHeader = true } })
  eq(mute.talk(), true, "a trainer with no after-battle line is too")

  local plain = install({ world = { notATrainer = true } })
  eq(plain.talk(), true, "so is anyone who is not a trainer")

  local off = install({ options = { enabled = false } })
  eq(off.talk(), true, "and so is everyone when the row is off")
  eq(#boxes, 0, "OFF is the vanilla interaction, with nothing to relaunch")
end

-- ------------------------------------------------------------- the purse

do
  io.write("REMATCH PRIZE decides whether the win pays\n")

  local free = install({ options = { prize = false } })
  free.talk(); boxes[1].onDone()
  eq(boxes[2].text, "Want to battle\nagain?",
     "off, the question is asked with no price on it")
  boxes[2].opts.choice(true)
  eq(free.game.save.money, 3000, "so nothing is staked")
  free.game.save.money = free.game.save.money + 960   -- the engine pays anyway
  battles[1].onFinish("win")
  eq(free.game.save.money, 3000, "and the prize is put back afterwards")

  -- Only a win pays, so only a win is refunded -- a blackout has already
  -- taken its own money on the way out of the battle, which is not ours.
  local lost = install({ options = { prize = false } })
  lost.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  lost.game.save.money = 1500
  battles[1].onFinish("lose")
  eq(lost.game.save.money, 1500, "a blackout's cost is not refunded")
  eq(lost.ow.finished, "lose", "and the overworld still hears about it")
  ok(not lost.npc.frozen, "the trainer is let go either way")
end

-- --------------------------------------------------------- MATCH LEVELS

local function levelsOf(battle)
  local out = {}
  for i, slot in ipairs(battle.builtParty) do out[i] = slot.level end
  return table.concat(out, "/")
end

local function party(...)
  local mons = {}
  for _, level in ipairs({ ... }) do mons[#mons + 1] = { level = level } end
  return mons
end

do
  io.write("their party moves to meet yours, keeping its own steps\n")
  -- theirs is 9 / 24, so a spread of 15 under the ace
  local up = install({ party = party(31, 40, 12) })
  up.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "25/40", "the ace meets your best, the spread holds")

  local down = install({ party = party(20, 11) })
  down.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "5/20",
     "and it moves down too -- a leader you left behind is still a fight")

  local level = install({ party = party(24) })
  level.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "9/24", "already level with you is left alone")
end

do
  io.write("the ends of the ladder are clamped, not wrapped\n")
  local high = install({ party = party(100) })
  high.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "85/100", "nothing goes past 100")

  local low = install({ party = party(2) })
  low.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "1/2", "and nothing goes below 1")
end

do
  io.write("MATCH LEVELS off is the fight you already had\n")
  local w = install({ party = party(40), options = { scale = false } })
  w.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "9/24", "their own levels, untouched")
end

do
  io.write("the trainer's own data is not rewritten\n")
  local w = install({ party = party(40) })
  w.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(ROSTER[1].level, 9, "the shared data row keeps its levels")
  eq(ROSTER[2].level, LAST_LEVEL, "...both of them")
  ok(battles[1].builtParty ~= ROSTER, "the battle got a copy")
  eq(battles[1].builtParty[1].species, "WEEDLE", "carrying the rest of the slot")
end

-- This is the guarantee, and it is the reason the wrap is armed for the
-- length of one call rather than left on: trainer.party is a hook the whole
-- game runs through, and every trainer battle that is not a rematch has to
-- come out of it holding exactly what it went in with.
do
  io.write("nothing but a rematch is scaled\n")
  local w = install({ party = party(80) })
  local handed = { { species = "PIDGEY", level = 6 } }
  local back = partyHook(function(_, _, p) return p end,
                         "OPP_BUG_CATCHER", 1, handed)
  ok(back == handed, "a first encounter is handed back the same table")
  eq(back[1].level, 6, "at the same level")

  -- and it is still armed correctly for the rematch immediately after
  w.talk(); boxes[1].onDone(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "65/80", "while the rematch is scaled")
end

-- ------------------------------------------------- the price never exceeds it

do
  io.write("the buy-in is always less than the pay-out\n")
  -- The price is half the prize, floored, and the prize is what the engine
  -- pays for the win -- so what comes back is ceil(prize / 2), which is more
  -- than what went in for every prize above zero.  Walked over a spread of
  -- levels because the scaling makes the prize move.
  for _, top in ipairs({ 1, 2, 5, 24, 37, 50, 99, 100 }) do
    local w = install({ party = party(top), money = 999999 })
    w.talk(); boxes[1].onDone()
    boxes[2].opts.choice(true)

    local stake = 999999 - w.game.save.money
    local last = battles[1].enemyParty[#battles[1].enemyParty].level
    local prize = BASE_MONEY * last
    eq(stake, math.floor(prize / 2), ("level %d: the stake is half"):format(top))
    ok(prize > stake, ("level %d: and the win pays more than it"):format(top))

    w.game.save.money = w.game.save.money + prize
    battles[1].onFinish("win")
    ok(w.game.save.money > 999999,
       ("level %d: so a win leaves you up"):format(top))
  end
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
