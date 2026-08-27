-- What a status looks like, and how a four-shade palette wears it.
--
-- Everything here is arithmetic on numbers: no love, no engine modules, no
-- mod object.  That is deliberate -- the interesting half of this feature is
-- "what colour, and how much of it", and a pure module is the half a test can
-- hold still.  main.lua does the talking to the engine.
--
-- A Game Boy zone is four colours, lightest shade first, and the screen is
-- drawn by remapping each of the art's four greys onto one of them
-- (src/render/PaletteFX.lua).  So tinting is not an overlay: there is no
-- rectangle laid on top and no alpha anywhere.  The four colours themselves
-- move, and the result is a screen that still has its full range of light and
-- dark -- it has simply changed hue, the way a real SGB palette swap does.

local Colours = {}

-- ------- the statuses
--
-- Gen 1's five, plus the two conditions that are not statuses but read like
-- them: Toxic (a counter riding on PSN, src/battle/EffectRegistry.lua) and
-- fainted (hp == 0, which no status field records).
--
-- `rank` breaks ties when a party holds several at once: the overworld can
-- only wear one colour, and it should be the one the player most needs to
-- know about.  Fainted outranks everything because it is the one that cannot
-- be walked off; poison next, because it is the one still taking HP while you
-- walk.  The rest are ordered by how much they cost you in the next battle.
Colours.STATUSES = {
  { key = "fainted", label = "FAINTED",   rank = 60, tint = nil,
    desaturate = true },
  { key = "tox",     label = "BAD POISON", rank = 50, tint = { 120,  40, 152 } },
  { key = "psn",     label = "POISON",    rank = 40, tint = { 168,  80, 184 } },
  { key = "brn",     label = "BURN",      rank = 30, tint = { 232,  96,  56 } },
  { key = "frz",     label = "FREEZE",    rank = 25, tint = { 104, 200, 232 } },
  { key = "par",     label = "PARALYSIS", rank = 20, tint = { 232, 208,  72 } },
  { key = "slp",     label = "SLEEP",     rank = 10, tint = {  96, 112, 160 } },
  -- Not a status: a mon still standing but nearly out of HP.  It is here
  -- because it is the other thing the game already tells you about with a
  -- signal of its own -- the low-health alarm -- and the colour says the same
  -- thing without the noise.  Ranked below every status: a poisoned mon at
  -- low HP is poisoned, and that is the more actionable fact.
  { key = "lowhp",   label = "LOW HP",    rank = 5,  tint = { 232,  64,  64 } },
}

-- the engine's own status strings (src/pokemon/Pokemon.lua:82) to our keys
Colours.FROM_STATUS = {
  SLP = "slp", PSN = "psn", BRN = "brn", FRZ = "frz", PAR = "par",
}

local byKey = {}
for _, entry in ipairs(Colours.STATUSES) do byKey[entry.key] = entry end
Colours.BY_KEY = byKey

function Colours.entry(key) return byKey[key] end

-- ------- reading a mon
--
-- Order matters and is not the rank order: this answers "what is true of this
-- mon", and a fainted mon is fainted whatever its status byte still says.
-- The Toxic counter is a separate field because Gen 1 keeps Toxic as PSN plus
-- a counter rather than as a status of its own; a mon carrying the counter is
-- badly poisoned even though `status` reads PSN.
--
-- lowFraction: the share of max HP at or below which LOW HP applies.  The
-- engine's own low-health alarm is 1/5 (src/battle), which is the default the
-- caller passes; this takes it as an argument rather than hard-coding it so
-- the option can move it without this module knowing an option exists.
function Colours.keyFor(mon, lowFraction)
  if type(mon) ~= "table" then return nil end
  local hp = tonumber(mon.hp)
  if hp and hp <= 0 then return "fainted" end
  -- A mon with no maxHP is not a mon this can judge -- an empty party slot,
  -- or a stub in a test -- and guessing would paint the whole screen.
  local status = mon.status
  if status == "PSN" and (tonumber(mon.toxicCounter or mon.toxic) or 0) > 0 then
    return "tox"
  end
  local mapped = type(status) == "string" and Colours.FROM_STATUS[status] or nil
  if mapped then return mapped end
  -- Max HP is `mon.stats.hp` in this engine (src/pokemon/Pokemon.lua: `hp =
  -- stats.hp` at creation, and Pokemon.heal reads `mon.stats.hp` back).  The
  -- other two spellings are what a battler or a serialized mon may carry, and
  -- are here so this answers for those too rather than silently declining to.
  local stats = type(mon.stats) == "table" and mon.stats or nil
  local maxHP = tonumber((stats and stats.hp) or mon.maxHP or mon.maxHp)
  if hp and maxHP and maxHP > 0 and lowFraction and lowFraction > 0
      and hp <= maxHP * lowFraction then
    return "lowhp"
  end
  return nil
end

-- The one condition a party wears, by rank.  `allowed` is a set of keys the
-- caller will act on, so an option that says "poison only" is a filter here
-- rather than a branch in every caller.
function Colours.worstIn(party, lowFraction, allowed)
  local best, bestRank
  for _, mon in ipairs(party or {}) do
    local key = Colours.keyFor(mon, lowFraction)
    if key and (allowed == nil or allowed[key]) then
      local rank = byKey[key] and byKey[key].rank or 0
      if not bestRank or rank > bestRank then best, bestRank = key, rank end
    end
  end
  return best
end

-- ------- wearing it

local function clamp8(v)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return math.floor(v + 0.5)
end

-- Rec. 601 luma.  The point is not colour science, it is that a shade's
-- weight has to survive the tint: shade 4 is the ink the text is drawn in and
-- shade 1 is the paper behind it, and a tint that flattened them would take
-- the screen's legibility with it.
function Colours.luma(c)
  return (0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]) / 255
end

-- One colour, tinted.  The target is the tint scaled by this shade's own
-- luma, so the darkest shade goes to nearly black rather than to the tint --
-- which is what keeps four distinguishable shades instead of four variations
-- on purple.
function Colours.tintColour(c, tint, amount)
  if amount <= 0 or not tint then return { c[1], c[2], c[3] } end
  local l = Colours.luma(c)
  local keep = 1 - amount
  return {
    clamp8(c[1] * keep + tint[1] * l * amount),
    clamp8(c[2] * keep + tint[2] * l * amount),
    clamp8(c[3] * keep + tint[3] * l * amount),
  }
end

-- One colour, drained.  Fainted is the absence of colour rather than a colour
-- of its own: a grey mon among coloured ones reads as "this one is out"
-- without having to be told which grey means what.
function Colours.desaturateColour(c, amount)
  if amount <= 0 then return { c[1], c[2], c[3] } end
  local grey = Colours.luma(c) * 255
  local keep = 1 - amount
  return {
    clamp8(c[1] * keep + grey * amount),
    clamp8(c[2] * keep + grey * amount),
    clamp8(c[3] * keep + grey * amount),
  }
end

-- A whole four-colour palette, wearing `key` at `amount`.
-- Returns a new table; the caller's palette is never written through, because
-- zone colour tables are shared with the engine's own palette records and
-- editing one in place would tint the game permanently.
function Colours.apply(colors, key, amount)
  local entry = byKey[key]
  if not entry or amount <= 0 or type(colors) ~= "table" then return colors end
  local out = {}
  for i = 1, #colors do
    local c = colors[i]
    if type(c) ~= "table" then
      out[i] = c
    elseif entry.desaturate then
      out[i] = Colours.desaturateColour(c, amount)
    else
      out[i] = Colours.tintColour(c, entry.tint, amount)
    end
  end
  return out
end

-- ------- how much of it
--
-- The resting depth of the tint, and the extra it takes on for the frames the
-- engine would have spent flashing the screen black.
--
-- `pulse` is the engine's own poisonFlash counter, which it sets to 12 and
-- counts down (src/world/OverworldController.lua).  Reading it rather than
-- keeping our own means the deepening lands exactly on the tick that took the
-- HP, including any mod that moves the interval.
Colours.LEVELS = { subtle = 0.22, normal = 0.38, strong = 0.55 }

function Colours.amountFor(level, pulse, pulseMax)
  local base = Colours.LEVELS[level] or Colours.LEVELS.normal
  if not pulse or pulse <= 0 then return base end
  local span = pulseMax or 12
  if span <= 0 then return base end
  local share = pulse / span
  if share > 1 then share = 1 end
  -- Toward -- never to -- 1.  A tick that went fully opaque would be the
  -- black flash again in a different colour, and the whole point is that the
  -- screen never stops showing the game.
  local peak = base + (1 - base) * 0.55
  return base + (peak - base) * share
end

return Colours
