-- Exp Share, fitted into the bundle.
--
-- Two things need doing that the upstream mod cannot do for itself, and both
-- are here rather than in a patch against its source, so a sync brings the
-- next version in cleanly.
--
-- 1. The default.  Upstream stores its mode in the save's own options table
--    (save.options.expShare) rather than in mod options, so there is no schema
--    row whose default the bundle could set: an unset field simply reads as
--    OFF.  The bundle ships GEN 5+ instead, which is the modern behaviour and
--    the reason most players install this at all -- the fighters keep their
--    full experience and the bench gains alongside them.  It is seeded once,
--    on a save that has never carried the field.  A player who picks OFF is
--    picking a stored value, and is never overwritten.
--
-- 2. Where it is configured.  Upstream appends three rows to the engine's
--    OPTIONS screen.  Inside a bundle whose whole premise is one row per
--    feature, that would put EXP SHARE in two places and neither of them next
--    to its own switch, so the registration is suppressed (in features.lua)
--    and the same rows are rebuilt here, on the bundle's EXP SHARE screen,
--    driven by the exports upstream already publishes.

local Adapter = {}

local DEFAULT_MODE = "gen5"

-- Every mode upstream understands.  A stored value outside this set is treated
-- as unset, so a save written by some future version that has been rolled back
-- is seeded rather than left in a mode this build cannot cycle out of.
local KNOWN = {
  off = true, gen1 = true, gen5 = true,
  balanced = true, average = true, custom = true,
}

function Adapter.install(mod, context, feature)
  local exports = mod.exports

  -- ---- 1. seed the default

  local function seed(game)
    local options = game and game.save and game.save.options
    if type(options) ~= "table" then return end
    if KNOWN[options.expShare] then return end
    options.expShare = DEFAULT_MODE
    if type(game.writeOptions) == "function" then
      pcall(function() game:writeOptions() end)
    elseif type(game.persistOptions) == "function" then
      pcall(function() game:persistOptions() end)
    end
    mod.log:info("seeded EXP SHARE to %s on a save that had no setting", DEFAULT_MODE)
  end

  local function seedFrom(event)
    seed(event and event.game)
  end

  mod.events:on("game.ready", seedFrom)
  mod.events:on("save.loaded", seedFrom)
  mod.events:on("save.created", seedFrom)

  -- ---- 2. the rows, on the bundle's own screen
  --
  -- `value` and `step` are upstream's own: the bundle never reaches into the
  -- save itself, so cycling a row here does exactly what cycling it on the
  -- OPTIONS screen used to.  PERCENT SLOT and PERCENT are only meaningful in
  -- CUSTOM, and say so by disappearing outside it -- the same thing upstream's
  -- syncCustomOptionRows does to its own rows.

  local function callable(name)
    return type(exports[name]) == "function"
  end

  context.customRows[feature.id] = function()
    local rows = {}

    if callable("labelOf") and callable("cycle") then
      rows[#rows + 1] = {
        id = "exp_share_mode",
        label = "EXP SHARE",
        description = "OFF IS VANILLA. GEN 5+ KEEPS THE FIGHTERS WHOLE AND GIVES THE BENCH HALF A SHARE EACH.",
        value = function(game) return exports.labelOf(game) end,
        step = function(game, dir) return exports.cycle(game, dir) end,
      }
    end

    if callable("percentSlotLabel") and callable("cyclePercentSlot") then
      rows[#rows + 1] = {
        id = "exp_share_percent_slot",
        label = "PERCENT SLOT",
        description = "ALL EDITS THE SHARED PERCENTAGE. A SLOT NUMBER EDITS THAT ONE POKEMON'S OVERRIDE.",
        value = function(game) return exports.percentSlotLabel(game) end,
        step = function(game, dir) return exports.cyclePercentSlot(game, dir) end,
        visible = function(game) return exports.modeOf(game) == "custom" end,
      }
    end

    if callable("percentLabel") and callable("cyclePercent") then
      rows[#rows + 1] = {
        id = "exp_share_percent",
        label = "PERCENT",
        description = "HOW MUCH OF A FIGHTER'S SHARE EACH BENCH POKEMON GETS.",
        value = function(game) return exports.percentLabel(game) end,
        step = function(game, dir) return exports.cyclePercent(game, dir) end,
        visible = function(game) return exports.modeOf(game) == "custom" end,
      }
    end

    if callable("slotLabel") and callable("cycleSlot") then
      rows[#rows + 1] = {
        id = "exp_share_single",
        label = "SINGLE SHARE",
        description = "ALL SHARES WITH THE WHOLE BENCH. A SLOT NUMBER SHARES WITH ONLY THAT POKEMON.",
        value = function(game) return exports.slotLabel(game) end,
        step = function(game, dir) return exports.cycleSlot(game, dir) end,
      }
    end

    if callable("jingleLabel") and callable("cycleJingle") then
      rows[#rows + 1] = {
        id = "exp_share_jingle",
        label = "LEVEL UP SOUND",
        description = "THE LONG LEVEL-UP FANFARE, OR THE SHORT ITEM PICKUP CHIME.",
        value = function(game) return exports.jingleLabel(game) end,
        step = function(game, dir) return exports.cycleJingle(game, dir) end,
      }
    end

    return rows
  end
end

return Adapter
