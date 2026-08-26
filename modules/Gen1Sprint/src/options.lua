-- Every Gen1Sprint behaviour is a row here, and every row ships with the
-- vanilla-preserving default spelled out next to it.  The schema is handed
-- to mod.options:define, which is what draws the rows in MODS > OPTIONS and
-- what the launcher's mod_option_schemas.json snapshot is built from
-- (docs/mod-option-schema.md).
--
-- Row shapes are the four the engine renders: toggle, choice, number, text.
-- `choices` are { label, value } pairs; `visible_if` only hides a menu row,
-- it never changes the stored value, so a hidden row still reads back the
-- value the player last chose.

local Options = {}

-- SPRINT SPEED is stored as a divisor on the step the engine was about to
-- take, not as a frame count, so it composes: a mod that slows walking down
-- keeps its ratio, and the same "2x" means 2x on foot and 2x on the bike.
--
-- 2x is the shipped default because that is what FireRed's running shoes
-- are -- 16 frames per tile walking, 8 running -- and 8 is also what
-- Gen 1's own BICYCLE rides at (src/world/FieldDefaults.lua bikeStepFrames),
-- so sprinting on foot lands on a speed the engine already animates cleanly.
Options.MULTIPLIERS = {
  ["1"] = 1,       -- VANILLA: the engine's own answer, untouched
  ["1_5"] = 1.5,
  ["2"] = 2,
  ["3"] = 3,
}

Options.schema = {
  -- ------- the sprint itself

  { key = "enabled", type = "toggle", label = "SPRINT", default = true },

  -- B is free in the overworld: the only two things that read it there are
  -- the Cycling Road brake and the pikapic skip, and neither can be running
  -- while a direction is held (src/world/OverworldController.lua).  SELECT
  -- is read nowhere in the overworld at all, so it is offered for players
  -- who would rather keep B clear out of habit.
  { key = "button", type = "choice", label = "HOLD", default = "b",
    choices = {
      { "B", "b" },
      { "SELECT", "select" },
    },
    visible_if = { key = "enabled", equals = true } },

  { key = "speed", type = "choice", label = "SPRINT SPEED", default = "2",
    choices = {
      { "1.5x", "1_5" },
      { "2x", "2" },
      { "3x", "3" },
    },
    visible_if = { key = "enabled", equals = true } },

  -- ------- the bicycle
  -- Not a sprint row: this one applies whether or not anything is held, and
  -- it stays visible with SPRINT: OFF, because a player who wants only the
  -- faster bike is entitled to exactly that and nothing else.
  --
  -- The default is 2x, and it is a departure from vanilla rather than a
  -- restoration of it -- the one row in this mod that is.  Gen 1's bicycle
  -- is 8 frames per tile, which is precisely what a 2x sprint already gives
  -- you on foot, so with this mod installed and the bike left alone the
  -- bicycle is not a faster way to travel at all.  2x here puts it at 4 and
  -- restores the ladder: 16 walking, 8 sprinting, 4 riding.
  --
  -- It is a game-feel choice and not a parity one, and it is worth being
  -- straight about which.  FireRed's bicycle is MOVE_SPEED_FAST_1 -- 8
  -- frames per tile, the same constant its running shoes use -- so in
  -- FireRed the two really are the same speed and the bike is the poorer
  -- deal, working in strictly fewer places for no gain.  4 is not FireRed's
  -- ordinary bike; it is FireRed's Cycling Road roll (MOVE_SPEED_FASTER),
  -- borrowed because it is the speed that game does reach on a bicycle.
  -- VANILLA is one row away and restores Gen 1's 8 exactly.

  { key = "bike_speed", type = "choice", label = "BIKE SPEED", default = "2",
    choices = {
      { "VANILLA", "1" },
      { "1.5x", "1_5" },
      { "2x", "2" },
      { "3x", "3" },
    } },

  -- ------- where it applies
  -- Both default OFF, which is the FireRed answer: running shoes are a
  -- thing you do on foot.  Vanilla surf and vanilla bike speeds are what an
  -- untouched row leaves you with.

  { key = "surf", type = "toggle", label = "SPRINT SURFING", default = false,
    visible_if = { key = "enabled", equals = true } },

  { key = "bike", type = "toggle", label = "SPRINT ON BIKE", default = false,
    visible_if = { key = "enabled", equals = true } },
}

-- key -> row, so the reader can fall back to a default and validate a choice
-- against the values the schema actually offers.
local byKey = {}
for _, row in ipairs(Options.schema) do byKey[row.key] = row end

local function legal(row, value)
  if row.type == "toggle" then return type(value) == "boolean" end
  if row.type == "number" then return type(value) == "number" end
  if row.type == "choice" then
    for _, choice in ipairs(row.choices) do
      if choice[2] == value then return true end
    end
    return false
  end
  return true
end

-- A reader rather than raw mod.options:get calls: a stored value can be
-- anything -- an older version's vocabulary, a hand-edited options.lua --
-- and a mod that divided a step length by a garbage string would be a
-- crash in the middle of the overworld.  Anything out of vocabulary falls
-- back to the row default, which is always the vanilla-preserving answer.
function Options.reader(mod)
  return function(key)
    local row = byKey[key]
    if not row then return nil end
    local value = mod.options:get(key)
    if value == nil or not legal(row, value) then return row.default end
    if row.type == "number" then
      if row.min then value = math.max(row.min, value) end
      if row.max then value = math.min(row.max, value) end
    end
    return value
  end
end

return Options
