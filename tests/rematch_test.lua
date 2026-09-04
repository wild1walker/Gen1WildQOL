-- TRAINER REMATCH: whose conversation this is, and which button ended it.
--
-- The feature is one wrap on world.talk that does NOT own the interaction.
-- next() runs first and in full -- the engine prints whichever line it would
-- have printed and every side effect it carries still happens -- and the
-- question is hung on the end of the box the engine pushed.  So what is worth
-- holding here is the gate: which conversations are finished enough to add a
-- line to, and which are the engine still working.
--
-- The gate is the stack.  One plain box, and when it closes the engine's own
-- onDone leaves the stack where the talk found it: then there is an offer.
-- Two boxes, a menu, a battle, nothing at all: no offer, on that talk.  It is
-- why a gym leader who still owes you a TM (a CHAIN of boxes, each pushing
-- the next) gets no rematch until the TM is handed over, and why the ROCKET
-- on ROCKET_HIDEOUT_B4F drops the LIFT KEY before anybody is asked anything.
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
-- Only the pieces the module reaches for, and each of them records what it
-- was asked so the test can look.

local boxes, battles

package.loaded["src.core.Strings"] = function(text) return text end

-- The module identifies the engine's box by its METATABLE, so the fake is
-- built the way TextBox.new builds one (TextBox.lua:122-123) rather than as
-- a bare table: a duck-type would pass a check the real module does not make.
local TextBox = {}
TextBox.__index = TextBox

function TextBox.new(game, text, onDone, opts)
  local self = setmetatable({}, TextBox)
  self.game = game
  self.text = text
  self.onDone = onDone
  self.opts = opts
  self.choice = opts and opts.choice
  self.auto = opts and opts.auto
  self.stay = opts and opts.stay
  boxes[#boxes + 1] = self
  return self
end

package.loaded["src.render.TextBox"] = TextBox

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

local LINE = "I need to catch more\nPOKeMON!"
local DROP = "Oh no! I dropped\nthe LIFT KEY!"
local TM_PRE = "Wait! Take this!"
local TM_GOT = "TM34 teaches\nBIDE!"

local function newWorld(options)
  options = options or {}
  local pressed = {}

  -- StateStack, as far as this module reads it: push, pop, top.  The module
  -- compares the top of the stack before and after the engine's talk, so a
  -- fake that only recorded pushes would test nothing.
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end

  local game = {
    save = {
      money = options.money or 3000,
      -- Level matching reads the top of this.  Nil means "no party", which is
      -- how the not-scaling cases are asked for.
      party = options.party,
    },
    stack = stack,
    input = { wasPressed = function(_, key) return pressed[key] == true end },
    data = {
      -- The price is read off the trainer's own roster, not off a battle
      -- built to be asked, so the fake game carries one.
      --
      -- There is deliberately no `trainerHeader` here at all.  The module
      -- used to need one and gym leaders have none (they are not def_trainers
      -- entries), which is why a leader could never be rematched; it reads
      -- the stack now and asks the data nothing.
      trainers = {
        OPP_YOUNGSTER = { baseMoney = BASE_MONEY, parties = { [2] = ROSTER } },
      },
    },
  }

  -- The overworld's own map state.  The engine holds the object it is talking
  -- to frozen for the length of the conversation and thaws it in the box's
  -- onDone (OverworldController.lua:3048-3049).
  local npc = {
    frozen = false,
    faced = false,
    def = { trainerClass = "OPP_YOUNGSTER", trainerParty = 2, index = 4,
            text = "TEXT_ROUTE3_TRAINER0" },
    facePlayer = function(self) self.faced = true end,
  }
  if options.notATrainer then npc.def.trainerClass = nil end
  if options.item then npc.def.item = options.item end
  if options.pokemon then npc.def.pokemon = options.pokemon end

  local ow = {
    player = {},
    map = { id = "ROUTE_3", def = { label = "ROUTE_3" } },
    trainerDefeated = function() return options.beaten ~= false end,
    pushed = nil,
    finished = nil,
    pushBattle = function(self, battle) self.pushed = battle end,
    afterBattle = function(self, result) self.finished = result end,
  }

  local world = { game = game, npc = npc, ow = ow, stack = stack,
                  dropped = false,
                  press = function(key) pressed[key] = true end,
                  unpress = function(key) pressed[key] = nil end }

  -- What talkTo does for this object, as the engine would.  `kind` picks the
  -- branch; every one of them is something a real map answers with.
  function world.engine()
    local kind = options.engine or "line"
    npc.frozen = true
    npc.faced = true
    local function thaw() npc.frozen = false end

    if kind == "silent" then
      -- a row-list script: the runner executes over frames and the stack is
      -- untouched on the way back out of talkTo
      return
    end
    if kind == "menu" then
      stack:push({ aMenu = true })
      return
    end
    if kind == "choice" then
      stack:push(TextBox.new(game, "Which one?", thaw,
                             { choice = function() end }))
      return
    end
    if kind == "auto" then
      stack:push(TextBox.new(game, LINE, thaw, { auto = { delay = 30 } }))
      return
    end
    if kind == "chain" then
      -- rewardChain: a gym leader who still owes you the TM answers with a
      -- run of boxes, each pushing the next from its own onDone
      stack:push(TextBox.new(game, TM_PRE, function()
        stack:push(TextBox.new(game, TM_GOT, thaw))
      end))
      return
    end
    if kind == "reveal" then
      -- the ROCKET on ROCKET_HIDEOUT_B4F: one line, and its onDone is the
      -- CheckAndSetEvent / ShowObject that puts the LIFT KEY on the floor
      stack:push(TextBox.new(game, DROP, function()
        world.dropped = true
        thaw()
      end))
      return
    end
    -- the vanilla beaten-trainer branch: the after-battle line, and the thaw
    stack:push(TextBox.new(game, LINE, thaw))
  end

  return world
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

  -- An A press on the object: the wrap, with the engine's own talk behind it.
  -- Returns whether the engine was reached, which it must always be.
  world.talk = function()
    local reached = false
    wrapped(function()
      reached = true
      world.engine()
    end, world.ow, world.npc)
    return reached
  end

  -- Closing the box on top, the way TextBox does it: pop, THEN onDone
  -- (TextBox.lua:532-533).  The module's whole gate is what the stack looks
  -- like at that moment, so a test that called onDone without popping would
  -- be testing a stack that never happens.
  world.close = function(box)
    box = box or world.stack:top()
    assert(world.stack:top() == box, "closing a box that is not on top")
    world.stack:pop()
    if box.onDone then box.onDone() end
    return box
  end

  return world
end

-- ------------------------------------------- the engine speaks, we add a line

do
  io.write("A through a beaten trainer's line offers the rematch\n")
  local w = install()

  eq(w.talk(), true, "the engine's own talk always runs")
  eq(#boxes, 1, "one box: the trainer's own after-battle line")
  eq(boxes[1].text, LINE, "printed by the engine, not by us")
  ok(w.npc.frozen, "the trainer is held for the conversation")
  ok(w.npc.faced, "and turned to face you, as talkTo does")

  -- A closed the box, so the press this frame is not B
  w.close()
  eq(#boxes, 2, "the prompt follows")
  eq(boxes[2].text,
     "Want to battle\nagain?\fThat will be\n\194\165480. OK?",
     "asking the question, then quoting half the prize")
  ok(type(boxes[2].opts.choice) == "function", "as a YES / NO")
  ok(w.npc.frozen, "the freeze is taken back for the question")

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
  w.close()
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
  w.close()
  eq(#boxes, 1, "the cancel is read first, so nothing is offered")
end

do
  io.write("NO at the prompt is the same as never asking\n")
  local w = install()
  w.talk()
  w.close()
  boxes[2].opts.choice(false)
  -- Nothing of the battle exists until the fight is agreed to.  0.18.0 built
  -- one to quote the price and dropped it on a NO; the price comes off the
  -- trainer's roster now, so a NO constructs nothing at all.
  eq(#battles, 0, "no battle is even built")
  ok(w.ow.pushed == nil, "so none is pushed")
  eq(w.game.save.money, 3000, "and nothing is charged")
  ok(not w.npc.frozen, "the trainer is let go")
end

-- ------------------------------------ the conversation the engine is still in

do
  io.write("a trainer who still owes you something is not asked anything\n")
  -- A gym leader whose TM did not fit in your bag at the victory: the talk
  -- re-runs the hand-over, which is a chain of boxes rather than a line.
  local w = install({ world = { engine = "chain" } })

  eq(w.talk(), true, "the hand-over runs, exactly as it always did")
  eq(#boxes, 1, "its first box")
  eq(boxes[1].text, TM_PRE, "which is the engine's, not ours")

  w.close()
  eq(#boxes, 2, "closing it pushes the next box of the chain")
  eq(boxes[2].text, TM_GOT, "the TM going in the bag")
  eq(w.game.stack:top(), boxes[2], "so the stack is deeper than we found it")

  w.close()
  eq(#boxes, 2, "and no prompt was hung on either box")
  eq(#battles, 0, "nothing was offered to fight")
end

do
  io.write("and once it is handed over, the same trainer is a rematch\n")
  -- The leader with nothing left to give answers with one advice line -- the
  -- ordinary shape -- and that is the whole difference.  A gym leader carries
  -- no def_trainers header, which is what used to make this impossible.
  local w = install({ world = { engine = "line" } })
  w.talk()
  w.close()
  eq(#boxes, 2, "the offer is there")
  ok(boxes[2].opts and boxes[2].opts.choice, "as a YES / NO")

  boxes[2].opts.choice(true)
  eq(#battles, 1, "and the leader can be fought again for the practice")
  ok(battles[1].checkpointOrigin == nil, "with no origin, so no second badge")
end

do
  io.write("the LIFT KEY is on the floor before anybody is asked anything\n")
  -- The ROCKET on ROCKET_HIDEOUT_B4F.  His line's onDone is the only thing in
  -- the game that reveals the ball; the module used to answer this A press
  -- itself, which meant that onDone never ran and the lift stayed locked.
  local w = install({ world = { engine = "reveal" } })

  w.talk()
  eq(boxes[1].text, DROP, "his own line, printed by his own script")
  ok(not w.dropped, "nothing has been revealed yet")

  w.close()
  ok(w.dropped, "closing it drops the LIFT KEY, as it always did")
  eq(#boxes, 2, "and only then is the rematch offered")
  ok(boxes[2].opts and boxes[2].opts.choice, "as a YES / NO")
end

do
  io.write("anything that is not one plain box is left alone\n")

  local silent = install({ world = { engine = "silent" } })
  eq(silent.talk(), true, "a script that pushes nothing still runs")
  eq(#boxes, 0, "and there is nothing to hang a question on")

  local menu = install({ world = { engine = "menu" } })
  menu.talk()
  eq(#boxes, 0, "a menu is not a box we may write on")
  eq(menu.game.stack:top().aMenu, true, "and it is left where it was pushed")

  local asked = install({ world = { engine = "choice" } })
  asked.talk()
  eq(#boxes, 1, "a box already asking a question")
  asked.close()
  eq(#boxes, 1, "is not asked a second one")
  eq(#battles, 0, "and nothing is offered to fight")

  local timed = install({ world = { engine = "auto" } })
  timed.talk()
  timed.close()
  eq(#boxes, 1, "a box that closes on a timer ended on no button at all")
end

-- --------------------------------------------------------------- the price

do
  io.write("a rematch costs half of what it pays\n")
  local w = install()
  w.talk()
  w.close()
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
  w.close()
  boxes[2].opts.choice(true)
  battles[1].onFinish("lose")
  eq(w.game.save.money, 2520, "which is what makes the fight worth losing")
  eq(w.ow.finished, "lose", "and the overworld still hears about it")
end

do
  io.write("what you cannot afford you are not sold\n")
  local w = install({ money = 479 })
  w.talk()
  w.close()
  eq(#boxes, 2, "a box, but not the question")
  eq(boxes[2].text, "You don't have\nenough money.",
     "the mart's own line, for the same reason")
  ok(boxes[2].opts == nil, "no YES / NO on it")

  w.close()
  eq(#battles, 0, "nothing is built to tell you the price")
  ok(w.ow.pushed == nil, "nothing is fought")
  eq(w.game.save.money, 479, "and nothing is taken")
  ok(not w.npc.frozen, "the trainer is let go")

  -- exactly enough is enough
  local exact = install({ money = 480 })
  exact.talk()
  exact.close()
  ok(boxes[2].opts and boxes[2].opts.choice, "480 buys a 480 rematch")
  eq(#battles, 0, "and the quote still costs no battle")
end

-- -------------------------------------------------- who is handed back

do
  io.write("everyone else goes to the engine untouched\n")

  local still = install({ world = { beaten = false } })
  eq(still.talk(), true, "a trainer still standing is the engine's")
  still.close()
  eq(#boxes, 1, "and no rematch is offered on the battle you just had")
  eq(#battles, 0, "nor one built")

  local plain = install({ world = { notATrainer = true } })
  plain.talk()
  plain.close()
  eq(#boxes, 1, "anyone who is not a trainer is the engine's too")

  local ball = install({ world = { item = "LIFT_KEY" } })
  ball.talk()
  ball.close()
  eq(#boxes, 1, "so is an object carrying an item ball")

  -- pokered's ITEM_NONE sentinel: the object sets the has-item bit and names
  -- item 0, which is a plain text object.  Lua's "0" is truthy, so a gate
  -- that only asked `if def.item` would swallow these.
  local none = install({ world = { item = "0" } })
  none.talk()
  none.close()
  eq(#boxes, 2, "a named item of 0 is not a ball, so the offer stands")

  local static = install({ world = { pokemon = "SNORLAX" } })
  static.talk()
  static.close()
  eq(#boxes, 1, "and a static encounter is the engine's")

  local off = install({ options = { enabled = false } })
  eq(off.talk(), true, "and so is everyone when the row is off")
  off.close()
  eq(#boxes, 1, "OFF is the vanilla interaction, with nothing to relaunch")
end

-- ------------------------------------------------------------- the purse

do
  io.write("REMATCH PRIZE decides whether the win pays\n")

  local free = install({ options = { prize = false } })
  free.talk(); free.close()
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
  lost.talk(); lost.close(); boxes[2].opts.choice(true)
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
  up.talk(); up.close(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "25/40", "the ace meets your best, the spread holds")

  local down = install({ party = party(20, 11) })
  down.talk(); down.close(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "5/20",
     "and it moves down too -- a leader you left behind is still a fight")

  local level = install({ party = party(24) })
  level.talk(); level.close(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "9/24", "already level with you is left alone")
end

do
  io.write("the ends of the ladder are clamped, not wrapped\n")
  local high = install({ party = party(100) })
  high.talk(); high.close(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "85/100", "nothing goes past 100")

  local low = install({ party = party(2) })
  low.talk(); low.close(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "1/2", "and nothing goes below 1")
end

do
  io.write("MATCH LEVELS off is the fight you already had\n")
  local w = install({ party = party(40), options = { scale = false } })
  w.talk(); w.close(); boxes[2].opts.choice(true)
  eq(levelsOf(battles[1]), "9/24", "their own levels, untouched")
end

do
  io.write("the trainer's own data is not rewritten\n")
  local w = install({ party = party(40) })
  w.talk(); w.close(); boxes[2].opts.choice(true)
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
  w.talk(); w.close(); boxes[2].opts.choice(true)
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
    w.talk(); w.close()
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
