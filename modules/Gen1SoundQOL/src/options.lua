-- Every Gen1SoundQOL behaviour is a row here, and every row ships with the
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

-- One full two-tone cycle of the vanilla siren is 30 game frames
-- (src/core/ChipAudio.lua newLowHealthAlarm: a 30-frame period at 60 fps),
-- so the shipped default of six beeps runs for three seconds before the
-- siren goes quiet.
Options.ALARM_CYCLE_FRAMES = 30

Options.schema = {
  -- ------- the low-HP siren

  { key = "alarm_mode", type = "choice", label = "LOW HP BEEP",
    default = "cycles",
    choices = {
      { "ONCE", "once" },
      { "N BEEPS", "cycles" },
      { "VANILLA", "vanilla" },
    } },

  { key = "alarm_cycles", type = "number", label = "BEEP COUNT",
    default = 6, min = 1, max = 8, step = 1,
    visible_if = { key = "alarm_mode", equals = "cycles" } },

  { key = "alarm_retrigger", type = "toggle", label = "BEEP EACH HIT",
    default = true,
    visible_if = { key = "alarm_mode", not_equals = "vanilla" } },
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
-- anything -- an older version's vocabulary (0.1.0 also stored bg_mute_* keys
-- here), a hand-edited options.lua -- and a mod that reshaped the siren off a
-- garbage string would be a bug report nobody could diagnose.  Anything out of
-- vocabulary falls back to the row default, which is always the
-- vanilla-preserving answer.
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
