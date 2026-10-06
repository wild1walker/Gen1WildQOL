-- The quality-of-life half on FireRed, LeafGreen and Emerald.
--
-- Five features run there (features.lua `gen3`): SPRINT, EXP SHARE, REUSABLE
-- TMS and AUTO SAVE through arms of their own in modules/Gen3QOL, and SOUND
-- through its ordinary entry, whose hook FireRed calls with the same ctx.
-- Each arm is driven here against stand-ins shaped like the Gen 3 engine
-- modules it wraps -- src/core/game3/player.lua canDash, item_use.lua useTm,
-- battle/experience.lua awardFoe, battle/exp_seq.lua begin, Game3:saveGame
-- and quickSaveAllowed -- and then the whole bundle is installed on a Gen 3
-- boot from the real features.lua, to show those five are what install and
-- nothing written for Red is so much as read.
--
-- Run:  luajit tests/gen3qol_test.lua

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

local function readFile(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local body = handle:read("*a")
  handle:close()
  return body
end

local function load_(path, ...)
  local source = assert(readFile(path), path .. " is missing")
  return assert(load(source, "@" .. path))(...)
end

-- A plain mod for one arm: options with defaults from what it defines,
-- hooks and events recorded.
local function armMod()
  local self = { stored = {}, schema = {}, hooks = {}, on = {}, logged = {},
                 exports = {} }
  self.options = {
    define = function(_, schema)
      for _, row in ipairs(schema) do self.schema[row.key] = row end
    end,
    get = function(_, key)
      local value = self.stored[key]
      if value == nil and self.schema[key] then return self.schema[key].default end
      return value
    end,
    set = function(_, key, value) self.stored[key] = value end,
  }
  self.hooks = {}
  self.wrapped = {}
  self.hooks.wrap = function(_, name, fn) self.wrapped[name] = fn end
  self.events = { on = function(_, name, fn)
    self.on[name] = self.on[name] or {}
    table.insert(self.on[name], fn)
  end }
  -- The engine's mod log has info, warn and error and nothing else
  -- (src/mods/Loader.lua); through the bundle's facade any other level is nil.
  self.log = {}
  for _, level in ipairs({ "info", "warn", "error" }) do
    self.log[level] = function(_, fmt, ...)
      self.logged[#self.logged + 1] = level .. ": "
        .. (select("#", ...) > 0 and fmt:format(...) or fmt)
    end
  end
  function self.emit(name, payload)
    for _, fn in ipairs(self.on[name] or {}) do fn(payload) end
  end
  return self
end

local function install(path, mod)
  local entry = load_(path)
  entry(mod)
  return mod
end

-- ---------------------------------------------------------------- SPRINT

do
  io.write("SPRINT: the cart's two refusals, and only those\n")
  local shoes = false
  local flagsAsked = {}
  local Player = { cellX = 4, cellY = 7, currentElevation = 3 }
  local Collision = { _mapDef = { allowRunning = 1 }, tile = 0 }
  function Collision.behavior() return Collision.tile end
  local row = { id = "firered", field = {} }
  local TILE = { LONG_GRASS = 9, FORTREE_BRIDGE = 12 }
  -- The cart's own canDash: the shoes, then -- on Emerald -- the header and
  -- the tile (src/core/game3/player.lua Player.canDash, runningDisallowed).
  function Player.canDash()
    if not shoes then return false end
    local rules = row.field.running
    if not rules then return true end
    if Player.underwater then return false end
    if rules.mapHeader and Collision._mapDef.allowRunning == 0 then return false end
    for _, name in ipairs(rules.behaviors) do
      if Collision.tile == TILE[name] then return false end
    end
    for _, name in ipairs(rules.evenElevation) do
      if Collision.tile == TILE[name] and Player.currentElevation % 2 == 0 then
        return false
      end
    end
    return true
  end
  package.loaded["src.core.game3.player"] = Player
  package.loaded["src.core.game3.collision"] = Collision
  package.loaded["src.core.game3.scripting.space"] = {
    getStore = function() return {} end,
  }
  package.loaded["src.core.game3.profile"] = {
    forSession = function() return row end,
  }
  package.loaded["src.core.game3.scripting.flags"] = {
    IDS = { SYS_B_DASH = 0x82F },
    forVersion = function() return { IDS = { FLAG_SYS_B_DASH = 0x860 } } end,
    getFlag = function(_, _, id) flagsAsked[#flagsAsked + 1] = id; return shoes end,
  }
  package.loaded["src.core.game3.mb"] = {
    id = function(name) return TILE[name] or -1 end,
  }

  local mod = install("modules/Gen3QOL/sprint.lua", armMod())
  ok(Player.canDash ~= nil and mod.exports.canDash == Player.canDash,
     "canDash is wrapped")

  eq(Player.canDash(), true, "no shoes yet: B runs anyway, by default")
  mod.stored.early = false
  eq(Player.canDash(), false, "RUN BEFORE THE SHOES off: the cart's answer")
  shoes = true
  eq(Player.canDash(), true, "and with the shoes, the cart's own yes")
  shoes = false
  mod.stored.early = nil

  mod.stored.enabled = false
  eq(Player.canDash(), false, "SPRINT off is the untouched game")
  mod.stored.enabled = nil

  Player.underwater = true
  eq(Player.canDash(), false, "never underwater")
  Player.underwater = nil
  Player.biking = true
  eq(Player.canDash(), false, "nor on a bicycle, whose speed is its own")
  Player.biking = nil

  package.loaded["src.core.game3.scripting.space"] = { getStore = function() return nil end }
  eq(Player.canDash(), false, "nor before the field is scripted")
  package.loaded["src.core.game3.scripting.space"] = { getStore = function() return {} end }

  -- Emerald: a header rule and tile rules.
  row = { id = "emerald", field = { running = {
    flag = "FLAG_SYS_B_DASH", mapHeader = true,
    behaviors = { "LONG_GRASS" }, evenElevation = { "FORTREE_BRIDGE" },
  } } }
  shoes = true
  Collision._mapDef = { allowRunning = 0 }
  eq(Player.canDash(), true, "Emerald indoors: RUN INDOORS lets B run")
  local asked = flagsAsked[#flagsAsked]
  mod.stored.early = false
  Player.canDash()
  eq(flagsAsked[#flagsAsked], 0x860,
     "and the shoes are asked by Emerald's own flag name")
  mod.stored.early = nil
  mod.stored.indoors = false
  eq(Player.canDash(), false, "RUN INDOORS off: the header's no stands")
  mod.stored.indoors = nil
  Collision.tile = 9
  eq(Player.canDash(), false,
     "long grass is the cart's tile rule, and it stands whatever the rows say")
  Collision.tile = 12
  Player.currentElevation = 4
  eq(Player.canDash(), false, "so is the Fortree bridge on an even elevation")
  Player.currentElevation = 3
  eq(Player.canDash(), true, "and not on an odd one")
  Collision.tile = 0
  ok(asked ~= nil, "(the flag was consulted)")
end

-- --------------------------------------------------------- REUSABLE TMS

do
  io.write("REUSABLE TMS: spent and given back, on both of the cart's paths\n")
  local counts = { [289] = 1, [339] = 1 }  -- TM01, HM01
  local Bag = {}
  function Bag.get(_, id) return counts[id] or 0 end
  function Bag.add(_, id, n) counts[id] = (counts[id] or 0) + n; return true end
  function Bag.remove(_, id, n) counts[id] = (counts[id] or 0) - n end
  local LearnMove = {}
  local pendingDone
  function LearnMove.begin(opts) pendingDone = opts.onDone end
  local full = false
  local ItemUse = {}
  function ItemUse.useTm(_, bag, id, _)
    if not full then
      Bag.remove(bag, id, 1)
      return true, "tm", "learned"
    end
    package.loaded["src.core.game3.battle.learn_move"].begin({
      onDone = function(learned)
        if learned then Bag.remove(bag, id, 1) end
        return "done"
      end,
    })
    return false, "full", "needs to forget"
  end
  package.loaded["src.core.game3.item_use"] = ItemUse
  package.loaded["src.core.game3.bag"] = Bag
  package.loaded["src.core.game3.battle.learn_move"] = LearnMove
  package.loaded["src.core.game3.items_data"] = {
    isHm = function(id) return id == 339 end,
  }
  local realBegin = LearnMove.begin

  local mod = install("modules/Gen3QOL/reusable_tms.lua", armMod())
  local bag = {}

  local okUse, kind = ItemUse.useTm({}, bag, 289, 1)
  eq(counts[289], 1, "a free slot: TM01 is spent and given straight back")
  ok(okUse and kind == "tm", "and the cart's own answer comes through")

  full = true
  local _, fullKind = ItemUse.useTm({}, bag, 289, 1)
  eq(fullKind, "full", "a full moveset: the cart opens its forget prompt")
  eq(LearnMove.begin, realBegin, "and the prompt's begin is put back at once")
  eq(pendingDone(true), "done", "the prompt's own onDone still runs, result and all")
  eq(counts[289], 1, "and the TM it spent there is given back too")
  ItemUse.useTm({}, bag, 289, 1)
  pendingDone(false)
  eq(counts[289], 1, "a cancelled teach spends nothing and gets nothing")

  full = false
  local realUse = ItemUse.useTm
  -- The cart spends, then fails on its message: the TM still comes back,
  -- and the failure still reaches the caller.
  local wrapped = realUse
  local inner = function(_, b, id)
    Bag.remove(b, id, 1)
    error("no ROM text", 0)
  end
  -- Re-install over a cart whose useTm fails after the spend.
  ItemUse.useTm = inner
  install("modules/Gen3QOL/reusable_tms.lua", armMod())
  local okFail, why = pcall(ItemUse.useTm, {}, bag, 289, 1)
  eq(okFail, false, "a teach that fails still fails")
  eq(why, "no ROM text", "with the cart's own error")
  eq(counts[289], 1, "but the TM it spent first is given back")
  ItemUse.useTm = wrapped

  mod.stored.qol_reusable_tms = false
  ItemUse.useTm({}, bag, 289, 1)
  eq(counts[289], 0, "OFF: the TM is spent, as on the cart")
  mod.stored.qol_reusable_tms = nil
  counts[289] = 1
end

-- ----------------------------------------------------------- EXP SHARE

local function expHarness()
  local Pokemon = {}
  function Pokemon.isEgg(mon) return mon.egg == true end
  function Pokemon.gainEVs(mon) mon.evs = (mon.evs or 0) + 1 end
  function Pokemon.adjustFriendship(mon) mon.friend = (mon.friend or 0) + 1 end
  function Pokemon.currentMapSec() return 1 end
  function Pokemon.displayMonName(mon) return mon.name end
  Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL = 0

  local Experience = { MAX_LEVEL = 100 }
  function Experience.expYield() return 64 end
  function Experience.recipientOpts(_, mon)
    return { luckyEgg = mon.lucky == true, traded = mon.traded == true }
  end
  function Experience.apply(mon, amount)
    mon.exp = (mon.exp or 0) + amount
    local levels = {}
    if mon.levelsUp then levels = { (mon.level or 1) + 1 } end
    return { gained = amount, levels = levels,
             steps = mon.levelsUp and { { grewTo = levels[1] } } or {} }
  end
  -- The cart's own award: every fighter alive, full share each, plus any
  -- holder of the item -- enough of the real arithmetic for the bench to be
  -- measured against.
  function Experience.awardFoe(st, foe, opts)
    local out = {}
    for pi, mon in ipairs(st.playerParty) do
      if (foe.participants[pi] or mon.holdsShare) and mon.hp > 0 then
        out[#out + 1] = { mon = mon, partyIndex = pi, battler = {},
                          amount = 91, result = { gained = 91, steps = {} } }
      end
    end
    return out
  end

  local BattleText = {}
  function BattleText.get(id, fill)
    if id == "STRINGID_PKMNGAINEDEXP" then
      return ("%s gained%s\n%s EXP. Points!"):format(fill.buff1, fill.buff2, fill.buff3)
    end
    if id == "STRINGID_ABOOSTED" then return " a boosted" end
    return ""
  end
  -- The sequence as the cart builds it: one line per award that gained, then
  -- its level-ups.
  local ExpSeq = {}
  function ExpSeq.begin(awards)
    local steps = {}
    for _, entry in ipairs(awards) do
      local gained = entry.result.gained or 0
      if gained > 0 then
        steps[#steps + 1] = { kind = "msg", data = { text = BattleText.get(
          "STRINGID_PKMNGAINEDEXP", { buff1 = entry.mon.name,
            buff2 = BattleText.get(entry.boosted and "STRINGID_ABOOSTED" or "X"),
            buff3 = tostring(gained) }) } }
        for _, step in ipairs(entry.result.steps or {}) do
          steps[#steps + 1] = { kind = "level", data = { level = step.grewTo,
                                                         mon = entry.mon } }
        end
      end
    end
    ExpSeq._steps = steps
    return #steps > 0
  end

  package.loaded["src.core.game3.pokemon"] = Pokemon
  package.loaded["src.core.game3.battle.experience"] = Experience
  package.loaded["src.core.game3.battle.exp_seq"] = ExpSeq
  package.loaded["src.core.game3.battle.battle_text"] = BattleText
  return Experience, ExpSeq
end

local function battle(wild)
  local party = {
    { name = "LEAD", species = 25, level = 20, hp = 30 },
    { name = "LOW", species = 16, level = 10, hp = 20 },
    { name = "HIGH", species = 1, level = 30, hp = 40 },
    { name = "EGG", species = 412, level = 5, hp = 10, egg = true },
    { name = "DOWN", species = 19, level = 12, hp = 0 },
  }
  local st = { wild = wild, playerParty = party,
               player = { mon = party[1], partyIndex = 1 } }
  local foe = { species = 16, mon = { level = 10 }, participants = { [1] = true } }
  return st, foe, party
end

local function amounts(out)
  local byName = {}
  for _, entry in ipairs(out) do byName[entry.mon.name] = entry.amount end
  return byName
end

do
  io.write("EXP SHARE: the bench gains beside the fighters\n")
  local Experience, ExpSeq = expHarness()
  local mod = install("modules/Gen3QOL/expshare.lua", armMod())
  eq(mod.schema.mode.default, "gen5", "GEN 5+ ships on, as on Red and Gold")

  -- 64 * 10 / 7 = 91 for the one fighter; the bench gets half: 45.
  local st, foe = battle(true)
  local got = amounts(Experience.awardFoe(st, foe, {}))
  eq(got.LEAD, 91, "the fighter is paid exactly as the cart paid it")
  eq(got.LOW, 45, "GEN 5+: a bench Pokemon gains half a fighter's share")
  eq(got.HIGH, 45, "every bench Pokemon does")
  eq(got.EGG, nil, "an egg gains nothing")
  eq(got.DOWN, nil, "nor does a fainted Pokemon")

  st, foe = battle(false)
  got = amounts(Experience.awardFoe(st, foe, { trainer = true }))
  eq(got.LOW, 67, "a trainer battle boosts the bench as it boosts a fighter")

  st, foe = battle(true)
  st.playerParty[2].lucky = true
  got = amounts(Experience.awardFoe(st, foe, {}))
  eq(got.LOW, 67, "and so does a Lucky Egg")
  ok(st.playerParty[2].evs == 1, "the bench gains effort values, as a holder would")

  st, foe = battle(true)
  st.playerParty[3].holdsShare = true
  got = amounts(Experience.awardFoe(st, foe, {}))
  eq(got.HIGH, 91, "a holder of the cart's own Exp. Share is left as the cart paid it")

  st, foe = battle(true)
  foe.participants[2] = true
  got = amounts(Experience.awardFoe(st, foe, {}))
  eq(got.HIGH, 22,
     "two fighters split 91 at 45 each, and the bench gets half of one: 22")
  eq(got.LOW, 91, "a second fighter is a fighter, paid by the cart")

  mod.stored.mode = "balanced"
  st, foe = battle(true)
  got = amounts(Experience.awardFoe(st, foe, {}))
  eq(got.LOW, 45, "BALANCED: below the fighter's level, the bench gains")
  eq(got.HIGH, nil, "at or above it, it does not")

  mod.stored.mode = "average"
  st, foe = battle(true)
  got = amounts(Experience.awardFoe(st, foe, {}))
  -- living, hatched: 20, 10, 30 -> 20
  eq(got.LOW, 45, "AVERAGE: below the party's average level, the bench gains")
  eq(got.HIGH, nil, "above it, it does not")

  mod.stored.mode = "custom"
  mod.stored.percent = 100
  st, foe = battle(true)
  got = amounts(Experience.awardFoe(st, foe, {}))
  eq(got.LOW, 91, "CUSTOM 100%: the bench gains a whole fighter's share")

  mod.stored.mode = "off"
  st, foe = battle(true)
  got = amounts(Experience.awardFoe(st, foe, {}))
  eq(got.LOW, nil, "OFF: the cart's award, untouched")
  mod.stored.mode, mod.stored.percent = nil, nil

  io.write("EXP SHARE: one line for the bench\n")
  st, foe = battle(true)
  st.playerParty[2].levelsUp = true
  local awards = Experience.awardFoe(st, foe, {})
  ExpSeq.begin(awards)
  local texts, levels = {}, 0
  for _, step in ipairs(ExpSeq._steps) do
    if step.kind == "msg" then texts[#texts + 1] = step.data.text end
    if step.kind == "level" then levels = levels + 1 end
  end
  eq(texts[1], "LEAD gained\n91 EXP. Points!", "the fighter keeps its own line")
  eq(texts[2], "The rest of the party\ngained EXP. Points!",
     "the bench's lines become one")
  eq(#texts, 2, "and only one")
  eq(levels, 1, "while a bench level-up keeps its own step")
end

-- ----------------------------------------------------------- AUTO SAVE

do
  io.write("AUTO SAVE: due on events, written when the cart could save\n")
  local mod = install("modules/Gen3QOL/autosave.lua", armMod())
  local Player = { moving = false }
  package.loaded["src.core.game3.player"] = Player
  local writes = 0
  local game = { phase = "field", allowed = true }
  function game:quickSaveAllowed() return self.allowed end
  function game:saveGame()
    writes = writes + 1
    mod.emit("save.writing", {})
    return true
  end
  local update = mod.wrapped["core.update"]
  local stepped = 0
  local function frames(seconds)
    for _ = 1, seconds do
      update(function() stepped = stepped + 1 end, game, 1)
    end
  end

  mod.emit("save.loaded", {})
  frames(30)
  eq(writes, 0, "a fresh load: nothing is new, nothing is written")
  eq(stepped, 30, "and the game's own update runs every frame")

  mod.emit("battle.ended", {})
  frames(1)
  eq(writes, 1, "a battle won: written on the next frame the cart could save")

  mod.emit("pokemon.caught", {})
  frames(5)
  eq(writes, 1, "not twice inside fifteen seconds")
  frames(10)
  eq(writes, 2, "and then it is")

  mod.emit("pokemon.evolved", {})
  game.allowed = false
  frames(30)
  eq(writes, 2, "never while the cart would not let the player save")
  game.allowed = true
  Player.moving = true
  frames(1)
  eq(writes, 2, "nor mid-step")
  Player.moving = false
  frames(1)
  eq(writes, 3, "the first frame both say yes, it is written")

  mod.emit("map.entered", { mapId = "FR_ROUTE_1" })
  frames(20)
  eq(writes, 3, "the first map of a session is where the save already stands")
  mod.emit("map.entered", { mapId = "FR_ROUTE_1" })
  frames(20)
  eq(writes, 3, "the same map again is not a new area")
  mod.emit("map.entered", { mapId = "FR_VIRIDIAN_CITY" })
  frames(1)
  eq(writes, 4, "a new map is")

  mod.stored.events = false
  mod.emit("battle.ended", {})
  frames(20)
  eq(writes, 4, "AFTER EVENTS off: a battle does not")
  mod.stored.events = nil

  -- The player's own START > SAVE is a save: the clock starts again there.
  mod.stored.interval = 60
  mod.emit("save.writing", {})
  frames(59)
  eq(writes, 4, "INTERVAL 1 MIN: not before a minute of play since a save")
  frames(2)
  eq(writes, 5, "and at one")
  mod.stored.interval = nil

  mod.stored.enabled = false
  mod.emit("battle.ended", {})
  frames(60)
  eq(writes, 5, "AUTO SAVE off: nothing")
  mod.stored.enabled = nil

  -- The indicator.
  local drawn = 0
  love = love or {}
  love.graphics = love.graphics or {}
  for _, name in ipairs({ "setColor", "setLineWidth", "line", "circle" }) do
    love.graphics[name] = love.graphics[name] or function() end
  end
  love.graphics.arc = function() drawn = drawn + 1 end
  mod.emit("battle.ended", {})
  local before = writes
  for _ = 1, 30 do
    if writes > before then break end
    frames(1)
  end
  eq(writes, before + 1, "(written)")
  local hud = mod.wrapped["render.hud"]
  hud(function() end, game, { gameX = 0, gameY = 0, gameWidth = 480,
                              gameHeight = 320, scale = 2 })
  ok(drawn > 0, "a write puts the Poke Ball up")
  frames(3)
  drawn = 0
  hud(function() end, game, { gameX = 0, gameY = 0, gameWidth = 480,
                              gameHeight = 320, scale = 2 })
  eq(drawn, 0, "and it goes again")
end

-- ---------------------------------------------------------------- SOUND

do
  io.write("SOUND: FireRed's alarm ctx is Red's shape\n")
  -- Gen1SoundQOL's wrapper, built the way its main installs it, fed the ctx
  -- src/core/game3/battle/init.lua update_low_hp_music passes once a frame.
  local Alarm = load_("modules/Gen1SoundQOL/src/alarm.lua")
  local settings = { alarm_mode = "cycles", alarm_cycles = 2, alarm_retrigger = true }
  local wrapper = Alarm.newWrapper(function(key) return settings[key] end, 30)
  local st = { player = { mon = { hp = 9 } } }
  local heard = {}
  local function frame()
    local ctx = { on = true, battle = st }
    wrapper(function(c) heard[#heard + 1] = c.on end, ctx)
  end
  for _ = 1, 60 do frame() end
  eq(heard[60], true, "two cycles of thirty frames: still sounding at 60")
  frame()
  eq(heard[61], false, "and silenced on the 61st")
  st.player.mon.hp = 4
  frame()
  eq(heard[62], true, "a hit in the red: the battle's own hp says so, and it beeps again")
end

-- ------------------------------------------------------ the sandbox's package

do
  io.write("no arm reads package.loaded\n")
  -- Inside the mod sandbox `package` is a shim whose `loaded` is EMPTY
  -- (src/mods/LegacyCompat.lua packageShim).  A lookup there passes every
  -- test in this file -- the stand-ins are in the real package.loaded -- and
  -- finds nothing on a real boot, which is how SPRINT once said no to every
  -- step.  So it is checked in the source.
  for _, name in ipairs({ "sprint", "expshare", "reusable_tms", "autosave" }) do
    local body = readFile("modules/Gen3QOL/" .. name .. ".lua") or ""
    local code = body:gsub("%-%-[^\n]*", "")
    eq(code:find("package%.loaded") , nil,
       name .. ".lua reaches the engine through require")
  end
end

-- ---------------------------------------------------- the bundle on Gen 3

do
  io.write("the bundle on a Gen 3 boot\n")
  package.loaded["src.core.GameVersion"] = {
    generation = function() return 3 end,
    get = function() return "firered" end,
    isYellow = function() return false end,
  }
  package.loaded["src.mods.ManagerState"] = { openOptions = function() end }
  package.loaded["src.core.game3.player"] = { canDash = function() return false end }

  local reads = {}
  local mod = { id = "gen1_wild_qol", path = ".", version = "0", exports = {},
                stored = {}, saved = {}, hooked = {}, screens = {} }
  function mod:read(path)
    reads[path] = true
    return readFile(path)
  end
  mod.options = {
    define = function(_, schema) mod.defined = schema end,
    get = function(_, key) return mod.stored[key] end,
    set = function(_, key, value) mod.stored[key] = value end,
  }
  local function bucket()
    return { get = function() return nil end, set = function() end,
             read = function() return nil end, write = function() return true end }
  end
  mod.save, mod.cache, mod.storage = bucket(), bucket(), bucket()
  mod.log = {}
  local errors = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    mod.log[level] = function(_, fmt, ...)
      if level == "error" or level == "warn" then
        errors[#errors + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
      end
    end
  end
  mod.hooks = { wrap = function(_, name) mod.hooked[name] = true end }
  mod.events = { on = function() end, once = function() end, emit = function() end }
  mod.content = { screens = { register = function(_, id) mod.screens[id] = true end } }
  mod.ui = { push = function() end }
  mod.find = function() return nil end
  mod.world = {}

  local Loader = load_("runtime/loader.lua")
  local loader = Loader.new(mod)
  local registry = loader.run("features.lua")
  local Bundle = loader.run("runtime/bundle.lua", function(name)
    return loader.run("runtime/" .. name .. ".lua")
  end)
  Bundle.install(mod, registry.spec, registry.features)

  local installed = {}
  for id, yes in pairs(mod.exports.installed) do
    if yes then installed[#installed + 1] = id end
  end
  table.sort(installed)
  eq(table.concat(installed, " "), "autosave expshare reusabletms sound sprint",
     "five features install on Gen 3, and only those")
  eq(#errors, 0, "with nothing on the log: " .. table.concat(errors, " / "))
  for path in pairs(reads) do
    if path:match("^modules/") and not path:match("^modules/Gen3QOL/")
        and not path:match("^modules/Gen1SoundQOL/")
        and path ~= "modules/versions.lua" then
      ok(false, "nothing written for Red is read: " .. path)
    end
  end
  eq(next(mod.screens), nil, "and no screens are registered")
  ok(mod.hooked["core.update"] and mod.hooked["battle.low_health_alarm"],
     "the arms' own hooks are")

  local byKey = {}
  for _, row in ipairs(mod.defined or {}) do byKey[row.key] = row end
  ok(byKey.sprint_enabled and byKey.sprint_early and byKey.sprint_indoors,
     "SPRINT's rows are in the schema FireRed's MOD OPTIONS lists")
  ok(byKey.expshare_enabled and byKey.expshare_mode,
     "EXP SHARE's switch and mode")
  ok(byKey.reusabletms_qol_reusable_tms,
     "REUSABLE TMS keeps the row key it has on every other cart")
  ok(byKey.autosave_enabled and byKey.autosave_interval, "AUTO SAVE's")
  ok(byKey.sound_alarm_mode, "and SOUND's")
end

io.write(("gen3 qol: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
