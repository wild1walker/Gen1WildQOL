-- EXP SHARE on FireRed, LeafGreen and Emerald.
--
-- The Gen 1 feature has a GEN 1 mode because Red has the Exp. All; a GBA cart
-- has the held Exp. Share instead, and it still works -- a holder is one of
-- the cart's own recipients and is left exactly as the cart paid it.  What
-- this adds is the modern rule: the fighters keep their full share, and every
-- other Pokemon in the party that can still gain gets a share of their own.
--
--   GEN 5+    the bench gains half a fighter's share.
--   BALANCED  the same, but only while a bench Pokemon is below the level of
--             the one that fought, so the bench trails the party rather than
--             racing it.
--   AVERAGE   the same gate, measured against the party's average level.
--   CUSTOM    the bench gains BENCH SHARE percent of a fighter's share.
--
-- A fighter's share is the cart's own arithmetic (pokefirered
-- src/battle_script_commands.c:3113): the defeated species' base yield times
-- its level over seven, split between the Pokemon that fought.  A bench
-- Pokemon's is a fraction of that, then the same three boosts the cart gives
-- anyone -- a trainer battle, a Lucky Egg, a traded Pokemon -- and the effort
-- values with it, as a held Exp. Share would.
--
-- Two seams.  `Experience.awardFoe` is wrapped to add the bench to what the
-- cart awarded; its result is the list the battle's experience sequence walks
-- for messages, level-ups and new moves, and a bench entry is one the
-- sequence already knows how to show (it is how a held Exp. Share is shown).
-- And `ExpSeq.begin` is wrapped so the bench's "gained N EXP. Points!" lines
-- become one -- "The rest of the party gained EXP. Points!" -- while every
-- level-up and every new move keeps its own.  If the cart's lines ever stop
-- matching what is expected here, nothing is removed and the bench simply
-- speaks for itself.

local SHARE_TEXT = "The rest of the party\ngained EXP. Points!"

local MODES = { off = true, gen5 = true, balanced = true, average = true,
                custom = true }

return function(mod)
  local percents = {}
  for pct = 10, 100, 10 do percents[#percents + 1] = { pct .. "%", pct } end
  mod.options:define({
    { key = "mode", type = "choice", label = "EXP SHARE", default = "gen5",
      choices = {
        { "OFF", "off" },
        { "GEN 5+", "gen5" },
        { "BALANCED", "balanced" },
        { "AVERAGE", "average" },
        { "CUSTOM", "custom" },
      },
      help = "The bench gains alongside the Pokemon that fought." },
    { key = "percent", type = "choice", label = "BENCH SHARE", default = 50,
      choices = percents,
      help = "How much of a fighter's share the bench gains.",
      visible_if = { key = "mode", equals = "custom" } },
  })

  local okE, Experience = pcall(require, "src.core.game3.battle.experience")
  local okS, ExpSeq = pcall(require, "src.core.game3.battle.exp_seq")
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not (okE and type(Experience) == "table"
          and type(Experience.awardFoe) == "function"
          and okP and type(Pokemon) == "table") then
    mod.log:warn("Gen 3 experience is not where this expects it; EXP SHARE is off")
    return
  end

  local function mode()
    local value = mod.options:get("mode")
    if MODES[value] then return value end
    return "gen5"
  end

  local function percent()
    if mode() ~= "custom" then return 50 end
    local value = tonumber(mod.options:get("percent")) or 50
    return math.max(10, math.min(100, value))
  end

  local function alive(mon)
    if type(mon) ~= "table" then return false end
    if type(Pokemon.isEgg) == "function" and Pokemon.isEgg(mon) then return false end
    return (tonumber(mon.species or mon.speciesId) or 0) ~= 0
      and (tonumber(mon.hp) or 0) > 0
  end

  local function boosted(amount, isTrainer, per)
    if per.luckyEgg then amount = math.floor(amount * 150 / 100) end
    if isTrainer then amount = math.floor(amount * 150 / 100) end
    if per.traded then amount = math.floor(amount * 150 / 100) end
    return amount
  end

  -- Which bench Pokemon the gate lets through.  BALANCED measures against
  -- the Pokemon in front -- the one on the field when the foe went down --
  -- and AVERAGE against the whole living party, fighters included.
  local function gate(st, party)
    local which = mode()
    if which == "balanced" then
      local lead = st and st.player and st.player.mon
      local level = tonumber(lead and lead.level)
      if not level then return function() return true end end
      return function(mon) return (tonumber(mon.level) or 1) < level end
    elseif which == "average" then
      local sum, count = 0, 0
      for i = 1, 6 do
        if alive(party[i]) then
          sum = sum + (tonumber(party[i].level) or 1)
          count = count + 1
        end
      end
      if count == 0 then return function() return true end end
      local average = sum / count
      return function(mon) return (tonumber(mon.level) or 1) < average end
    end
    return function() return true end
  end

  -- The fighters, counted the way the cart counts them.  The cart's own
  -- awards say who was paid, and of those the ones that were paid for
  -- FIGHTING are every one not holding an Exp. Share -- a holder who also
  -- fought is counted once, as a fighter.
  local function fighters(st, foe, opts)
    local sentIn = {}
    if opts and opts.partyIndices then
      for _, pi in ipairs(opts.partyIndices) do sentIn[pi] = true end
    elseif foe and foe.participants and next(foe.participants) then
      for pi in pairs(foe.participants) do sentIn[pi] = true end
    elseif st and st.player and st.player.mon
        and (tonumber(st.player.mon.hp) or 0) > 0 then
      sentIn[st.player.partyIndex or 1] = true
    end
    local party = (st and st.playerParty) or {}
    local count = 0
    for pi in pairs(sentIn) do
      if alive(party[pi]) then count = count + 1 end
    end
    return sentIn, count
  end

  local shared = setmetatable({}, { __mode = "k" })

  local baseAward = Experience.awardFoe
  Experience.awardFoe = function(st, foe, opts, ...)
    local out = baseAward(st, foe, opts, ...)
    if mode() == "off" or type(out) ~= "table" or not st or not foe then
      return out
    end
    local party = st.playerParty or {}
    local paid = {}
    for _, entry in ipairs(out) do
      if entry.partyIndex then paid[entry.partyIndex] = true end
    end
    local sentIn, count = fighters(st, foe, opts)

    local foeMon = foe.mon
    local foeSpecies = foe.species or (foeMon and (foeMon.species or foeMon.speciesId))
    local foeLevel = (foeMon and foeMon.level) or foe.level or 1
    local isTrainer = opts and opts.trainer
    if isTrainer == nil then isTrainer = not st.wild end
    local yield = tonumber(Experience.expYield(foeSpecies)) or 0
    local calculated = math.floor(yield * math.max(1, tonumber(foeLevel) or 1) / 7)
    local fighterShare = math.floor(calculated / math.max(1, count))
    local share = math.floor(fighterShare * percent() / 100)
    if share <= 0 then return out end

    local admits = gate(st, party)
    local ctx = { mapSec = type(Pokemon.currentMapSec) == "function"
      and Pokemon.currentMapSec(st.session) or nil }
    for pi = 1, 6 do
      local mon = party[pi]
      if alive(mon) and not paid[pi] and not sentIn[pi]
          and (tonumber(mon.level) or 1) < (Experience.MAX_LEVEL or 100)
          and admits(mon) then
        local per = type(Experience.recipientOpts) == "function"
          and Experience.recipientOpts(st, mon) or {}
        local amount = math.max(1, boosted(share, isTrainer, per))
        if type(Pokemon.gainEVs) == "function" then
          Pokemon.gainEVs(mon, foeSpecies)
        end
        local result = Experience.apply(mon, amount)
        if type(Pokemon.adjustFriendship) == "function" and result then
          for _ = 1, #(result.levels or {}) do
            Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL, ctx)
          end
        end
        local entry = {
          mon = mon,
          partyIndex = pi,
          battler = nil,
          expGetterBattlerId = 0,
          amount = amount,
          boosted = per.traded and true or false,
          result = result,
        }
        shared[entry] = true
        out[#out + 1] = entry
      end
    end
    return out
  end

  -- ------- one line for the bench
  if okS and type(ExpSeq) == "table" and type(ExpSeq.begin) == "function" then
    local okT, BattleText = pcall(require, "src.core.game3.battle.battle_text")
    local function gainedLine(entry)
      if not (okT and type(BattleText) == "table") then return nil end
      local result = entry.result or {}
      -- Built the way exp_seq.lua builds it, and all of it under the pcall:
      -- a line this cannot build is a line it does not fold.
      local ok, text = pcall(function()
        return BattleText.get("STRINGID_PKMNGAINEDEXP", {
          buff1 = Pokemon.displayMonName(entry.mon),
          buff2 = BattleText.get(entry.boosted and "STRINGID_ABOOSTED"
                                 or "STRINGID_EMPTYSTRING4"),
          buff3 = tostring(result.gained or entry.amount or 0),
        })
      end)
      return ok and text or nil
    end

    local baseBegin = ExpSeq.begin
    ExpSeq.begin = function(awards, ...)
      local lines = {}
      for _, entry in ipairs(awards or {}) do
        if shared[entry] then
          local line = gainedLine(entry)
          if line then lines[line] = (lines[line] or 0) + 1 end
        end
      end
      local results = { baseBegin(awards, ...) }
      if next(lines) == nil or type(ExpSeq._steps) ~= "table" then
        return (table.unpack or unpack)(results)
      end
      local kept, at = {}, nil
      for _, step in ipairs(ExpSeq._steps) do
        local text = step.kind == "msg" and step.data and step.data.text
        if text and (lines[text] or 0) > 0 then
          lines[text] = lines[text] - 1
          if not at then
            at = #kept + 1
            kept[at] = { kind = "msg", data = { text = SHARE_TEXT } }
          end
        else
          kept[#kept + 1] = step
        end
      end
      ExpSeq._steps = kept
      return (table.unpack or unpack)(results)
    end
  end

  mod.exports.mode = mode
end
