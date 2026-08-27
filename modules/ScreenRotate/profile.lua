-- What a landscape profile is, and how it is put on and taken off again.
--
-- Everything in this file is pure: it is handed a reader for the feature's
-- own option rows and the engine's live options table, and it answers with
-- plain tables.  Nothing here knows about `love`, the frame loop or the
-- engine's display modules -- main.lua owns all three -- which is what lets
-- the interesting part be driven headlessly in tests/qol_features_test.lua.

local Profile = {}

-- ---- what a profile covers
--
-- The screen settings and nothing else.  A phone turned sideways is a
-- different shape, not a different game, so the rows here are the ones that
-- decide the shape and framing of the picture: the widescreen battle set, the
-- UI composition, the 10:9 lock and where the picture sits in the display.
-- Text speed, battle style, volumes, the ruleset and every other row on the
-- engine's OPTION screen are deliberately absent -- they mean the same thing
-- in both orientations, so switching them on a rotation would be a surprise
-- rather than a convenience.
--
--   key      the row in this feature's own settings
--   option   the engine option in `save.options` it governs
--   values   row value -> engine value, when the two are not the same string
--
-- "SAME" is every row's default and means the row is not in the profile at
-- all: that setting keeps whatever it is set to upright.  A profile of
-- nothing but SAME is a profile that does nothing, which is what this feature
-- ships as under CUSTOM.

Profile.SETTINGS = {
  {
    key = "battle_layout", option = "battleLayout", label = "BATTLE LAYOUT",
    choices = { { "SAME", "same" }, { "OG", "og" }, { "WIDE", "wide" } },
    description = "THE BATTLE SCREEN SIDEWAYS: OG IS THE CLASSIC 160X144 ONE, WIDE IS THE 304X144 COMPOSITION.",
  },
  {
    key = "battle_size", option = "battleFit", label = "BATTLE SIZE",
    choices = { { "SAME", "same" }, { "FIXED", "fixed" }, { "FILL", "fill" } },
    description = "FIXED KEEPS THE INTEGER-SCALED LETTERBOX SIDEWAYS. FILL SCALES THE BATTLE TO THE SCREEN.",
  },
  {
    key = "battle_hud", option = "battleHud", label = "BATTLE HUD",
    choices = { { "SAME", "same" }, { "STANDARD", "standard" }, { "EXTENDED", "extended" } },
    description = "THE EXTENDED HUD IS A WIDESCREEN COMPOSITION, SO IT ONLY APPLIES WHERE THE LAYOUT IS WIDE.",
  },
  {
    key = "ui_layout", option = "uiLayout", label = "UI LAYOUT",
    choices = { { "SAME", "same" }, { "CENTERED", "centered" }, { "DYNAMIC", "dynamic" } },
    description = "DYNAMIC DOCKS THE DIALOGUE BOX AND THE START MENU TO THE SCREEN'S OWN EDGES SIDEWAYS.",
  },
  {
    key = "faithful", option = "faithfulRes", label = "FAITHFUL RATIO",
    choices = { { "SAME", "same" }, { "OFF", "off" }, { "ON", "on" } },
    -- The engine stores this as a level, 0 for OFF; on a phone there is one
    -- ON and the renderer picks the scale from the display
    -- (src/core/FaithfulRes.lua).
    values = { off = 0, on = 1 },
    description = "THE 10:9 LOCK SIDEWAYS. OFF LETS THE PICTURE USE THE WIDTH A TURNED PHONE JUST GAINED.",
  },
  {
    key = "letterbox", option = "uiLetterbox", label = "UI LETTERBOX",
    choices = { { "SAME", "same" }, { "AUTO", "auto" }, { "BLACK", "black" },
                { "WHITE", "white" }, { "PALETTE", "palette" } },
    description = "WHAT FILLS THE SCREEN AROUND THE PICTURE SIDEWAYS.",
  },
  {
    key = "screen_pos", option = "screenPos", label = "SCREEN POS",
    choices = { { "SAME", "same" }, { "CENTER", "center" }, { "UPPER", "upper" },
                { "TOP", "top" } },
    description = "WHERE THE PICTURE SITS IN THE SCREEN SIDEWAYS.",
  },
}

-- The one-press answer to "just make it wide when I turn the phone".  It is
-- the widescreen set the engine's own OPTION screen offers, plus the 10:9
-- lock off -- holding an exact 10:9 is the one setting that throws away the
-- width a turned phone just gained, so WIDE without it would be half a
-- profile.
--
-- Deliberately silent about UI LETTERBOX and SCREEN POS: neither is what
-- "wide" means, and a preset that quietly moved the picture as well would be
-- doing something nobody asked it for.
Profile.WIDE = {
  battleLayout = "wide",
  battleFit = "fill",
  battleHud = "extended",
  uiLayout = "dynamic",
  faithfulRes = 0,
}

-- Landscape is the wider-than-tall one.  A square window counts as upright:
-- with nothing gained on either axis there is nothing for a landscape
-- profile to spend.
function Profile.landscape(width, height)
  width, height = tonumber(width), tonumber(height)
  if not width or not height then return false end
  return width > height
end

local function engineValue(setting, value)
  if setting.values then return setting.values[value] end
  return value
end

-- The engine options a landscape profile wants set, as
-- `{ [engine key] = value }`.  Empty means "change nothing", which is what
-- OFF and an all-SAME CUSTOM both come to.
--
-- `options` is the live table, read for one thing only: the extended HUD is a
-- widescreen composition, so a profile asking for it without also asking for
-- WIDE has to be read against whatever the layout will actually be.  The
-- engine's own row does the same clamp (src/ui/OptionsMenu.lua).
function Profile.target(get, options)
  if get("enabled") == false then return {} end

  local wanted = {}
  if get("sideways") == "wide" then
    for key, value in pairs(Profile.WIDE) do wanted[key] = value end
  else
    for _, setting in ipairs(Profile.SETTINGS) do
      local value = engineValue(setting, get(setting.key))
      if value ~= nil and value ~= "same" then wanted[setting.option] = value end
    end
  end

  if wanted.battleHud == "extended" then
    local layout = wanted.battleLayout
    if layout == nil then layout = (options or {}).battleLayout end
    if layout ~= "wide" then wanted.battleHud = "standard" end
  end
  return wanted
end

-- Move the live options from what is on them now to `wanted`, and say which
-- engine keys were touched.
--
-- Three tables carry the state between calls:
--
--   options  the engine's own, mutated in place
--   held     engine key -> { value = the upright value }, for every key this
--            feature is currently holding.  Boxed rather than stored flat so
--            that "there was no value here" survives the round trip.
--   applied  engine key -> the value this feature last wrote
--
-- `applied` is what a wanted value is compared against, never the live
-- option.  That is the difference between a profile and a lock: change BATTLE
-- LAYOUT on the engine's own OPTION screen while the phone is sideways and it
-- stays changed, because this only writes when the profile itself changes or
-- the phone turns.  Turning the phone back still restores what was on it
-- upright, which is what `held` is for.
function Profile.reconcile(wanted, options, held, applied)
  local touched = {}

  for key, box in pairs(held) do
    if wanted[key] == nil then
      options[key] = box.value
      held[key] = nil
      applied[key] = nil
      touched[key] = true
    end
  end

  for key, value in pairs(wanted) do
    if applied[key] ~= value then
      if held[key] == nil then held[key] = { value = options[key] } end
      options[key] = value
      applied[key] = value
      touched[key] = true
    end
  end

  return touched
end

return Profile
