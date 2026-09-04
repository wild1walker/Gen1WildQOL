-- Gen1Rematch -- fight a trainer you have already beaten.
--
-- ------- the shape of it
--
-- A beaten trainer already has something to say.  Walking up to one prints
-- it -- an `after` line off `def_trainers` for most of them
-- (src/world/OverworldController.lua:3230-3237), a hand-ported script's own
-- line for the ones the cartridge gave a script to.  So the rematch is
-- offered where the conversation already ends, rather than as a new thing on
-- the screen:
--
--   A through the line   ->  "Want to battle again?"  ->  YES / NO
--   B out of the line    ->  nothing, exactly as before
--
-- Which button ended the box is the whole interface.  It costs no row, no
-- prompt for anyone who did not ask, and it is the reading both buttons
-- already have everywhere else in this game: A is "go on then", B is "I am
-- done here".
--
-- The engine does not distinguish them -- `TextBox` advances and closes on
-- either (home/text_script.asm:96 waits on A|B, and src/render/TextBox.lua:476
-- is that faithfully) -- but it does not have to.  `onDone` is called from
-- inside the same `update` that saw the press, one line after `stack:pop()`,
-- so the press is still this frame's and `wasPressed("b")` still answers.
-- That is the only reason this reads a button at all rather than patching the
-- box.
--
-- ------- what a rematch is and is not
--
-- It is the battle and nothing else.  The victory path a first win takes --
-- `defeatedTrainers`, the header's event flag, `checkVictoryRewards` -- is
-- not run here, so no badge is handed out twice, no gift item reappears, and
-- no map's onVictory script fires again.  A gym leader is an ordinary trainer
-- on this path and can be fought again for the practice; the badge is already
-- yours and stays exactly once yours.
--
-- ------- whose talk this is, and when it is finished
--
-- The engine says the line.  Every one of them, out of `talkTo`, in the
-- order `talkTo` already resolves: a hand-ported map script wins first
-- ("hand-ported scripts always win", OverworldController.lua:3152), then an
-- item ball, then a static encounter, and only then the trainer branches
-- (:3225-3237).  This wrap calls next() and lets all of that happen, then
-- hangs the question off the box the engine pushed.  It used to answer the A
-- press ITSELF for any beaten trainer with an `after` line, which put it in
-- front of every one of those branches: the offer was not sitting on the end
-- of a conversation, it was replacing one.
--
-- A replaced conversation is not a missing line, it is a missing item.  The
-- ROCKET on ROCKET_HIDEOUT_B4F is a beaten trainer with an after-line whose
-- hand-ported talk is the only thing in the game that puts the LIFT KEY on
-- the floor: the ball starts hidden in the map objects and the first talk
-- after the win is what reveals it (CheckAndSetEvent
-- EVENT_ROCKET_DROPPED_LIFT_KEY / ShowObject ROCKETHIDEOUTB4F_LIFT_KEY,
-- data/scripts/story3.lua:387-408).  Talking to a trainer you have beaten is
-- where this game hands over what it still owes you, and he is not the only
-- one: a gym leader re-runs the TM give when your bag was full at the
-- victory (retryTmGive, data/scripts/gyms.lua:28-38), the MT MOON SUPER
-- NERD's line is what turns the fossils on.
--
-- ------- one box, and the stack where the talk found it
--
-- So the question is not "may we speak for this trainer" but "has the engine
-- finished speaking", and it is asked of the stack rather than of a list of
-- names:
--
--   the talk pushed exactly one box, and it is a plain one -- no YES/NO of
--   its own, no timer closing it -- and when that box closes, the engine's
--   own `onDone` leaves the stack exactly where the talk found it.
--
-- Then the engine had one line to say and has said it, and the offer goes on
-- the end of it.  Anything else is the engine still working: a gym leader
-- who still owes you a TM answers with a CHAIN of boxes, each pushing the
-- next from its own onDone (rewardChain, OverworldController.lua:3917-3930),
-- so the stack is one deeper when we look and there is no offer on that
-- talk.  Hand the TM over and the same leader answers with one advice line,
-- which ends where it started -- and the rematch is there.  A farewell that
-- fades, a menu, a script that runs its rows over frames: all the same
-- answer, for the same reason, without this file knowing what any of them
-- are.
--
-- That is the whole gate.  It is not a denylist of grunts, so the trainer
-- nobody has thought of yet is behind it too; and it is not a ban on bosses,
-- so a gym leader you have taken everything from is an ordinary beaten
-- trainer with an ordinary line, and can be fought again for the practice.
--
-- ------- the levels
--
-- The team is the one you beat.  The levels are yours.
--
-- MATCH LEVELS moves their party so its top mon meets the top of yours, and
-- keeps the spread between their own mons exactly: a 12 / 14 / 16 gym leader
-- met with a level 40 party is 36 / 38 / 40, still stepping up to the same
-- ace.  It moves down as well as up, so a leader you left behind is a fair
-- practice fight rather than a formality.
--
-- REMATCHES ONLY, and that is enforced by construction rather than promised.
-- The scaling rides `trainer.party`, which is a hook the whole game runs
-- through, so the wrap is armed for exactly the length of this module's own
-- call to `newTrainer` and is otherwise a straight pass to next().  There is
-- no state in which a first encounter, a rival, an arena battle or anybody
-- else's trainer sees a level this file touched.
--
-- The party it hands back is a copy.  `partyDef` is the trainer's own row in
-- the data table, shared by every battle in the session, and writing a level
-- into it would rewrite that trainer permanently.
--
-- ------- what it costs
--
-- Half of what they pay, up front.  The engine's win branch adds
-- `baseMoney * level` (src/battle/BattleState.lua:4721-4722) and the rematch
-- asks for half of that before the battle starts, so a win nets you the other
-- half and a loss costs you the stake.  A repeatable battle that paid full
-- price would be a money printer; one that paid nothing would be a trip for
-- exp alone.  Half is the fight being worth making and worth losing.
--
-- The price is `baseMoney` times the level of the last mon in the roster, with
-- MATCH LEVELS applied to that roster here the same way it is applied on the
-- way into the battle -- so the quote and the prize are the same arithmetic
-- on the same numbers.
--
-- 0.18.0 read it off a BattleState built to be asked and thrown away on a NO,
-- which was exact to the point of being exact about another mod's rewrite as
-- well.  It was also a live battle object constructed on the overworld and
-- held across a prompt for as long as somebody took to answer it, and the
-- first mon of a trainer you walked away from marked SEEN for the trouble.
-- Quoting a price is not worth that, and nothing else in this cart rewrites
-- a trainer's party.
--
-- REMATCH PRIZE off takes both halves out: nothing is charged, and the prize
-- the engine paid is put back afterwards.  Off is a rematch with no money in
-- it at all, in either direction.

return function(mod)

  -- Two pages, closing on the mart's own line (src/ui/ShopMenu.lua:90), so
  -- the price is stated in the words this game already uses for a price and
  -- nobody is charged for something they were not shown.  The YES/NO comes up
  -- by itself once the last page has typed out.
  local ASK = "Want to battle\nagain?"
  local PRICED = ASK .. "\fThat will be\n\194\165%d. OK?"
  local BROKE = "You don't have\nenough money."

  mod.options:define({
    { key = "enabled", type = "toggle", label = "TRAINER REMATCH",
      default = true },
    -- The money in a rematch, both ways: the half you stake and the whole
    -- the engine pays you back for winning.  Off is a rematch that is worth
    -- exp and nothing else, and costs the same.
    { key = "prize", type = "toggle", label = "REMATCH PRIZE", default = true,
      visible_if = { key = "enabled", equals = true } },
    -- Off is the fight you already had, at the levels you had it -- which is
    -- worth keeping for anyone who wants a rematch to be the same rematch.
    { key = "scale", type = "toggle", label = "MATCH LEVELS", default = true,
      visible_if = { key = "enabled", equals = true } },
  })

  local function on(key) return mod.options:get(key) ~= false end

  local function say(text)
    local ok, Strings = pcall(require, "src.core.Strings")
    if ok and type(Strings) == "function" then
      local said, out = pcall(Strings, text)
      if said and type(out) == "string" then return out end
    end
    return text
  end

  -- ------- is this a trainer talk at all?
  --
  -- Asked BEFORE next(), because after it the answer has moved: a trainer
  -- still standing is beaten by the time the engine hands control back.  The
  -- item ball and the static encounter are the two answers `talkTo` reaches
  -- before either trainer branch (:3163, :3199), screened here so this never
  -- hangs a question off one of them -- "0" among them, which is pokered's
  -- ITEM_NONE sentinel and a plain text object, exactly as the engine reads
  -- it.
  local function talkingToABeatenTrainer(ow, npc)
    local def = npc and npc.def
    if type(def) ~= "table" or not def.trainerClass then return false end
    if def.item and def.item ~= 0 and def.item ~= "0" then return false end
    if def.pokemon then return false end
    if type(ow.trainerDefeated) ~= "function" then return false end
    local asked, beaten = pcall(ow.trainerDefeated, ow, npc)
    return (asked and beaten) and true or false
  end

  -- A box a button ends, and nothing more.  `choice` is a question already
  -- being asked and `auto` is a box that closes on a timer, and neither is
  -- something to hang "which button did you leave on?" off.  `stay` belongs
  -- to whoever pushed it -- it is the idiom for putting something on top of
  -- a box (TextBox.lua:118-121), so a box carrying one is a conversation
  -- still being built.
  --
  -- The identity check is the metatable rather than a duck-type: a state
  -- that merely has pages is not a TextBox, and pushing our question onto
  -- something else's onDone field would be a bug nobody would find.
  local function plainBox(state)
    local ok, TextBox = pcall(require, "src.render.TextBox")
    if not ok or type(TextBox) ~= "table" then return false end
    if getmetatable(state) ~= TextBox then return false end
    return not (state.choice or state.auto or state.stay)
  end

  -- ------- the battle
  --
  -- No `checkpointOrigin`, and that is load-bearing rather than an omission.
  -- The restore path keys on `kind == "trainer_encounter"` and re-runs the
  -- whole first-win branch on the battle it brings back -- defeatedTrainers,
  -- the event flag, checkVictoryRewards (OverworldController.lua:4744-4752).
  -- A rematch restored through it would hand out the badge a second time.
  -- With no origin the checkpoint simply does not restore this battle, which
  -- is the failure worth having.
  -- ------- matching their levels to yours
  --
  -- The top of your party, because that is the mon you would lead with and
  -- the one number a player can predict this from.  Fainted mons count: a
  -- revive is a POKe CENTER away and a party that shrinks when you lose would
  -- make the rematch easier for having gone badly.
  local function partyTop(game)
    local best = 0
    for _, mon in ipairs(game and game.save and game.save.party or {}) do
      local level = type(mon) == "table" and tonumber(mon.level) or nil
      if level and level > best then best = level end
    end
    return best
  end

  -- One offset for the whole party rather than a multiplier, so the steps
  -- between their mons survive: multiplying 12 / 14 / 16 up to a top of 40
  -- would spread them to 30 / 35 / 40 and flatten the lead-in, and
  -- multiplying down would bunch them together.  An offset moves the party
  -- without redesigning it.
  local function matched(game, party)
    local yours = partyTop(game)
    if yours <= 0 then return party end

    local theirs = 0
    for _, slot in ipairs(party) do
      local level = type(slot) == "table" and tonumber(slot.level) or nil
      if level and level > theirs then theirs = level end
    end
    if theirs <= 0 then return party end

    local delta = yours - theirs
    if delta == 0 then return party end

    local out = {}
    for i, slot in ipairs(party) do
      -- Shallow, which is enough: the only field written is `level`, and a
      -- slot's `moves` list is read and never touched.
      local copy = {}
      for key, value in pairs(slot) do copy[key] = value end
      local level = (tonumber(slot.level) or 1) + delta
      copy.level = math.max(1, math.min(100, level))
      out[i] = copy
    end
    return out
  end

  -- Armed only for the length of our own newTrainer call, below.  Every other
  -- trainer battle in the game reaches next() and nothing else.
  local scaling = false

  mod.hooks:wrap("trainer.party", function(next, oppClass, partyIndex, party)
    local built = next(oppClass, partyIndex, party)
    if not scaling or not on("scale") then return built end
    if type(built) ~= "table" then return built end
    local ok, out = pcall(matched, mod.world and mod.world.game, built)
    if ok and type(out) == "table" then return out end
    return built
  end)

  local function build(npc)
    local game = mod.world and mod.world.game
    local def = npc.def
    local made, BattleState = pcall(require, "src.battle.BattleState")
    if not made or type(BattleState) ~= "table" then return nil end
    scaling = true
    local built, battle = pcall(BattleState.newTrainer, game, def.trainerClass,
                                def.trainerParty)
    scaling = false
    if not built or type(battle) ~= "table" then
      mod.log:warn("rematch could not be started: %s", tostring(battle))
      return nil
    end
    return battle
  end

  -- Half of what this battle is about to pay, which is `baseMoney` times the
  -- level of the LAST mon in the party -- the one whose fainting runs the win
  -- branch, so the one the engine multiplies by.
  --
  -- Off the trainer's own roster, with MATCH LEVELS applied to it here the
  -- same way the hook applies it on the way in.  0.18.0 read it off a battle
  -- BUILT to be asked, which was exact to the point of being exact about
  -- another mod's rewrite as well -- and which meant constructing a whole
  -- BattleState on the overworld, holding it across the prompt, and throwing
  -- it away on a NO.  Quoting a price is not worth a live battle object, and
  -- a rematch is fought against a roster nobody else in this cart touches.
  local function priceOf(def)
    if not on("prize") then return 0 end
    local game = mod.world and mod.world.game
    local data = game and game.data
    local trainer = data and data.trainers and data.trainers[def.trainerClass]
    local base = type(trainer) == "table" and trainer.baseMoney or nil
    local party = type(trainer) == "table" and trainer.parties
      and trainer.parties[def.trainerParty or 1] or nil
    if type(base) ~= "number" or type(party) ~= "table" or not party[1] then
      return 0
    end
    if on("scale") then
      local ok, out = pcall(matched, game, party)
      if ok and type(out) == "table" and out[1] then party = out end
    end
    local last = party[#party]
    local level = type(last) == "table" and tonumber(last.level) or nil
    if not level then return 0 end
    return math.floor(base * level / 2)
  end

  local function startBattle(ow, npc, price, release)
    local game = mod.world and mod.world.game
    local save = game and game.save

    -- Built here, on the YES, and not a frame before it.  Nothing of the
    -- battle exists until the fight is agreed to: no party rewritten, no
    -- first mon marked SEEN for a trainer you walked away from, and nothing
    -- holding the save's party while the overworld carries on around it.
    local battle = build(npc)
    if not battle then return release() end

    -- Read before anything is charged, so REMATCH PRIZE off is neutral in
    -- both directions.  Putting the money back also takes back a PAY DAY used
    -- in the rematch, which is the honest reading of the row rather than a
    -- hole in it: this fight pays nothing.
    local purse = (not on("prize")) and save and save.money or nil

    if price > 0 and save then save.money = save.money - price end

    battle.onFinish = function(result)
      if result == "win" and purse and save then save.money = purse end
      ow:afterBattle(result, battle)
      release()
    end
    ow:pushBattle(battle)
  end

  local function offer(ow, npc, release)
    local game = mod.world and mod.world.game
    local ok, TextBox = pcall(require, "src.render.TextBox")
    if not ok or type(TextBox) ~= "table" then return release() end

    local price = priceOf(npc.def)
    local purse = (game.save and game.save.money) or 0
    if price > purse then
      return game.stack:push(TextBox.new(game, say(BROKE), release))
    end

    -- A free rematch is not quoted a price of nothing.
    local ask = price > 0 and say(PRICED):format(price) or say(ASK)
    game.stack:push(TextBox.new(game, ask, nil, {
      choice = function(yes)
        if not yes then return release() end
        startBattle(ow, npc, price, release)
      end,
    }))
  end

  -- ------- the A press on a beaten trainer
  --
  -- `world.talk` is the A press on an object before the map's text tables
  -- get it.  A wrap that does not call next() OWNS the interaction, and this
  -- one deliberately does not: next() runs first and in full, so the line
  -- that gets printed is whichever line the engine would have printed and
  -- every side effect it carries -- a revealed LIFT KEY among them -- still
  -- happens.  All this adds is a question on the end of the box, and only
  -- when that box was the end of it.
  mod.hooks:wrap("world.talk", function(next, ow, npc)
    if not on("enabled") then return next(ow, npc) end
    -- Asked now: after next() this trainer may have just been beaten, and a
    -- battle you have this second finished is not a rematch.
    if not talkingToABeatenTrainer(ow, npc) then return next(ow, npc) end

    local game = mod.world and mod.world.game
    local stack = game and game.stack
    if not stack or type(stack.top) ~= "function" then return next(ow, npc) end

    -- What the stack looked like before the engine said anything.  Identity,
    -- not a count: it is the same reading either way and it does not reach
    -- into the stack's own array to get it.
    local under = stack:top()

    local result = next(ow, npc)

    -- One box, plain, and the engine's own.  Two boxes, a menu, a battle or
    -- nothing at all are all "the engine is not finished", and none of them
    -- is ours to write on.
    local box = stack:top()
    if box == under or not plainBox(box) then return result end

    local spoken = box.onDone
    box.onDone = function()
      -- The engine's own callback first, always: it is the unfreeze on the
      -- vanilla path and the LIFT KEY's ShowObject on the ROCKET's, and it
      -- runs whether or not a rematch is offered afterwards.
      if spoken then spoken() end

      -- And now the test that makes this safe.  If that callback pushed
      -- something, the conversation is still going -- the next box of a gym
      -- leader's TM hand-over, a farewell mid-fade -- and the offer is not
      -- made on this talk.  It will be there on the next one, once the
      -- engine has nothing left to hand over and answers with one line.
      if stack:top() ~= under then return end

      -- Whichever button closed the box is still this frame's press.  B is a
      -- way out that costs nothing and asks nothing, which is the point: the
      -- prompt only ever appears for someone who read to the end and pressed
      -- on.  Checked before A rather than after, so a frame carrying both is
      -- read as the cancel.
      local input = game.input
      if input and input.wasPressed and input:wasPressed("b") then return end

      -- talkTo freezes the object it is talking to and thaws it on the way
      -- out (OverworldController.lua:3048-3049), and that thaw has just run
      -- in `spoken`.  Take the freeze back for the length of the prompt and
      -- the battle, so a trainer cannot walk off mid-conversation with their
      -- own rematch.
      npc.frozen = true
      local released = false
      local function release()
        if released then return end
        released = true
        npc.frozen = false
      end

      offer(ow, npc, release)
    end

    return result
  end)
end
