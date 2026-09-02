-- The two rules about machines, driven against the engine's own seams.
--
-- Both features are wrappers on one engine function each, and both are the
-- kind of change that is invisible until it is wrong in the field: a TM that
-- vanishes anyway, an HM refusal that still fires.  So the seams are driven
-- here rather than described.
--
--   REUSABLE TMS      `ItemEffects.use` answers a machine with "learn" (spend
--                     the item) or "learnkept" (keep it, which is what an HM
--                     already does), and `BagMenu` calls `consume` inside
--                     `if result == "learn"`.  Retuning the verdict is the
--                     whole feature -- and it must carry every OTHER value
--                     the engine returned, because `use` is not a two-value
--                     function: the healing items answer a third, the jingle.
--
--   FORGET HM MOVES   `MoveLearnMenu:update` checks the row against IsMoveHM
--                     before it swaps and prints "HM techniques can't be
--                     deleted!" instead.  The wrapper answers the one frame
--                     the engine would have refused and runs the engine's own
--                     swap; every other frame falls through untouched.
--
-- Run:  luajit tests/qol_machines_test.lua

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

local function fakeMod()
  return {
    id = "qol",
    log = setmetatable({}, { __index = function() return function() end end }),
    hooks = { wrap = function() end },
    events = { on = function() end, once = function() end },
  }
end

-- ============================================================ REUSABLE TMS

do
  io.write("a TM is kept when it is used\n")

  -- The engine's own answers, as `ItemEffects.use` gives them.  The third
  -- return is the jingle a healing item carries; it is here because a wrapper
  -- that named its returns would silently eat it.
  local JINGLE = { sound = "Get_Item1" }
  local calls = {}
  local ItemEffects = {
    use = function(data, save, itemId, ...)
      calls[#calls + 1] = itemId
      if itemId == "TM01" then return "learn", "MEGA_PUNCH" end
      if itemId == "HM01" then return "learnkept", "CUT" end
      if itemId == "POTION" then return "consumed", { "text" }, JINGLE end
      return "failed", { "no effect" }
    end,
  }
  package.loaded["src.inventory.ItemEffects"] = ItemEffects

  local feature = load_("modules/QualityOfLife/qol_feature_reusable_tms.lua",
                        { value = 1 })
  ok(type(feature) == "table" and type(feature.install) == "function",
     "the feature loads")
  eq(feature.option.key, "qol_reusable_tms", "and owns one option row")
  eq(feature.option.default, true, "which ships on")
  eq(feature.games and feature.games[1], "gen1",
     "and says it is Gen 1 only -- Gold's items never reach this module")

  local on = true
  feature.install(fakeMod(), {
    options = { value = function(_, key)
      return key == "qol_reusable_tms" and on or nil
    end },
  })
  ok(ItemEffects.use ~= nil, "install wrapped use")

  -- ---- the verdict
  local verdict, move = ItemEffects.use({}, {}, "TM01")
  eq(verdict, "learnkept", "a TM is kept, which is what stops BagMenu "
    .. "consuming it")
  eq(move, "MEGA_PUNCH", "and still names the move it teaches")

  eq(select(1, ItemEffects.use({}, {}, "HM01")), "learnkept",
     "an HM was already kept and is unchanged")

  -- ---- everything that is not a machine
  local v, payload, jingle = ItemEffects.use({}, {}, "POTION")
  eq(v, "consumed", "a POTION is still consumed")
  eq(jingle, JINGLE, "and keeps the THIRD return -- the jingle rides the box, "
    .. "and a two-value wrapper would have taken it off")
  eq(type(payload), "table", "with its text in between")

  eq(select(1, ItemEffects.use({}, {}, "ROCK")), "failed",
     "and a refusal is still a refusal")

  -- ---- off
  on = false
  eq(select(1, ItemEffects.use({}, {}, "TM01")), "learn",
     "switched off, the TM is spent again -- the row is live, not a "
     .. "relaunch")
  on = true

  -- ---- installing twice
  --
  -- A hot reload re-runs install.  It has to wrap the ENGINE's `use` again,
  -- not the wrapper it left behind, or every reload adds a layer.
  local wrapped = ItemEffects.use
  feature.install(fakeMod(), {
    options = { value = function() return true end },
  })
  ok(ItemEffects.use ~= wrapped, "a second install replaces the wrapper")
  calls = {}
  ItemEffects.use({}, {}, "TM01")
  eq(#calls, 1, "and the engine's own use still runs exactly once")

  package.loaded["src.inventory.ItemEffects"] = nil
end

-- ========================================================= FORGET HM MOVES

do
  io.write("an HM move can be forgotten like any other\n")

  local MoveLearnMenu = { update = function(self) self.vanillaRan = true end }
  package.loaded["src.ui.MoveLearnMenu"] = MoveLearnMenu

  local feature = load_("modules/QualityOfLife/qol_feature_forget_hm.lua",
                        { value = 1 })
  ok(type(feature) == "table" and type(feature.install) == "function",
     "the feature loads")
  eq(feature.option.key, "qol_forget_hm", "and owns one option row")
  eq(feature.option.default, true, "which ships on")
  eq(feature.games and feature.games[1], "gen1", "Gen 1 only")

  -- ---- the decision, on its own
  local function menu(index, moves, selecting)
    return { selecting = selecting ~= false, index = index,
             mon = { moves = moves } }
  end
  local A = { wasPressed = function(_, key) return key == "a" end }
  local DOWN = { wasPressed = function(_, key) return key == "down" end }
  local FOUR = { { id = "TACKLE" }, { id = "SURF" }, { id = "GROWL" },
                 { id = "CUT" } }

  ok(feature.refuses(menu(2, FOUR), A),
     "SURF under the cursor with A down is the frame the engine refuses")
  ok(feature.refuses(menu(4, FOUR), A), "and so is CUT")
  ok(not feature.refuses(menu(1, FOUR), A),
     "an ordinary move is not: the engine swaps it and always did")
  ok(not feature.refuses(menu(2, FOUR), DOWN),
     "and neither is moving the cursor onto one")
  ok(not feature.refuses(menu(2, FOUR, false), A),
     "nor A during the YES/NO before the list is even up")
  ok(not feature.refuses(menu(9, FOUR), A), "a row that is not there is not one")
  ok(not feature.refuses(nil, A), "and no menu at all is not a crash")

  -- ---- the wrapper
  local finished, game
  local function standIn(index)
    return {
      selecting = true,
      index = index,
      newMoveId = "SURF",
      mon = { moves = { { id = "TACKLE", pp = 35 }, { id = "SURF", pp = 15 },
                        { id = "GROWL", pp = 40 }, { id = "CUT", pp = 30 } } },
      game = game,
      finish = function(_, learned) finished = learned end,
    }
  end
  game = { input = A,
           data = { moves = { SURF = { name = "SURF", pp = 15 },
                              CUT = { name = "CUT", pp = 30 },
                              TACKLE = { name = "TACKLE", pp = 35 } } } }

  local on = true
  feature.install(fakeMod(), {
    options = { value = function(_, key)
      return key == "qol_forget_hm" and on or nil
    end },
  })

  local hm = standIn(4)                       -- CUT, which the engine refuses
  finished = nil
  MoveLearnMenu.update(hm, 0)
  ok(not hm.vanillaRan, "the refused frame does not reach the engine")
  eq(hm.mon.moves[4].id, "SURF", "the HM slot takes the new move")
  eq(hm.mon.moves[4].pp, 15, "at the new move's own PP")
  eq(hm.forgot, "CUT", "and the forgotten name is set for the Poof! page")
  eq(finished, true, "then finish runs the engine's own pages")

  local plain = standIn(1)                    -- TACKLE, which it never refused
  MoveLearnMenu.update(plain, 0)
  ok(plain.vanillaRan, "an ordinary row is still the engine's to handle")
  eq(plain.mon.moves[1].id, "TACKLE", "and this wrapper touched nothing")

  on = false
  local off = standIn(4)
  MoveLearnMenu.update(off, 0)
  ok(off.vanillaRan, "switched off, the HM row goes back to the engine -- "
    .. "and to its refusal")
  eq(off.forgot, nil, "with no swap of ours behind it")
  on = true

  -- ---- installing twice
  local wrapped = MoveLearnMenu.update
  feature.install(fakeMod(), { options = { value = function() return true end } })
  ok(MoveLearnMenu.update ~= wrapped, "a second install replaces the wrapper")
  local again = standIn(1)
  MoveLearnMenu.update(again, 0)
  ok(again.vanillaRan,
     "and the engine's own update is still one call away, not two")

  package.loaded["src.ui.MoveLearnMenu"] = nil
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
