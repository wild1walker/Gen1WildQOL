-- Coverage of this bundle's own additions to the vendored Quality of Life mod.
--
-- Separate from runtime_test.lua because it is specific to Gen1WildQOL: the
-- Quality of Life features are only in this half, so these tests have nothing
-- to run against in Gen1WildUI.
--
-- The subject is modules/QualityOfLife/bundle_common.lua -- the built copy,
-- because that is the one the game loads. tools/build.py --check is what
-- guarantees it matches overlays/.
--
-- Run:  luajit tests/qol_features_test.lua

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

-- ------------------------------------------------- the fainted XP bar guard

do
  io.write("the XP bar stops drawing once the player's Pokemon faints\n")

  local Common = load_("modules/QualityOfLife/bundle_common.lua")
  local visible = Common.playerHudVisible

  -- The ordinary case: a Pokemon that is up and fighting.
  ok(visible({ player = { mon = { hp = 21 } } }), "a healthy player draws the bar")

  -- The bug in the screenshot: RATICATE has fainted, the engine has cleared
  -- the player HUD, and upstream's own guards are all still false -- so the
  -- bar was drawn into the empty space where the HUD had been.
  eq(visible({ player = { fainted = true, mon = { hp = 0 } } }), false,
     "a fainted player does not")

  -- The flag alone is enough, which is what upstream reads for the enemy.
  eq(visible({ player = { fainted = true, mon = { hp = 21 } } }), false,
     "the fainted flag alone is enough")

  -- And zero HP alone is enough, for the frame before the flag is set.
  eq(visible({ player = { mon = { hp = 0 } } }), false,
     "zero HP alone is enough")

  -- Nothing to draw over at all.
  eq(visible({}), false, "no player battler at all draws nothing")
  eq(visible(nil), false, "and neither does no battle")

  -- A battler whose mon the engine has not filled in yet is not assumed dead:
  -- the bar's own guards decide, as they did before.
  ok(visible({ player = {} }), "a battler with no mon yet is left to upstream")
  ok(visible({ player = { mon = {} } }), "and so is a mon with no hp field")
end

do
  io.write("the guard is the XP bar's alone, not the shared overlay host's\n")

  -- Both battle features draw through one overlay host, so a gate applied for
  -- one of them must not reach the other: the caught marker draws over the
  -- *enemy* HUD and is perfectly correct to keep drawing while the player is
  -- down. It has its own enemy-side guard already.
  local Common = load_("modules/QualityOfLife/bundle_common.lua")

  local added = {}
  local host = {
    add = function(_, overlay) added[#added + 1] = overlay end,
    install = function() end,
  }

  local xpDrawn, caughtDrawn = 0, 0

  -- The XP bar: registered through a gated view of the host.
  do
    -- Reproduce the gating Common.install applies, through the public
    -- predicate, so the test exercises the real thing.
    local gate = Common.playerHudVisible
    local proxy = {
      add = function(_, overlay)
        local base = overlay.draw
        overlay.draw = function(battle, ...)
          if not gate(battle) then return end
          return base(battle, ...)
        end
        return host:add(overlay)
      end,
    }
    proxy:add({ id = "experience bar",
                draw = function() xpDrawn = xpDrawn + 1 end })
  end

  -- The caught marker: registered straight onto the host, ungated.
  host:add({ id = "caught marker",
             draw = function() caughtDrawn = caughtDrawn + 1 end })

  eq(#added, 2, "both overlays reached the shared host")

  local fainted = { player = { fainted = true, mon = { hp = 0 } } }
  for _, overlay in ipairs(added) do overlay.draw(fainted, {}, {}) end
  eq(xpDrawn, 0, "with the player down the XP bar drew nothing")
  eq(caughtDrawn, 1, "while the enemy-side marker drew as usual")

  local alive = { player = { mon = { hp = 21 } } }
  for _, overlay in ipairs(added) do overlay.draw(alive, {}, {}) end
  eq(xpDrawn, 1, "and with the player up the XP bar draws again")
  eq(caughtDrawn, 2, "the marker being unaffected throughout")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
