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
  log = { warn = function(_, f, ...) logged[#logged + 1] = tostring(f) end,
          error = function(_, f, ...) logged[#logged + 1] = tostring(f) end },
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
           BROKE = "You don't have\nenough money." },
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

  -- 20 base x the LAST mon's level, scaled +10 => 16, halved.
  eq(w.said[1], "Want to battle\nagain?\fThat will be\n160. OK?",
     "the price is base x the last mon's MATCHED level, halved")

  -- The page is up; the YES/NO opens over it.
  w.pendingText()
  ok(w.choicebox, "the YES/NO opens over the page that asked")

  w.pendingChoice(true)
  ok(w.fought ~= nil, "YES fights them")
  eq(w.fought.entry.name, "JOEY", "against the roster the object carries")
  eq(w.fought.wild, nil, "as a trainer battle, not a wild one")
  eq(purse(w.game), 5000 - 160, "and the stake is taken up front")

  w.finishBattle("win")
  eq(purse(w.game), 5000 - 160,
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
  eq(w.said[1], "Want to battle\nagain?\fThat will be\n60. OK?",
     "unscaled, the price is off the party as it stands")
  scale = true
end

-- ---- too poor to play

do
  local w = scene(10)
  w:interactBody(); w.vm.busy = false; w:step()
  eq(w.said[1], "You don't have\nenough money.", "a price you cannot pay is said so")
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
