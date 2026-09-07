-- TRAINER REMATCH on Gold, Silver and Crystal.
--
-- ------- why this is a second file rather than a second branch
--
-- The FEATURE is the same one main.lua describes and every word of that note
-- still applies: the offer goes on the end of the conversation the trainer
-- already has, it is the battle and nothing else, the levels come to yours,
-- and half the purse is staked up front.  What is different is every seam it
-- hangs on, because Gold does not have one of Red's:
--
--   Red                                  Gold
--   `world.talk` hook                    no such hook -- World:interactBody
--                                        dispatches inline
--   the stack's own update               World:STEP -- Gold's World has no
--                                        `update` at all (Game2 calls
--                                        `world:step()`)
--   one TextBox, watched by identity     an extracted SCRIPT run on the VM
--   BattleState.newTrainer + pushBattle  World:startScriptedBattle
--   data.trainers[class].parties[i]      World:trainerParty -> Trainers.lookup
--   TextBox with a `choice`              World:showText(stay) + World:askYesNo
--
-- Writing that as five branches inside main.lua would have left neither game
-- readable.  The two files share what is actually shared -- the option rows,
-- the level match, the price -- and each owns its own way in.
--
-- ------- the offer, and when it is safe to make one
--
-- On Red the gate is the stack: the talk pushed exactly one plain box, and
-- when that box closes the stack is where the talk found it.  Gold's talk is
-- not a box at all.  Every trainer object, beaten or not, goes through
-- `startTrainerScript(npc, TALK_TO_TRAINER_SCRIPT)` and the script decides
-- what to say -- so the question "has the engine finished speaking" is asked
-- of the VM instead: `vm:running()` is false, and nothing is left on the
-- stack over the world.
--
-- That is a better gate than Red's, not a worse one.  A gym leader still
-- handing over a TM, a script that walks somebody off, a queued phone call --
-- all of them keep the VM busy or keep a box up, and none of them gets an
-- offer hung off it.  The offer waits for a talk that ended.
--
-- ------- and B still means "I am done here"
--
-- The press that closed the last page is still this frame's when the VM goes
-- idle, for the same reason it is on Red: the idle is noticed inside the same
-- update that consumed the press.  So B out of a beaten trainer's line is
-- nothing at all, exactly as before, and the prompt only ever appears for
-- somebody who read to the end and pressed on.
--
-- ------- what a rematch does NOT run
--
-- `startScriptedBattle` is the battle, the transition, the music and the
-- prize -- and none of the trainer's own script.  So the event flag is not
-- re-set, the after-battle text does not replay, no badge is handed out twice
-- and no `disappear` fires again.  On Gold that separation is free: the
-- rewards live in the script and the battle does not.

local Gen2 = {}

-- The npc a talk was started on, and the trainer record behind it, held from
-- the A press until the VM goes idle.  One at a time: a talk cannot begin
-- while another is running.
local pending = nil

local function engine(name)
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then return mod end
  return nil
end

-- The class/member pair on a trainer object, which is what every lookup here
-- takes.  `npc.def.trainer` is the record World:startTrainerScript reads.
local function trainerOf(npc)
  local record = npc and npc.def and npc.def.trainer
  if type(record) ~= "table" then return nil end
  if record.class == nil or record.member == nil then return nil end
  return record
end

-- Beaten, and beaten BEFORE this press: the flag is set by the trainer's own
-- script, so after the talk a first win reads exactly like a rematch.
local function beatenTrainer(world, npc)
  local record = trainerOf(npc)
  if not record then return nil end
  if type(world.trainerBeaten) ~= "function" then return nil end
  local ok, beaten = pcall(world.trainerBeaten, world, record)
  if not (ok and beaten) then return nil end
  return record
end

-- Nothing over the world: no text box, no menu, no battle, and no map setup
-- part-way through a fade.  Asked of the world's own flags rather than of the
-- stack's contents, because Gold's world is not a stack state and "the top is
-- the world" cannot be spelled that way.
local function worldIsIdle(world)
  if world.textbox or world.choicebox or world.stayedTextBox then return false end
  if world.battleActive or world.mapSetup then return false end
  if type(world.busy) == "function" then
    local ok, busy = pcall(world.busy, world)
    if ok and busy then return false end
  end
  local vm = world.vm
  if vm and type(vm.running) == "function" and vm:running() then return false end
  return true
end

-- ------- the money
--
-- The same arithmetic the battle will do: ComputeTrainerReward multiplies the
-- class's base reward by the LAST party row's level, and the party here is
-- the one the battle will fight -- MATCH LEVELS applied, when it is on -- so
-- the quote and the prize are the same numbers.
function Gen2.priceOf(world, record, matched, wantPrize, wantScale, game)
  if not wantPrize then return 0 end
  if type(world.trainerParty) ~= "function" then return 0 end
  local ok, entry = pcall(world.trainerParty, world, record.class, record.member)
  if not (ok and type(entry) == "table") then return 0 end
  local base = tonumber(entry.baseMoney)
  -- The ROSTER, which is the data rows -- species, level, item -- and not
  -- `Trainers.party`, which turns those rows into live mons.  Only the last
  -- row's level is wanted here, the roster already carries it, and building a
  -- whole party to read one number would need the pokemon table and would
  -- quote nothing at all on a save whose data had not loaded yet.
  local party = entry.roster
  if not base or type(party) ~= "table" or not party[1] then return 0 end
  if wantScale then
    local scaled, out = pcall(matched, game, party)
    if scaled and type(out) == "table" and out[1] then party = out end
  end
  local last = party[#party]
  local level = type(last) == "table" and tonumber(last.level) or nil
  if not level then return 0 end
  return math.floor(base * level / 2)
end

-- ------- the battle
--
-- `startScriptedBattle` takes the roster record, not the object's class/member
-- pair, so the lookup happens here -- and it is the same lookup the cart makes
-- for a first fight, so a rematch is fought against the party the object
-- actually carries rather than a copy this file assembled.
function Gen2.startBattle(ctx, record, price)
  local world, game = ctx.world, ctx.game
  local save = game and game.save
  if type(world.trainerParty) ~= "function"
      or type(world.startScriptedBattle) ~= "function" then
    return false
  end
  local found, entry = pcall(world.trainerParty, world, record.class, record.member)
  if not (found and type(entry) == "table") then
    ctx.log:warn("no roster for trainer class %s member %s; no rematch",
      tostring(record.class), tostring(record.member))
    return false
  end

  -- Read before anything is charged, so REMATCH PRIZE off is neutral in both
  -- directions -- the stake is not taken and the engine's payout is put back.
  local purse = (not ctx.wantPrize()) and save and save.money or nil
  if price > 0 and save then save.money = (save.money or 0) - price end

  ctx.arm(true)
  local started, problem = pcall(world.startScriptedBattle, world, entry, nil,
    function(outcome)
      if outcome == "win" and purse and save then save.money = purse end
      ctx.done()
    end)
  ctx.arm(false)

  if not started then
    -- Put the stake back: nothing was fought for it.
    if price > 0 and save then save.money = (save.money or 0) + price end
    ctx.log:warn("rematch could not be started: %s", tostring(problem))
    return false
  end
  return true
end

-- ------- the question
--
-- `showText(body, onDone, stay)` then `askYesNo` is the cart's own `writetext
-- / yesorno` pair: the page stays up and the YES/NO box opens over it, so the
-- question is asked in the box that asked it rather than in a second one.
function Gen2.offer(ctx, record)
  local world = ctx.world
  if type(world.showText) ~= "function" or type(world.askYesNo) ~= "function" then
    return ctx.done()
  end

  local price = Gen2.priceOf(world, record, ctx.matched, ctx.wantPrize(),
    ctx.wantScale(), ctx.game)
  local purse = (ctx.game and ctx.game.save and ctx.game.save.money) or 0
  if price > purse then
    return world:showText(ctx.say(ctx.text.BROKE), function() ctx.done() end)
  end

  local ask = price > 0 and ctx.say(ctx.text.PRICED):format(price)
    or ctx.say(ctx.text.ASK)
  world:showText(ask, function()
    world:askYesNo(function(yes)
      if not yes then return ctx.done() end
      if not Gen2.startBattle(ctx, record, price) then ctx.done() end
    end)
  end, true)
end

-- ------- the two patches
--
-- Both idempotent and both live: the toggles are read on the press and on the
-- frame, not at install, so every row here works without a relaunch.
-- Every seam this file hangs on, named once.  A missing method here is the
-- whole feature, silently -- which is exactly what happened: this asked for
-- `World.update`, Gold's World has no such method (Game2 calls `world:step()`
-- sixty times a second), the guard below took the early exit, and TRAINER
-- REMATCH never installed on Gold at all.  The headless suite did not catch it
-- because its stand-in World declared an `update` of its own, so the stub
-- agreed with the mistake rather than checking it.  tests/rematch_gen2_test.lua
-- now reads these names off the engine instead.
Gen2.SEAMS = { "interactBody", "step", "facingObject", "trainerBeaten",
               "trainerParty", "startScriptedBattle", "showText", "askYesNo" }

function Gen2.install(ctx)
  local World = engine("src.world.gen2.World")
  if not World then return false, "no Gen 2 World to hang a rematch on" end
  for _, name in ipairs(Gen2.SEAMS) do
    if type(World[name]) ~= "function" then
      -- Named, rather than one message for eight causes: the last time this
      -- failed the log said only "no Gen 2 World", which is both wrong and
      -- unactionable -- the World was right there.
      return false, ("the Gen 2 World has no %s(); TRAINER REMATCH stands down")
        :format(name)
    end
  end
  if World.gen1wildRematchHook then return true end

  -- 1. remember whose talk this was, before the engine answers it
  local innerInteract = World.interactBody
  function World:interactBody(...)
    local armed = nil
    if ctx.enabled() then
      local ok, npc = pcall(self.facingObject, self)
      if ok and npc then
        local record = beatenTrainer(self, npc)
        if record then armed = { npc = npc, record = record, world = self } end
      end
    end
    local started = innerInteract(self, ...)
    -- Only a talk that actually began: a press that found a wall, or one the
    -- engine refused, has no conversation to put an offer on the end of.
    pending = (armed and started) and armed or nil
    return started
  end

  -- 2. and make the offer on the frame that talk finishes
  --
  -- `step` is Gold's per-frame method -- src/core/Game2.lua calls
  -- `self.world:step()` -- and there is no `update` on this class to wrap.
  local innerStep = World.step
  function World:step(...)
    local result = innerStep(self, ...)
    local armed = pending
    if not armed or armed.world ~= self then return result end
    -- The World is the one thing that certainly knows its own game.
    ctx.game = self.game
    if not ctx.enabled() then pending = nil; return result end
    -- No second latch beyond this one.  `pending` is cleared before the offer
    -- is made and set only by a fresh talk, so nothing can re-enter here; and
    -- a latch that outlived a failed offer would switch the feature off for
    -- the rest of the session with nothing to say so.
    if not worldIsIdle(self) then return result end

    pending = nil

    -- Whichever button ended the last page is still this frame's press.  B is
    -- a way out that costs nothing and asks nothing, which is the point: the
    -- prompt only appears for somebody who read on.  Checked before anything
    -- else, so a frame carrying both reads as the cancel.
    local input = ctx.game and ctx.game.input
    if input and type(input.wasPressed) == "function"
        and input:wasPressed("b") then
      return result
    end

    -- The object holds still for the length of the prompt and the battle, so
    -- a trainer cannot walk off in the middle of their own rematch.
    local npc = armed.npc
    local wasFrozen = npc.frozen
    npc.frozen = true
    local released = false
    ctx.done = function()
      if released then return end
      released = true
      npc.frozen = wasFrozen
    end
    ctx.world = self

    local ok, problem = pcall(Gen2.offer, ctx, armed.record)
    if not ok then
      ctx.log:warn("the rematch offer failed: %s", tostring(problem))
      ctx.done()
    end
    return result
  end

  World.gen1wildRematchHook = true
  return true
end

-- exposed for the headless suite
Gen2.trainerOf = trainerOf
Gen2.beatenTrainer = beatenTrainer
Gen2.worldIsIdle = worldIsIdle
Gen2.forget = function() pending = nil end
Gen2.pending = function() return pending end

return Gen2
