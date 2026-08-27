-- STATUS COLOURS: the arithmetic, held still.
--
-- The subject is modules/StatusColours/colours.lua -- the built copy, because
-- that is the one the game loads; tools/build.py --check is what guarantees it
-- matches maintained/.
--
-- What is worth testing here is not "does a purple rectangle appear".  It is
-- the three claims the feature rests on: that a tint keeps the four shades
-- distinguishable (or the screen stops being readable), that the party's worst
-- condition is the one that wins (or the colour says the wrong thing), and
-- that the damage tick deepens the tint without ever reaching the blackout it
-- replaced.
--
-- Run:  luajit tests/statuscolours_test.lua

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
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "  (got ", tostring(actual),
             ", want ", tostring(expected), ")\n")
  end
end

local C = assert(dofile("modules/StatusColours/colours.lua"),
  "colours.lua did not load")

local GRAYS = { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 } }

-- ------- reading a mon

io.write("what a mon is carrying\n")
eq(C.keyFor({ hp = 20, maxHP = 40, status = "PSN" }), "psn", "poison is poison")
eq(C.keyFor({ hp = 20, maxHP = 40, status = "BRN" }), "brn", "burn is burn")
eq(C.keyFor({ hp = 20, maxHP = 40 }), nil, "a healthy mon carries nothing")
eq(C.keyFor({ hp = 0, maxHP = 40, status = "PSN" }), "fainted",
  "a fainted mon is fainted, whatever its status byte still says")
eq(C.keyFor({ hp = 20, maxHP = 40, status = "PSN", toxicCounter = 3 }), "tox",
  "the Toxic counter makes PSN bad poison")
eq(C.keyFor({ hp = 20, maxHP = 40, status = "PSN", toxicCounter = 0 }), "psn",
  "a zero counter does not")
eq(C.keyFor({ hp = 5, stats = { hp = 40 } }, 0.2), "lowhp",
  "an unstatused mon at a fifth of its HP is low -- stats.hp, the real field")
eq(C.keyFor({ hp = 5, stats = { hp = 40 } }, nil), nil,
  "and is not, when the caller passes no threshold")
eq(C.keyFor({ hp = 5, stats = { hp = 40 }, status = "PAR" }, 0.2), "par",
  "a status outranks low HP on the same mon")
eq(C.keyFor({ hp = 5, maxHP = 40 }, 0.2), "lowhp",
  "maxHP still answers, for a battler or a serialized mon that carries it")
eq(C.keyFor({ hp = 5 }, 0.2), nil,
  "and a mon with no max at all is not guessed at")
eq(C.keyFor(nil), nil, "an empty slot carries nothing")
eq(C.keyFor({ hp = 20, status = "WAT" }), nil, "an unknown status is ignored")

-- ------- the party's worst

io.write("the one the party wears\n")
local party = {
  { hp = 20, maxHP = 40, status = "PAR" },
  { hp = 18, maxHP = 40, status = "PSN" },
  { hp = 30, maxHP = 40 },
}
eq(C.worstIn(party, 0.2), "psn", "poison outranks paralysis")
party[3] = { hp = 0, maxHP = 40 }
eq(C.worstIn(party, 0.2), "fainted", "and fainted outranks poison")
eq(C.worstIn(party, 0.2, { psn = true, tox = true }), "psn",
  "the allowed set is a filter, not a fallback")
eq(C.worstIn(party, 0.2, { brn = true }), nil,
  "and nothing allowed means no colour at all")
eq(C.worstIn({}, 0.2), nil, "an empty party wears nothing")
eq(C.worstIn(nil, 0.2), nil, "and so does no party")
eq(C.worstIn({ { hp = 20, maxHP = 40, status = "PSN", toxicCounter = 1 },
               { hp = 20, maxHP = 40, status = "PSN" } }, 0.2), "tox",
  "bad poison outranks ordinary poison")

-- ------- the tint keeps the picture readable

io.write("a tinted palette is still a palette\n")
local tinted = C.apply(GRAYS, "psn", 0.38)
eq(#tinted, 4, "four shades in, four shades out")
local lumas = {}
for i, c in ipairs(tinted) do lumas[i] = C.luma(c) end
ok(lumas[1] > lumas[2] and lumas[2] > lumas[3] and lumas[3] > lumas[4],
  "and they stay in order lightest to darkest, so text stays readable")
ok(lumas[1] - lumas[4] > 0.6, "with most of the original range intact")
ok(tinted[2][1] > tinted[2][2] and tinted[2][3] > tinted[2][2],
  "a mid shade has taken the purple: red and blue above green")
ok(tinted[4][1] < 40 and tinted[4][2] < 40 and tinted[4][3] < 40,
  "the ink stays ink rather than turning purple")
ok(GRAYS[2][1] == 170, "and the palette handed in was not written through")

io.write("fainted drains instead of tinting\n")
local grey = C.apply({ { 240, 80, 80 } }, "fainted", 1.0)
eq(grey[1][1], grey[1][2], "red and green meet")
eq(grey[1][2], grey[1][3], "and green and blue")

io.write("nothing happens when nothing should\n")
eq(C.apply(GRAYS, "psn", 0), GRAYS, "zero amount returns the palette itself")
eq(C.apply(GRAYS, "nonsense", 0.5), GRAYS, "an unknown key changes nothing")

-- ------- the tick

io.write("the damage tick deepens, and never blacks out\n")
local rest = C.amountFor("normal", 0, 12)
local peak = C.amountFor("normal", 12, 12)
local mid = C.amountFor("normal", 6, 12)
ok(peak > mid and mid > rest, "the deepening tracks the engine's counter down")
ok(peak < 1, "and never reaches opaque -- that would be the blackout again")
eq(C.amountFor("normal", nil, 12), rest, "no tick is the resting depth")
ok(C.amountFor("subtle", 0, 12) < rest, "SUBTLE is shallower")
ok(C.amountFor("strong", 0, 12) > rest, "and STRONG is deeper")
eq(C.amountFor("nonsense", 0, 12), rest, "an unknown depth falls back to NORMAL")
local peaked = C.apply(GRAYS, "psn", peak)
local peakLumas = {}
for i, c in ipairs(peaked) do peakLumas[i] = C.luma(c) end
ok(peakLumas[1] > peakLumas[4], "even at the peak the screen still has range")

-- ------- every state is complete

io.write("every state is fully described\n")
for _, entry in ipairs(C.STATUSES) do
  ok(type(entry.label) == "string" and entry.label ~= "",
    entry.key .. " has a label")
  ok(type(entry.rank) == "number", entry.key .. " has a rank")
  ok(entry.tint ~= nil or entry.desaturate,
    entry.key .. " either has a tint or drains")
  if entry.tint then
    eq(#entry.tint, 3, entry.key .. "'s tint is an RGB triple")
  end
end
local seenRank = {}
for _, entry in ipairs(C.STATUSES) do
  ok(not seenRank[entry.rank], "rank " .. entry.rank .. " is used once")
  seenRank[entry.rank] = true
end
for status, key in pairs(C.FROM_STATUS) do
  ok(C.entry(key) ~= nil, status .. " maps to a state that exists")
end

-- ------- the feature itself, against the engine's seams
--
-- colours.lua is the arithmetic; this is the part that talks to the game.  A
-- stub mod records what the feature asked the engine for, and a stub game
-- carries the two things it reads: the party, and the overworld's poisonFlash
-- counter.  What is being asserted is the behaviour the feature exists for --
-- that the tick's black flash is swallowed and replaced, that the tint appears
-- only where it should, and that switching it off really does hand the vanilla
-- flash back.

local function stubMod()
  local self = { id = "gen1_wild_qol", exports = {}, stored = {}, hooks = {} }
  self.wrapped = {}
  self.options = {
    define = function(_, schema) self.defined = schema end,
    get = function(_, key) return self.stored[key] end,
  }
  self.log = setmetatable({}, { __index = function() return function() end end })
  self.hooks = { wrap = function(_, name, fn) self.wrapped[name] = fn end }
  function self:read(path)
    local fh = io.open("modules/StatusColours/" .. path, "r")
    if not fh then return nil, "missing" end
    local body = fh:read("*a"); fh:close(); return body
  end
  return self
end

local function install()
  local chunk = assert(loadfile("modules/StatusColours/main.lua"))
  local factory = chunk()
  local m = stubMod()
  factory(m)
  return m
end

local function stubGame(party, flash)
  local overworld = { poisonFlash = flash or 0 }
  local stack = { states = { overworld }, visibleBase = function() return 1 end }
  return { save = { party = party }, overworld = overworld, stack = stack }
end

local ZONES = { { x = 0, y = 0, w = 160, h = 144,
                  colors = { { 255, 255, 255 }, { 170, 170, 170 },
                             { 85, 85, 85 }, { 0, 0, 0 } } } }
local function same(_, z) return z end

io.write("the feature wires itself up\n")
local m = install()
ok(m.defined ~= nil, "it defines an option schema")
ok(#m.defined == 13, "with a row for every switch (" .. tostring(#m.defined) .. ")")
eq(m.defined[1].key, "enabled", "and the master first, which features.lua donates")
eq(m.defined[3].default, "damaging",
  "WORLD REACTS TO defaults to the statuses that take HP")
ok(m.wrapped["render.zones"] ~= nil, "it wraps render.zones")
ok(type(m.exports.statusColours) == "table", "and publishes what it is wearing")

-- ------- how the colour reaches the screen
--
-- Two mechanisms were tried and only the second works for everyone.  Palette
-- zones -- render.zones and sgbWorldZones -- are the SGB shade-remap path, and
-- a map drawn from a full-colour GBC atlas has no four-colour palette to move:
-- sgbWorldZones returns an empty list outright under RED++.  So the tint is
-- drawn instead, the way the flash it replaces is drawn, on the end of the
-- overworld's own draw where it lands over the map and under every state
-- stacked above it.
--
-- The graphics table is injected, so what would have been painted can be
-- asserted without a window.

local function stubGraphics()
  local g = { calls = {}, colour = nil, blend = nil, depth = 0 }
  function g.push() g.depth = g.depth + 1 end
  function g.pop() g.depth = g.depth - 1 end
  function g.setBlendMode(mode, alpha) g.blend = { mode, alpha } end
  function g.setColor(r, gr, b, a) g.colour = { r, gr, b, a } end
  function g.rectangle(mode, x, y, w, h)
    g.calls[#g.calls + 1] = { mode = mode, x = x, y = y, w = w, h = h,
                              colour = g.colour, blend = g.blend }
  end
  return g
end

local function frame(mod, game)
  -- the order the engine runs them in: the zones hook, then the world's draw
  mod.wrapped["render.zones"](same, game, ZONES)
  local world = game.overworld
  if type(world.draw) == "function" then world:draw() end
  return mod.__graphics.calls
end

local function withWorld(party, flash)
  local game = stubGame(party, flash)
  game.overworld.draw = function() end
  return game
end

io.write("the tint is painted over the world\n")
m.__graphics = stubGraphics()
local poisoned = withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
local ui = m.wrapped["render.zones"](same, poisoned, ZONES)
eq(ui, ZONES, "the zone list is handed back untouched -- palettes are not the seam")
poisoned.overworld:draw()
local calls = m.__graphics.calls
eq(#calls, 1, "one rectangle is painted")
eq(calls[1].w, 160, "the width of the world")
eq(calls[1].h, 144, "and its height")
eq(calls[1].blend[1], "alpha",
  "alpha-blended, the way the flash it replaces is -- a multiply showed nothing here")
ok(calls[1].colour[1] > calls[1].colour[2],
  "and the colour pulls red above green -- the purple")
ok(calls[1].colour[3] > calls[1].colour[2], "with blue above it too")
ok(calls[1].colour[4] > 0 and calls[1].colour[4] < 0.5,
  "at an alpha under the 0.45 the vanilla flash uses, so it never blacks out")
eq(m.__graphics.depth, 0, "push and pop are balanced, so no state leaks out")

io.write("a healthy party paints nothing\n")
m.__graphics = stubGraphics()
eq(#frame(m, withWorld({ { hp = 40, stats = { hp = 40 } } })), 0,
  "no rectangle at all")

io.write("wrapping happens once\n")
m.__graphics = stubGraphics()
local twice = withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
frame(m, twice)
frame(m, twice)
eq(#m.__graphics.calls, 2, "two frames paint two rectangles, not four")

io.write("the tick is swallowed and replaced\n")
m.__graphics = stubGraphics()
local ticking = withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } }, 12)
frame(m, ticking)
eq(ticking.overworld.poisonFlash, 0,
  "the engine's flash counter is taken to zero, so no black frame is drawn")
local deep = m.__graphics.calls[1].colour[4]
m.__graphics = stubGraphics()
frame(m, withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } }))
local rest = m.__graphics.calls[1].colour[4]
ok(deep > rest, "and the tick's frame is deeper than the resting tint")

io.write("REPLACE FLASH off hands the flash back\n")
m.stored.replace_flash = false
m.__graphics = stubGraphics()
local kept = withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } }, 12)
frame(m, kept)
eq(kept.overworld.poisonFlash, 12, "the counter is left for the engine to draw")
m.stored.replace_flash = nil

io.write("the switches switch\n")
local function paintedUnder(overrides, status)
  for k, v in pairs(overrides) do m.stored[k] = v end
  m.__graphics = stubGraphics()
  local n = #frame(m, withWorld({ { hp = 20, stats = { hp = 40 },
                                    status = status or "PSN" } }))
  for k in pairs(overrides) do m.stored[k] = nil end
  return n
end
eq(paintedUnder({ enabled = false }), 0, "the master turns the whole thing off")
eq(paintedUnder({ world = false }), 0, "TINT THE WORLD turns off the world half")
eq(paintedUnder({ psn = false }), 0, "and POISON off means no tint")

io.write("the world reacts to what takes HP\n")
eq(paintedUnder({}, "BRN"), 1,
  "burn paints: it is one of the three HandlePoisonBurnLeechSeed takes HP for")
eq(paintedUnder({}, "PAR"), 0, "paralysis takes no HP, so DAMAGING leaves it out")
eq(paintedUnder({}, "SLP"), 0, "and so does sleep")
eq(paintedUnder({ world_scope = "poison" }, "BRN"), 0,
  "POISON narrows it back to the two poisons")
eq(paintedUnder({ world_scope = "any" }, "PAR"), 1,
  "and ANY STATUS lets paralysis through")

io.write("a battle is not the overworld\n")
m.__graphics = stubGraphics()
local battle = withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
battle.stack.states = { {} }   -- the visible base is something else
eq(#frame(m, battle), 0,
  "nothing is wrapped, so the map behind a battle is left alone")

io.write("a host with no graphics stands down quietly\n")
m.__graphics = false
local headless = withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
m.wrapped["render.zones"](same, headless, ZONES)
ok(pcall(function() headless.overworld:draw() end),
  "the draw still returns rather than throwing")
m.__graphics = stubGraphics()

io.write("a graphics table that throws is stood down from, once\n")
local angry = stubGraphics()
angry.rectangle = function() error("no context") end
m.__graphics = angry
local hostile = withWorld({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
m.wrapped["render.zones"](same, hostile, ZONES)
ok(pcall(function() hostile.overworld:draw() end),
  "the first frame survives the failure")
ok(pcall(function() hostile.overworld:draw() end),
  "and so does the next, with the wrapper removed rather than retried")
m.__graphics = stubGraphics()

-- ------- the stats page
--
-- The one screen where a POKeMON's full picture is shown with its status
-- printed beside it.  SummaryMenu answers with a full-screen HP-bar palette
-- plus one zone over the picture; only the picture should wear the condition,
-- or the whole page turns purple and the bar stops meaning what it means.

io.write("the condition as a draw colour\n")
do
  local api = m.exports.statusColours
  eq(api.drawColour({ hp = 40, stats = { hp = 40 } }), nil,
    "a healthy POKeMON is drawn as it is")
  local psn = api.drawColour({ hp = 20, stats = { hp = 40 }, status = "PSN" })
  ok(psn ~= nil, "a poisoned one gets a colour")
  ok(psn[1] > psn[2] and psn[3] > psn[2],
    "with red and blue above green -- the purple")
  ok(psn[1] <= 1 and psn[2] > 0,
    "inside the multiply range, so the art keeps its own light and dark")
  local out = api.drawColour({ hp = 0, stats = { hp = 40 } })
  eq(out[1], out[2], "a fainted one drains instead: red meets green")
  eq(out[2], out[3], "and green meets blue")
  ok(out[1] < 1, "and it is pulled down from white")
  m.stored.psn = false
  eq(api.drawColour({ hp = 20, stats = { hp = 40 }, status = "PSN" }), nil,
    "a row switched off means no colour, so the screens draw it as it is")
  m.stored.psn = nil
  m.stored.enabled = false
  eq(api.drawColour({ hp = 20, stats = { hp = 40 }, status = "PSN" }), nil,
    "and the master turns it off everywhere at once")
  m.stored.enabled = nil
end

io.write("the stats page shifts the picture's palette, and paints nothing\n")
local registered
local function stubModWithScreens()
  local mm = stubMod()
  mm.content = { screens = { register = function(_, id, record)
    registered = { id = id, record = record }
  end } }
  return mm
end
do
  local chunk = assert(loadfile("modules/StatusColours/main.lua"))
  local m2 = stubModWithScreens()
  chunk()(m2)
  ok(registered ~= nil, "a screen is registered")
  eq(registered and registered.id, "SummaryMenu", "under the engine's own id")

  -- SummaryMenu answers with an HP-bar palette over the whole screen plus one
  -- zone over the picture.  Only the second is the picture's.
  local WHOLE = { x = 0, y = 0, w = 160, h = 144,
                  colors = { { 255, 255, 255 }, { 170, 170, 170 },
                             { 85, 85, 85 }, { 0, 0, 0 } } }
  local PIC = { x = 8, y = 0, w = 56, h = 56,
                colors = { { 255, 255, 255 }, { 170, 170, 170 },
                           { 85, 85, 85 }, { 0, 0, 0 } } }
  local Builtin = {}
  Builtin.__index = Builtin
  function Builtin.new(_, mon)
    local self = setmetatable({ mon = mon, game = {} }, Builtin)
    self.sgbPalettes = function() return { WHOLE, PIC } end
    return self
  end

  local painted = stubGraphics()
  m2.__graphics = painted
  local saved = package.loaded["src.ui.SummaryMenu"]
  package.loaded["src.ui.SummaryMenu"] = Builtin
  local poisoned = registered.record.new({},
    { hp = 20, stats = { hp = 40 }, status = "PSN" })
  local zones = poisoned:sgbPalettes({})
  package.loaded["src.ui.SummaryMenu"] = saved

  eq(#painted.calls, 0,
    "nothing is painted over the picture -- a rect there turns its white "
    .. "background into a lavender block")
  eq(zones[1].colors, WHOLE.colors, "the full-screen bar palette is left alone")
  ok(zones[2].colors ~= PIC.colors, "the picture's palette is replaced")
  ok(zones[2].colors[2][1] > zones[2].colors[2][2], "and wears the purple")
  ok(zones[2].colors[1][1] > 200,
    "while its lightest shade stays light, so the well stays a white well")
  eq(zones[2].x, PIC.x, "the rect is untouched")
  eq(PIC.colors[2][1], 170, "and the engine's table was not written through")

  package.loaded["src.ui.SummaryMenu"] = Builtin
  local healthy = registered.record.new({}, { hp = 40, stats = { hp = 40 } })
  local plain = healthy:sgbPalettes({})
  package.loaded["src.ui.SummaryMenu"] = saved
  eq(plain[2].colors, PIC.colors, "a healthy POKeMON's picture is untouched")
end

-- ------- through the whole bundle
--
-- Everything above drives the feature file directly.  That is not enough, and
-- twice now it has not been: a feature can be correct on its own and still
-- reach the player doing nothing, because what installs it is features.lua and
-- runtime/bundle.lua, not this test.  So this one starts where the game does
-- -- the real registry, the real runtime -- and asserts that a poisoned party
-- ends with a rectangle painted over the world.

do
  io.write("the bundle installs it, and a poisoned party paints the world\n")

  local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local body = fh:read("*a"); fh:close(); return body
  end
  local function load_(path, req)
    local src = readFile(path)
    if not src then return nil end
    local chunk = load(src, "@" .. path)
    if not chunk then return nil end
    return chunk(req)
  end

  local Bundle = load_("runtime/bundle.lua",
    function(name) return load_("runtime/" .. name .. ".lua") end)
  ok(Bundle ~= nil, "the runtime loads")

  local bundleMod = { id = "gen1_wild_qol", path = ".", version = "0.0.0",
                      exports = {}, stored = {}, hooked = {}, screens = {} }
  function bundleMod:read(path) return readFile(path) end
  bundleMod.options = {
    define = function(_, schema) bundleMod.defined = schema end,
    get = function(_, key) return bundleMod.stored[key] end,
    set = function(_, key, value) bundleMod.stored[key] = value end,
  }
  bundleMod.log = setmetatable({}, { __index = function() return function() end end })
  bundleMod.hooks = { wrap = function(_, name, fn) bundleMod.hooked[name] = fn end }
  bundleMod.events = { on = function() end, once = function() end }
  bundleMod.content = { screens = { register = function(_, id, record)
    bundleMod.screens[id] = record
  end } }
  bundleMod.ui = { insertBefore = function(t) return t end, push = function() end }
  bundleMod.save = { get = function() end, set = function() end }
  bundleMod.cache, bundleMod.storage = {}, {}
  bundleMod.find = function() return nil end
  bundleMod.assets = { path = function(_, path) return path end }

  local registry = load_("features.lua")
  ok(registry ~= nil and registry.features ~= nil, "features.lua loads")
  Bundle.install(bundleMod, registry.spec, registry.features)

  ok(bundleMod.hooked["render.zones"] ~= nil,
    "the bundle's install reaches the feature and it takes its hook")
  ok(type(bundleMod.exports.statusColours) == "table",
    "and publishes its table on the bundle's own exports, where mod.find looks")

  local painted = stubGraphics()
  bundleMod.__graphics = painted
  local world = { poisonFlash = 0, isOpaque = true, draw = function() end }
  local stack = { states = { world } }
  function stack:visibleBase() return 1 end
  local game = { save = { party = { { hp = 3, stats = { hp = 45 },
                                      status = "PSN" } } },
                 overworld = world, stack = stack }

  bundleMod.hooked["render.zones"](function(_, z) return z end, game, nil)
  world:draw()
  eq(#painted.calls, 1, "a poisoned party paints one rectangle over the world")
  eq(painted.calls[1].w, 160, "at the width of the world")
  ok(painted.calls[1].colour[1] > painted.calls[1].colour[2],
    "in the purple")
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
