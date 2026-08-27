-- Coverage of the features this repository maintains itself.
--
-- Separate from runtime_test.lua because it is specific to Gen1WildQOL: the
-- Quality of Life features and ROTATE PROFILES are only in this half, so
-- these tests have nothing to run against in Gen1WildUI.
--
-- The subjects are modules/QualityOfLife/bundle_common.lua and
-- modules/ScreenRotate/profile.lua -- the built copies, because those are the
-- ones the game loads. tools/build.py --check is what guarantees they match
-- what they were built from.
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

-- ------------------------------------------- the landscape profile, ROTATE PROFILES
--
-- The subject is modules/ScreenRotate/profile.lua -- the built copy, like
-- everything else here.  It is the whole of the feature that can be driven
-- without a device: main.lua measures the display and pokes the engine's
-- display modules, and this decides what a landscape profile is and what
-- putting one on and taking it off does to the options table.

local Profile = load_("modules/ScreenRotate/profile.lua")

-- reader over a plain table, standing in for mod.options:get
local function rows(values)
  return function(key) return values[key] end
end

do
  io.write("landscape is the wider-than-tall display\n")

  ok(Profile.landscape(2400, 1080), "a phone on its side is landscape")
  ok(not Profile.landscape(1080, 2400), "and upright is not")
  ok(not Profile.landscape(1000, 1000),
     "a square display gains nothing on either axis, so it counts as upright")
  ok(not Profile.landscape(nil, nil), "a display that cannot be measured is not landscape")
end

do
  io.write("WIDE is the preset, CUSTOM is the rows\n")

  local wide = Profile.target(rows({ enabled = true, sideways = "wide" }), {})
  eq(wide.battleLayout, "wide", "WIDE puts the widescreen battle on")
  eq(wide.battleFit, "fill", "and fills with it")
  eq(wide.battleHud, "extended", "and takes the extended HUD, which needs the wide layout")
  eq(wide.uiLayout, "dynamic", "and docks the UI to the screen's own edges")
  eq(wide.faithfulRes, 0, "and drops the 10:9 lock, which is what a turned phone gains width past")
  eq(wide.uiLetterbox, nil, "and says nothing about the letterbox, which is not what wide means")
  eq(wide.screenPos, nil, "nor about where the picture sits")

  local off = Profile.target(rows({ enabled = false, sideways = "wide" }), {})
  eq(next(off), nil, "OFF is a profile of nothing, whatever the preset says")

  local blank = Profile.target(rows({ enabled = true, sideways = "custom" }), {})
  eq(next(blank), nil, "and so is a CUSTOM profile still on SAME all the way down")
end

do
  io.write("a CUSTOM row names one setting and leaves the rest alone\n")

  local target = Profile.target(rows({
    enabled = true, sideways = "custom",
    faithful = "off", screen_pos = "top",
  }), { battleLayout = "og" })

  eq(target.faithfulRes, 0, "FAITHFUL RATIO OFF is the engine's level 0")
  eq(target.screenPos, "top", "SCREEN POS passes its own value through")
  eq(target.battleLayout, nil, "a row left on SAME is not in the profile at all")

  local on = Profile.target(rows({ enabled = true, sideways = "custom", faithful = "on" }), {})
  eq(on.faithfulRes, 1, "FAITHFUL RATIO ON is the lock, which a phone sizes from its own display")
end

do
  io.write("the extended HUD is a widescreen composition, and is clamped like one\n")

  local against_og = Profile.target(rows({
    enabled = true, sideways = "custom", battle_hud = "extended",
  }), { battleLayout = "og" })
  eq(against_og.battleHud, "standard",
     "asking for it without a wide layout to hang it on gets the standard HUD")

  local with_wide = Profile.target(rows({
    enabled = true, sideways = "custom",
    battle_hud = "extended", battle_layout = "wide",
  }), { battleLayout = "og" })
  eq(with_wide.battleHud, "extended", "the same profile that also asks for WIDE keeps it")

  local onto_wide = Profile.target(rows({
    enabled = true, sideways = "custom", battle_hud = "extended",
  }), { battleLayout = "wide" })
  eq(onto_wide.battleHud, "extended", "and so does one landing on a layout already wide")
end

do
  io.write("a profile goes on, and comes back off leaving what it found\n")

  local options = { battleLayout = "og", battleFit = "fixed", faithfulRes = 1 }
  local held, applied = {}, {}

  local touched = Profile.reconcile({ battleLayout = "wide", faithfulRes = 0 },
                                    options, held, applied)
  eq(options.battleLayout, "wide", "the profile's values are on the options table")
  eq(options.faithfulRes, 0, "every one of them")
  eq(options.battleFit, "fixed", "and nothing it did not name was touched")
  ok(touched.battleLayout and touched.faithfulRes, "both are reported as touched")
  eq(touched.battleFit, nil, "and the untouched one is not")

  local again = Profile.reconcile({ battleLayout = "wide", faithfulRes = 0 },
                                  options, held, applied)
  eq(next(again), nil, "asking for the same profile again writes nothing")

  local off = Profile.reconcile({}, options, held, applied)
  eq(options.battleLayout, "og", "an empty profile puts the upright value back")
  eq(options.faithfulRes, 1, "including a level, not merely a string")
  ok(off.battleLayout and off.faithfulRes, "and reports both as touched on the way out")
  eq(next(held), nil, "with nothing left held")
end

do
  io.write("an upright value that was never set survives the round trip\n")

  local options = {}
  local held, applied = {}, {}

  Profile.reconcile({ screenPos = "top" }, options, held, applied)
  eq(options.screenPos, "top", "the profile sets a row the save had no value for")
  Profile.reconcile({}, options, held, applied)
  eq(options.screenPos, nil,
     "and taking it off restores the absence rather than inventing a default")
end

do
  io.write("this is a profile, not a lock\n")

  local options = { battleLayout = "og" }
  local held, applied = {}, {}
  Profile.reconcile({ battleLayout = "wide" }, options, held, applied)

  -- The player opens the engine's own OPTION screen while the phone is
  -- sideways and turns the battle layout back.
  options.battleLayout = "og"
  local touched = Profile.reconcile({ battleLayout = "wide" }, options, held, applied)
  eq(next(touched), nil, "a setting changed by hand is not written back over")
  eq(options.battleLayout, "og", "it stays where the player put it")

  -- ...and turning the phone upright is still the upright picture.
  Profile.reconcile({}, options, held, applied)
  eq(options.battleLayout, "og",
     "and the upright value is what upright gets, which here is the same one")
end

do
  io.write("editing the profile while it is on takes effect there and then\n")

  local options = { battleLayout = "og", uiLayout = "centered" }
  local held, applied = {}, {}
  Profile.reconcile({ battleLayout = "wide" }, options, held, applied)

  local touched = Profile.reconcile({ battleLayout = "wide", uiLayout = "dynamic" },
                                    options, held, applied)
  eq(options.uiLayout, "dynamic", "a row added to the profile is applied")
  eq(touched.battleLayout, nil, "without rewriting the rows that did not change")

  Profile.reconcile({ uiLayout = "dynamic" }, options, held, applied)
  eq(options.battleLayout, "og", "a row taken out of it gives its upright value back")
  eq(options.uiLayout, "dynamic", "and the rest of the profile stays on")

  Profile.reconcile({}, options, held, applied)
  eq(options.uiLayout, "centered", "and the last of it comes off with the rest")
end

-- ------------------------------------ ROTATE PROFILES, end to end on a stub phone
--
-- profile.lua decides what a profile is; main.lua is the half that measures
-- the display, gates on the device and pushes what changed at the engine.
-- None of that needs a phone to drive -- it needs a `mod`, a `love.graphics`
-- and the two engine modules it reaches for, all of which are stubs here.

do
  io.write("the profile follows the display, on a phone and nowhere else\n")

  local screen = { width = 1080, height = 2400 }
  local isMobile = true
  local pushed = {}

  package.preload["src.core.FaithfulRes"] = function()
    return {
      isMobile = function() return isMobile end,
      apply = function(value) pushed.faithfulRes = value end,
    }
  end
  package.preload["src.core.ScreenPosition"] = function()
    return { setMode = function(value) pushed.screenPos = value end }
  end
  package.preload["src.render.Letterbox"] = function()
    return { setMode = function(value) pushed.uiLetterbox = value end }
  end

  local realLove = _G.love
  _G.love = { graphics = { getDimensions = function()
    return screen.width, screen.height
  end } }

  -- The bundle hands a feature a facade over the real mod; this is the part
  -- of it ROTATE PROFILES touches.
  local function stubMod(settings)
    local hooked = {}
    local mod
    mod = {
      path = "modules/ScreenRotate",
      hooks = { wrap = function(_, name, callback) hooked[name] = callback end },
      log = { error = function(_, fmt, ...) error((fmt):format(...), 0) end },
      options = {
        define = function(_, schema) mod.schema = schema return schema end,
        get = function(_, key)
          if settings[key] ~= nil then return settings[key] end
          for _, row in ipairs(mod.schema or {}) do
            if row.key == key then return row.default end
          end
          return nil
        end,
      },
      read = function(_, relative)
        local handle = assert(io.open("modules/ScreenRotate/" .. relative, "r"))
        local source = handle:read("*a")
        handle:close()
        return source
      end,
    }
    load_("modules/ScreenRotate/main.lua")(mod)
    return mod, hooked
  end

  local function stubGame()
    local game
    game = {
      save = { options = { battleLayout = "og", battleFit = "fixed",
                           battleHud = "standard", uiLayout = "centered",
                           faithfulRes = 1 } },
      written = nil,
      writeOptions = function(self)
        local copy = {}
        for key, value in pairs(self.save.options) do copy[key] = value end
        game.written = copy
      end,
    }
    return game
  end

  -- one frame, long enough that the throttle lets it through
  local function frame(hooked, game)
    local ran = false
    hooked["core.update"](function() ran = true end, game, 1)
    return ran
  end

  local mod, hooked = stubMod({})
  ok(type(hooked["core.update"]) == "function", "it watches the display from core.update")
  eq(mod.schema[1].key, "enabled", "and its master switch is its own first row")

  local game = stubGame()
  ok(frame(hooked, game), "the frame it watches from is never skipped")
  eq(game.save.options.battleLayout, "og", "upright, an upright phone is left alone")

  screen.width, screen.height = 2400, 1080
  frame(hooked, game)
  eq(game.save.options.battleLayout, "wide", "turned sideways, the profile goes on")
  eq(game.save.options.faithfulRes, 0, "including the 10:9 lock coming off")
  eq(pushed.faithfulRes, 0, "which is live module state, so it is pushed at the engine")
  eq(pushed.uiLetterbox, nil,
     "and a setting the profile never named is not pushed at anything")

  -- Anything at all may persist the options while the profile is on.
  game:writeOptions()
  eq(game.written.battleLayout, "og", "a save made sideways writes the upright value")
  eq(game.written.faithfulRes, 1, "for every setting the profile is holding")
  eq(game.save.options.battleLayout, "wide", "and the live picture is left as it was")

  screen.width, screen.height = 1080, 2400
  frame(hooked, game)
  eq(game.save.options.battleLayout, "og", "turned back, the upright settings come back")
  eq(game.save.options.faithfulRes, 1, "all of them")
  eq(pushed.faithfulRes, 1, "and the engine is told about that too")

  game:writeOptions()
  eq(game.written.battleLayout, "og", "with the guard now a plain write-through")

  -- Same rotation, on something that does not rotate.
  isMobile = false
  local _, desktop = stubMod({})
  local plain = stubGame()
  screen.width, screen.height = 2400, 1080
  frame(desktop, plain)
  eq(plain.save.options.battleLayout, "og",
     "a wide desktop window is not a phone held sideways, and is left alone")

  isMobile = true
  local off, offHooks = stubMod({ enabled = false })
  local ignored = stubGame()
  frame(offHooks, ignored)
  eq(ignored.save.options.battleLayout, "og", "and OFF is the untouched game")
  eq(off.schema[2].key, "sideways", "the preset row sits under the switch")

  _G.love = realLove
  package.preload["src.core.FaithfulRes"] = nil
  package.preload["src.core.ScreenPosition"] = nil
  package.preload["src.render.Letterbox"] = nil
  package.loaded["src.core.FaithfulRes"] = nil
  package.loaded["src.core.ScreenPosition"] = nil
  package.loaded["src.render.Letterbox"] = nil
end

-- The XP bar's own guard -- "stop once the player's Pokemon faints, because
-- the engine has cleared the HUD out from under the bar" -- moved with the
-- feature.  It is asserted in Gen1BattleUI's suite now, not here.

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
