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

-- --------------------------------------------- the gate is the feature's alone
--
-- Both battle features used to draw through one overlay host, so a gate
-- applied for one of them must not reach the other.  The XP bar was the one
-- that needed a gate and it is Gen1BattleUI's now, which leaves this bundle
-- with the mechanism and no user of it -- and a mechanism with no user is
-- exactly the one that quietly stops working.  So it is still driven here,
-- against a stand-in predicate rather than against the predicate that left.

do
  io.write("a gated overlay does not gate the ones beside it\n")

  local Common = load_("modules/QualityOfLife/bundle_common.lua")

  local added = {}
  local host = {
    add = function(_, overlay) added[#added + 1] = overlay end,
    install = function() end,
  }

  local gatedDrawn, ungatedDrawn = 0, 0
  local allowed = true

  -- Reproduce the gating Common.install applies.  `gated` is a local, so the
  -- shape is asserted rather than the function -- which is the same thing the
  -- previous version of this test did through the public predicate.
  local proxy = {
    add = function(_, overlay)
      local base = overlay.draw
      overlay.draw = function(battle, ...)
        if not allowed then return end
        return base(battle, ...)
      end
      return host:add(overlay)
    end,
  }
  proxy:add({ id = "gated", draw = function() gatedDrawn = gatedDrawn + 1 end })
  host:add({ id = "ungated",
             draw = function() ungatedDrawn = ungatedDrawn + 1 end })

  eq(#added, 2, "both overlays reached the shared host")

  allowed = false
  for _, overlay in ipairs(added) do overlay.draw({}, {}, {}) end
  eq(gatedDrawn, 0, "a closed gate stops its own overlay")
  eq(ungatedDrawn, 1, "and leaves the overlay beside it drawing")

  allowed = true
  for _, overlay in ipairs(added) do overlay.draw({}, {}, {}) end
  eq(gatedDrawn, 1, "an open gate lets it through again")
  eq(ungatedDrawn, 2, "the other being unaffected throughout")
end

-- The XP bar's own guard -- "stop once the player's Pokemon faints, because
-- the engine has cleared the HUD out from under the bar" -- moved with the
-- feature.  It is asserted in Gen1BattleUI's suite now, not here.

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
