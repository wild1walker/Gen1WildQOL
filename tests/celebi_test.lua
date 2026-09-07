-- Headless coverage of the GS BALL arm (modules/Gen151/gen2/celebi.lua).
--
-- The whole feature is one byte, so the only thing that can be wrong is WHEN
-- it is written.  Two ways, and both lose a playthrough:
--
--   * writing it on a save that has already been through the event offers the
--     ball a second time, which on Crystal means the receptionist walks over
--     again after KURT has already taken it away.
--   * not writing it at all leaves the eleven scripts behind it dead, which
--     is the bug the feature exists to fix.
--
-- Run:  luajit tests/celebi_test.lua

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

local function load_(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

local Celebi = load_("modules/Gen151/gen2/celebi.lua")

-- ------------------------------------------------------------ arming a save

do
  io.write("arming a save\n")

  local save = {}
  eq(Celebi.arm(save), true, "a fresh save gets the flag")
  eq(save.crystal.gsBall, "have",
     "and the flag is `have` -- what the Mobile Adapter would have left, and "
     .. "what BattleTowerAction reads back as GS_BALL_AVAILABLE")

  -- The save may arrive with a crystal block already on it (Save.crystalState
  -- builds one for the beasts, Buena and the move tutor), so the write must
  -- land IN that table rather than replacing it.
  local existing = { crystal = { celebiCaught = false, beasts = { 1, 2 } } }
  eq(Celebi.arm(existing), true, "a save that already has a crystal block arms")
  eq(existing.crystal.gsBall, "have", "the flag lands in it")
  eq(existing.crystal.beasts[2], 2, "and nothing else in the block is touched")
end

-- --------------------------------------------------------- not arming twice

do
  io.write("leaving a started event alone\n")

  -- The three live states, each meaning the ball has already been offered.
  for _, state in ipairs({ "have", "given", "used" }) do
    local save = { crystal = { gsBall = state } }
    eq(Celebi.arm(save), false, "a save reading `" .. state .. "` is left alone")
    eq(save.crystal.gsBall, state, "and keeps the state it had")
  end

  -- `used` is the one with teeth: the player has finished the event, and
  -- rewriting it to `have` would start the whole thing over.
  local done = { crystal = { gsBall = "used", celebiCaught = true } }
  Celebi.arm(done)
  eq(done.crystal.gsBall, "used",
     "a finished event stays finished -- rewriting `used` would send the "
     .. "receptionist after a player who already has CELEBI")

  local twice = {}
  Celebi.arm(twice)
  eq(Celebi.arm(twice), false,
     "arming is idempotent, which matters because save.created and "
     .. "save.loaded can both fire across one session")
end

-- ---------------------------------------------------------- a save it is not

do
  io.write("a payload that is not a save\n")
  eq(Celebi.arm(nil), false, "no save arms nothing")
  eq(Celebi.arm("save"), false, "and neither does something that is not a table")
  ok(pcall(Celebi.arm), "a missing argument does not raise")
end

io.write(("celebi: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
