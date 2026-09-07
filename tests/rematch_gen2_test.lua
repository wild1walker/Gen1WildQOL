-- TRAINER REMATCH on Gold: the talk, the gate, the offer and the battle.
--
-- The Gen 1 arm is covered by tests/rematch_test.lua.  This one is the Gold
-- arm, which shares the feature and none of the seams: no `world.talk` hook,
-- no single TextBox to watch, no BattleState.newTrainer.  What it hangs on
-- instead is World:interactBody and World:STEP, so those are what this file
-- drives -- a World stood up with the fields the arm actually reads, and the
-- SHIPPED gen2.lua loaded over it rather than a copy retyped here.
--
-- A stand-in World is only worth anything if it is the shape of the real one,
-- and this one was not.  It DECLARED a `World:update` and the arm patched it,
-- so every assertion below passed -- while Gold's World has no `update` at
-- all (src/core/Game2.lua calls `world:step()`), the arm's own guard took its
-- early exit on the cartridge, and TRAINER REMATCH never installed.  The stub
-- agreed with the mistake instead of checking it.
--
-- So the seam NAMES are now read off the engine before anything is stood up
-- (see "the seams, read off the cart" below), and the stand-in is built from
-- that list.  A method the arm reaches for that Gold does not have is a
-- failure here rather than a feature that silently never runs.
--
-- The gate is the interesting part and most of the assertions are about it:
-- an offer must appear only after a talk that ENDED, on a trainer already
-- beaten before the press, and never over a script still running, a box still
-- up, a battle, or a fade.
--
-- Run:  luajit tests/rematch_gen2_test.lua

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

-- ---- the seams, read off the cart
--
-- The check that was missing.  Every method gen2.lua patches or calls on the
-- Gen 2 World is named in `Gen2.SEAMS`, and every one of them has to be a
-- method the ENGINE actually defines -- not one this file made up to make its
-- own stand-in work.  Without this, `World.update` looked fine for as long as
-- the stub below declared it.
--
-- SKIPs without an engine tree, because the shape assertions underneath are
-- worth running on their own; the names are checked wherever a checkout is.

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    for _, name in ipairs({ "gen1recompog", "gen1recomp", "bryanthaboi/gen1recomp" }) do
      candidates[#candidates + 1] = prefix .. "/" .. name
    end
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/world/gen2/World.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end

local function slurp(path)
  local handle = io.open(path)
  if not handle then return nil end
  local text = handle:read("*a") handle:close() return text
end

local SEAMS do
  local chunk = assert(loadfile("modules/Gen1Rematch/gen2.lua"))
  SEAMS = chunk().SEAMS
  ok(type(SEAMS) == "table" and #SEAMS > 0, "the arm names the seams it needs")
end

if ENGINE then
  local worldSrc = assert(slurp(ENGINE .. "/src/world/gen2/World.lua"))
  for _, name in ipairs(SEAMS) do
    ok(worldSrc:find("function World:" .. name .. "(", 1, true) ~= nil,
       "the Gen 2 World really defines " .. name .. "()")
  end
  -- The one that was wrong, stated both ways round so a rename in either
  -- direction fails here rather than in someone's game.
  ok(worldSrc:find("function World:step()", 1, true) ~= nil,
     "Gold's World ticks through step()")
  ok(worldSrc:find("function World:update(", 1, true) == nil,
     "and has no update() at all -- which is what this file used to assume")
  local gameSrc = assert(slurp(ENGINE .. "/src/core/Game2.lua"))
  ok(gameSrc:find("self.world:step()", 1, true) ~= nil,
     "and Game2 is what calls it, once a frame")
  local armSrc = assert(slurp("modules/Gen1Rematch/gen2.lua"))
  ok(armSrc:find("local innerStep = World.step", 1, true) ~= nil,
     "so the arm wraps step")
  -- Code, not prose: the note above the guard still tells the story of the
  -- bug by name, and should.
  ok(armSrc:find("function World:update", 1, true) == nil,
     "and defines no update of its own")
  ok(armSrc:find("= World.update", 1, true) == nil,
     "nor captures one to call through")

  -- The two data fields the price is read out of, likewise off the engine:
  -- a rename there is a rematch that quotes 0 and charges nothing.
  local lookup = assert(slurp(ENGINE .. "/src/world/gen2/Trainers.lua"))
  ok(lookup:find("roster = row.party or {},", 1, true) ~= nil,
     "a looked-up trainer carries its rows as `roster`")
  ok(lookup:find("baseMoney = entry.baseMoney,", 1, true) ~= nil,
     "and the class's `baseMoney`")
else
  io.write("  note: no engine tree; the seam names are unchecked\n")
end

-- ---- the shipped arm, and a fake engine under it
--
-- gen2.lua reaches for src.world.gen2.World and src.world.gen2.Trainers by
-- name, so those are what get stood up: a World CLASS whose methods the arm
-- patches, exactly as it would patch the cart's.

local World = {}
World.__index = World

function World:facingObject() return self.faced end
function World:trainerBeaten(record)
  return record ~= nil and self.beaten[record.event] == true
end
function World:busy() return self.isBusy == true end
function World:interactBody()
  -- The cart's shape: a trainer object starts its script, and the script is
  -- what says the line.  Anything else answers false.
  if not self.faced then return false end
  self.vm.busy = true
  self.talked = (self.talked or 0) + 1
  return true
end
function World:step() self.steps = (self.steps or 0) + 1 end
function World:trainerParty(class, member)
  local roster = self.rosters[tostring(class) .. "/" .. tostring(member)]
  if not roster then return nil end
  -- The shape Trainers.lookup really returns: the data rows live on
  -- `roster`, and `Trainers.party` is what would turn them into mons.
  return { class = class, member = member, baseMoney = roster.baseMoney,
           name = roster.name, roster = roster.roster }
end
function World:startScriptedBattle(entry, wild, onDone)
  self.fought = { entry = entry, wild = wild }
  self.finishBattle = onDone
  return true
end
function World:showText(body, onDone, stay)
  self.said = self.said or {}
  self.said[#self.said + 1] = body
  self.textbox = true
  self.pendingText = function()
    self.textbox = not stay and nil or self.textbox
    if onDone then onDone() end
  end
end
function World:askYesNo(onChoose)
  self.choicebox = true
  self.pendingChoice = function(yes)
    self.textbox, self.choicebox = nil, nil
    onChoose(yes)
  end
end

package.loaded["src.world.gen2.World"] = World
local function newWorld(game)
  return setmetatable({
    game = game, vm = { busy = false, running = function(self) return self.busy end },
    beaten = {}, rosters = {},
  }, World)
end

local Gen2 = assert(loadfile("modules/Gen1Rematch/gen2.lua"))()

-- ---- the context main.lua builds

local logged = {}
local prize, scale, enabled = true, true, true
local ctx
ctx = {
  -- `info` as well as warn/error.  main.lua hands the arm `mod.log`, which
  -- has all three; this stand-in had two, so the first call to log:info on
  -- the refusal path raised inside the pcall in step() and the offer
  -- vanished with nothing said -- a stand-in narrower than the real thing,
  -- failing in the one place the feature was already being reported broken.
  log = { warn = function(_, f, ...) logged[#logged + 1] = tostring(f) end,
          error = function(_, f, ...) logged[#logged + 1] = tostring(f) end,
          info = function(_, f, ...) logged[#logged + 1] = tostring(f) end },
  say = function(text) return text end,
  matched = function(_, party)
    -- MATCH LEVELS, stood up as "everybody gains ten", which is enough to
    -- prove the price is quoted off the SCALED party rather than the raw one.
    local out = {}
    for i, slot in ipairs(party) do
      out[i] = { level = (slot.level or 1) + 10 }
    end
    return out
  end,
  text = { ASK = "Want to battle\nagain?",
           PRICED = "Want to battle\nagain?\fThat will be\n%d. OK?",
           BROKE = "You don't have\nenough money."
             .. "\fA rematch costs\n%d." },
  enabled = function() return enabled end,
  wantPrize = function() return prize end,
  wantScale = function() return scale end,
  arm = function(value) ctx.armed = value end,
  done = function() end,
}

eq(Gen2.install(ctx), true, "the Gold arm installs")
eq(Gen2.install(ctx), true, "and a second install is a no-op")

-- ---- a beaten trainer, talked to

local JOEY = { class = "YOUNGSTER", member = "JOEY1", event = "BEAT_JOEY" }

-- The purse sits where GOLD keeps it, not where Red does.  This harness used
-- to build `save.money`, which is Red's field (src/ui/ShopMenu.lua) -- so it
-- agreed with the arm it was testing and both were wrong together, and every
-- check below passed while the game refused every rematch for want of money.
-- src/core/gen2/Save.lua:496 normalizes `save.player.money`; :186 seeds it.
local function purse(game) return game.save.player.money end
local function setPurse(game, amount) game.save.player.money = amount end

local function scene(money)
  local game = { save = { player = { money = money or 5000 },
                          party = { { level = 30 } } },
                 input = { wasPressed = function() return false end } }
  local w = newWorld(game)
  w.faced = { def = { trainer = JOEY } }
  w.beaten["BEAT_JOEY"] = true
  w.rosters["YOUNGSTER/JOEY1"] = {
    baseMoney = 20, name = "JOEY",
    roster = { { level = 4 }, { level = 6 } },
  }
  Gen2.forget()
  return w, game
end

do
  local w = scene()
  eq(w:interactBody(), true, "the talk starts")
  ok(Gen2.pending() ~= nil, "and the arm remembered whose talk it was")

  -- The script is still running: no offer.
  w:step()
  eq(w.said, nil, "nothing is offered while the script is still running")
  ok(Gen2.pending() ~= nil, "and the arm is still waiting")

  -- The script ends.  Now the offer.
  w.vm.busy = false
  w:step()
  ok(w.said and w.said[1], "the offer comes when the talk has ended")
  eq(Gen2.pending(), nil, "and the arm lets go of the talk")

  -- HALF THE PRIZE, and on Gold the prize is four times what it is on Red.
  -- Both carts multiply the class's base reward by the LAST party row's
  -- level; Red pays that once, Gold pays Prize.QUARTERS of them
  -- (src/battle/gen2/Prize.lua:169, :201).  20 base x the last mon's level
  -- scaled +10 => 16, is 320 a quarter, 1280 paid, 640 staked.  Copying
  -- Red's halving straight over staked 160 -- an EIGHTH of the purse.
  --
  -- Read off the engine rather than written down, so a cart that changes the
  -- split moves this with it instead of leaving the number stale.
  -- READ off the engine, not required from it: Prize pulls in src.core.Strings
  -- at load and the mod's own directory is what is on package.path here.  The
  -- rest of this file already reads engine facts out of the source this way
  -- (the World's method names, Game2's step call, Trainers.lookup's shape),
  -- and the point is the same -- the number below must be the cart's, not one
  -- this test made up to agree with the code it is checking.
  local quarters = 4
  if ENGINE then
    local prizeSrc = assert(slurp(ENGINE .. "/src/battle/gen2/Prize.lua"))
    quarters = tonumber(prizeSrc:match("Prize%.QUARTERS%s*=%s*(%d+)"))
    ok(quarters ~= nil, "the engine states how many quarters a reward is paid in")
    eq(quarters, 4, "and Gold pays four of them")
  end
  local paid = 20 * 16 * quarters
  -- math.floor, not `//`: this suite runs under LuaJIT as well as 5.4.
  eq(math.floor(paid / 2), 640, "half of what this battle pays is 640")
  eq(w.said[1], "Want to battle\nagain?\fThat will be\n640. OK?",
     "the price is half of what winning actually pays")

  -- The page is up; the YES/NO opens over it.
  w.pendingText()
  ok(w.choicebox, "the YES/NO opens over the page that asked")

  w.pendingChoice(true)
  ok(w.fought ~= nil, "YES fights them")
  eq(w.fought.entry.name, "JOEY", "against the roster the object carries")
  eq(w.fought.wild, nil, "as a trainer battle, not a wild one")

  -- ------- MATCH LEVELS reaches the BATTLE, not just the quote
  --
  -- Red scales through the `trainer.party` hook and gets a rebuild for free:
  -- the hook is handed the ROSTER ROWS and BattleState makes mons out of
  -- whatever comes back, so a scaled mon arrives with its new level's stats,
  -- its new level's learnset and full HP.  Gold calls the same hook, but by
  -- then Trainers.party has already BUILT the party -- so writing `level`
  -- there moved the number and left the moves and the HP where they were.
  --
  -- The roster the battle is built FROM is the same input Red's hook gets,
  -- so that is what is offset.  This asserts the rows the cart will build
  -- from, which is the only place the difference shows.
  local roster = w.fought.entry.roster
  eq(#roster, 2, "the whole roster is handed over, not just the last row")
  eq(roster[1].level, 14, "the first row is offset by the same delta")
  eq(roster[2].level, 16, "and so is the last, which is the one priced")
  eq(roster[2].level - roster[1].level, 2,
     "the steps between their mons survive -- an offset, not a multiplier")

  -- The record `trainerParty` hands back is the CART's own lookup.  A
  -- levelled-up roster left in it would still be there the next time this
  -- trainer is fought for real, so the scaling copies rather than edits.
  local fresh = w:trainerParty("YOUNGSTER", "JOEY1")
  eq(fresh.roster[2].level, 6, "the cart's own roster is left where it was")
  eq(purse(w.game), 5000 - 640, "and the stake is taken up front")

  w.finishBattle("win")
  eq(purse(w.game), 5000 - 640,
     "a win keeps the stake spent -- the engine pays the other half")
end

-- ---- NO costs nothing

do
  local w = scene()
  w:interactBody(); w.vm.busy = false; w:step()
  w.pendingText(); w.pendingChoice(false)
  eq(w.fought, nil, "NO does not start a battle")
  eq(purse(w.game), 5000, "and takes no money")
end

-- ---- REMATCH PRIZE off: no stake, and the payout handed back

do
  prize = false
  local w = scene()
  w:interactBody(); w.vm.busy = false; w:step()
  eq(w.said[1], "Want to battle\nagain?", "with the prize off, no price is quoted")
  w.pendingText(); w.pendingChoice(true)
  eq(purse(w.game), 5000, "nothing is staked")
  setPurse(w.game, 9999)            -- as if the engine had paid out
  w.finishBattle("win")
  eq(purse(w.game), 5000, "and the engine's payout is put back")
  prize = true
end

-- ---- MATCH LEVELS off changes the quote

do
  scale = false
  local w = scene()
  w:interactBody(); w.vm.busy = false; w:step()
  -- 20 base x 6, the last row's own level: 120 a quarter, 480 paid, 240
  -- staked.
  eq(w.said[1], "Want to battle\nagain?\fThat will be\n240. OK?",
     "unscaled, the price is off the party as it stands")
  scale = true
end

-- ---- too poor to play

do
  local w = scene(10)
  w:interactBody(); w.vm.busy = false; w:step()
  -- The refusal QUOTES the price.  It used to say only that the money was
  -- short, which is what made "it always says I can't afford it" impossible
  -- to answer from a report: a price nobody can pay and a purse read out of
  -- the wrong field produce the identical sentence.
  eq(w.said[1], "You don't have\nenough money.\fA rematch costs\n640.",
     "a price you cannot pay is said so, and named")
  w.pendingText()
  eq(w.choicebox, nil, "and no question is asked")
  eq(w.fought, nil, "and nothing is fought")
end

-- ---- the gate: everything that is NOT an ended talk

do
  local w = scene()
  w:interactBody()
  w.vm.busy = false
  w.textbox = true                      -- a box still up
  w:step()
  eq(w.said, nil, "no offer while a box is still up")
  w.textbox = nil
  w.battleActive = true                 -- a battle
  w:step()
  eq(w.said, nil, "no offer over a battle")
  w.battleActive = nil
  w.mapSetup = { phase = "in" }         -- a fade
  w:step()
  eq(w.said, nil, "no offer mid-fade")
  w.mapSetup = nil
  w.isBusy = true                       -- the world says it is busy
  w:step()
  eq(w.said, nil, "no offer while the world is busy")
  w.isBusy = false
  w:step()
  ok(w.said and w.said[1], "and the offer lands once all of that has cleared")
end

-- ---- B out of the line is nothing at all

do
  local w = scene()
  w.game.input.wasPressed = function(_, button) return button == "b" end
  w:interactBody(); w.vm.busy = false; w:step()
  eq(w.said, nil, "B out of the line asks nothing")
  eq(w.fought, nil, "and fights nothing")
end

-- ---- a trainer who has NOT been beaten is a first fight, not a rematch

do
  local w = scene()
  w.beaten["BEAT_JOEY"] = false
  w:interactBody(); w.vm.busy = false; w:step()
  eq(w.said, nil, "an unbeaten trainer gets no offer")
  eq(Gen2.pending(), nil, "and is never armed for one")
end

-- ---- neither is an object that is not a trainer

do
  local w = scene()
  w.faced = { def = {} }
  w:interactBody(); w.vm.busy = false; w:step()
  eq(w.said, nil, "a plain object gets no offer")
end

-- ---- a press that started no talk arms nothing

do
  local w = scene()
  w.faced = nil
  eq(w:interactBody(), false, "a press into empty air starts no talk")
  eq(Gen2.pending(), nil, "and arms nothing")
end

-- ---- the feature switched off is the vanilla interaction back

do
  enabled = false
  local w = scene()
  w:interactBody(); w.vm.busy = false; w:step()
  eq(w.said, nil, "OFF asks nothing")
  eq(Gen2.pending(), nil, "and remembers nothing")
  eq(w.talked, 1, "the engine's own talk still happened")
  enabled = true
end

-- ---- MATCH LEVELS is armed only for this feature's own battle

do
  local w = scene()
  ctx.armed = nil
  w:interactBody(); w.vm.busy = false; w:step()
  eq(ctx.armed, nil, "the level hook is not armed while the question is up")
  w.pendingText(); w.pendingChoice(true)
  eq(ctx.armed, false, "and is disarmed again the moment the battle is built")
end

-- ---- the trainer is held still for the length of it

do
  local w = scene()
  local npc = w.faced
  w:interactBody(); w.vm.busy = false; w:step()
  eq(npc.frozen, true, "the trainer holds still while the question is up")
  w.pendingText(); w.pendingChoice(false)
  eq(npc.frozen, nil, "and is let go when the answer is no")
end

io.write(("rematch_gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
