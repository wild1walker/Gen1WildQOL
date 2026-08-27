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

-- ------- the two zone lists
--
-- This is the bug 1.7.0 shipped.  render.zones hands a mod the UI pass -- the
-- menus and text boxes -- while the map is drawn through a different list the
-- overworld is asked for a few lines later.  Tinting the hook's list turned
-- the START menu purple and left the grass alone.  So what is asserted here is
-- both halves: the UI list comes back untouched, and the map's does not.

local function worldZones()
  return { { x = 0, y = 0, w = 320, h = 288,
             colors = { { 255, 255, 255 }, { 170, 170, 170 },
                        { 85, 85, 85 }, { 0, 0, 0 } } } }
end

local function drawFrame(mod, game)
  -- the order the engine runs them in: the hook, then the map's own list
  mod.wrapped["render.zones"](same, game, ZONES)
  local world = game.overworld
  if type(world.sgbWorldZones) ~= "function" then return nil end
  return world:sgbWorldZones()
end

io.write("the map is tinted and the menu is not\n")
local game = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
game.overworld.sgbWorldZones = worldZones
local ui = m.wrapped["render.zones"](same, game, ZONES)
eq(ui, ZONES, "the UI pass is handed back untouched -- the menu keeps its colour")
local map = game.overworld:sgbWorldZones()
ok(map[1].colors[2][1] > map[1].colors[2][2], "and the map wears the purple")
eq(map[1].w, 320, "in world-canvas pixels, with the rect untouched")

io.write("a healthy party leaves both alone\n")
local clean = stubGame({ { hp = 40, stats = { hp = 40 } } })
clean.overworld.sgbWorldZones = worldZones
local cleanMap = drawFrame(m, clean)
eq(cleanMap[1].colors[2][1], 170, "the map is the palette it was")

io.write("wrapping happens once\n")
local twice = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
twice.overworld.sgbWorldZones = worldZones
drawFrame(m, twice)
local first = twice.overworld:sgbWorldZones()[1].colors[2][1]
drawFrame(m, twice)
local second = twice.overworld:sgbWorldZones()[1].colors[2][1]
eq(second, first, "a second frame does not tint an already-tinted list again")

io.write("the tick is swallowed and replaced\n")
local ticking = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } }, 12)
ticking.overworld.sgbWorldZones = worldZones
local ticked = drawFrame(m, ticking)
eq(ticking.overworld.poisonFlash, 0,
  "the engine's flash counter is taken to zero, so no black frame is drawn")
local resting = drawFrame(m, game)
ok(C.luma(ticked[1].colors[2]) ~= C.luma(resting[1].colors[2]),
  "and the tick's frame is deeper than the resting tint")

io.write("REPLACE FLASH off hands the flash back\n")
m.stored.replace_flash = false
local kept = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } }, 12)
kept.overworld.sgbWorldZones = worldZones
drawFrame(m, kept)
eq(kept.overworld.poisonFlash, 12, "the counter is left for the engine to draw")
m.stored.replace_flash = nil

io.write("the switches switch\n")
local function mapUnder(overrides)
  for k, v in pairs(overrides) do m.stored[k] = v end
  local g = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
  g.overworld.sgbWorldZones = worldZones
  local zones = drawFrame(m, g)
  for k in pairs(overrides) do m.stored[k] = nil end
  return zones[1].colors[2][1]
end
eq(mapUnder({ enabled = false }), 170, "the master turns the whole thing off")
eq(mapUnder({ world = false }), 170, "TINT THE WORLD turns off the world half")
eq(mapUnder({ psn = false }), 170, "and POISON off means no tint")

io.write("the world reacts to what takes HP\n")
local function mapFor(status, scope)
  if scope then m.stored.world_scope = scope end
  local g = stubGame({ { hp = 20, stats = { hp = 40 }, status = status } })
  g.overworld.sgbWorldZones = worldZones
  local zones = drawFrame(m, g)
  m.stored.world_scope = nil
  return zones[1].colors[2][1]
end
ok(mapFor("BRN") ~= 170,
  "burn tints: it is one of the three HandlePoisonBurnLeechSeed takes HP for")
eq(mapFor("PAR"), 170, "paralysis takes no HP, so DAMAGING leaves it out")
eq(mapFor("SLP"), 170, "and so does sleep")
eq(mapFor("BRN", "poison"), 170, "POISON narrows it back to the two poisons")
ok(mapFor("PAR", "any") ~= 170, "and ANY STATUS lets paralysis through")

io.write("a battle is not the overworld\n")
local battle = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
battle.overworld.sgbWorldZones = worldZones
battle.stack.states = { {} }   -- the visible base is something else
local battleMap = drawFrame(m, battle)
eq(battleMap[1].colors[2][1], 170,
  "the tint stays out of battles, where the HUD already says it")

io.write("a trueColor zone is left alone\n")
local mixed = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
mixed.overworld.sgbWorldZones = function()
  return { { x = 0, y = 0, w = 8, h = 8, colors = false },
           { x = 0, y = 0, w = 320, h = 288,
             colors = { { 255, 255, 255 }, { 170, 170, 170 },
                        { 85, 85, 85 }, { 0, 0, 0 } } } }
end
local mixedOut = drawFrame(m, mixed)
eq(mixedOut[1].colors, false, "the opt-out survives the pass")
ok(mixedOut[2].colors[2][1] > mixedOut[2].colors[2][2],
  "while the zone beside it tints")

io.write("a map with no zones of its own is left as it is\n")
local bare = stubGame({ { hp = 20, stats = { hp = 40 }, status = "PSN" } })
bare.overworld.sgbWorldZones = function() return nil end
eq(drawFrame(m, bare), nil,
  "nil in, nil out -- nothing is invented in world-canvas space")

-- ------- the stats page
--
-- The one screen where a POKeMON's full picture is shown with its status
-- printed beside it.  SummaryMenu answers with a full-screen HP-bar palette
-- plus one zone over the picture; only the picture should wear the condition,
-- or the whole page turns purple and the bar stops meaning what it means.

io.write("the stats page tints the picture and not the page\n")
local registered
local function stubModWithScreens()
  local m = stubMod()
  m.content = { screens = { register = function(_, id, record)
    registered = { id = id, record = record }
  end } }
  return m
end
do
  local chunk = assert(loadfile("modules/StatusColours/main.lua"))
  local m2 = stubModWithScreens()
  chunk()(m2)
  ok(registered ~= nil, "a screen is registered")
  eq(registered and registered.id, "SummaryMenu", "under the engine's own id")

  local WHOLE = { x = 0, y = 0, w = 160, h = 144,
                  colors = { { 255, 255, 255 }, { 170, 170, 170 },
                             { 85, 85, 85 }, { 0, 0, 0 } } }
  local PIC = { x = 8, y = 0, w = 56, h = 56,
                colors = { { 255, 255, 255 }, { 170, 170, 170 },
                           { 85, 85, 85 }, { 0, 0, 0 } } }
  local Builtin = {}
  Builtin.__index = Builtin
  function Builtin.new(_, mon)
    local self = setmetatable({ mon = mon }, Builtin)
    self.sgbPalettes = function() return { WHOLE, PIC } end
    return self
  end

  local saved = package.loaded["src.ui.SummaryMenu"]
  package.loaded["src.ui.SummaryMenu"] = Builtin
  local poisoned = registered.record.new({},
    { hp = 20, stats = { hp = 40 }, status = "PSN" })
  local zones = poisoned:sgbPalettes({})
  package.loaded["src.ui.SummaryMenu"] = saved

  eq(zones[1].colors, WHOLE.colors, "the full-screen bar palette is left alone")
  ok(zones[2].colors ~= PIC.colors, "the picture's zone is replaced")
  ok(zones[2].colors[2][1] > zones[2].colors[2][2], "and wears the purple")
  eq(zones[2].x, PIC.x, "the rect is untouched")
  eq(PIC.colors[2][1], 170, "and the engine's table was not written through")

  package.loaded["src.ui.SummaryMenu"] = Builtin
  local healthy = registered.record.new({}, { hp = 40, stats = { hp = 40 } })
  local plain = healthy:sgbPalettes({})
  package.loaded["src.ui.SummaryMenu"] = saved
  eq(plain[2].colors, PIC.colors, "a healthy POKeMON's picture is untinted")
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
