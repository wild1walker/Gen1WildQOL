-- Feature 1: the low-HP battle siren beeps once instead of looping forever.
--
-- Vanilla mirrors audio/low_health_alarm.asm: while the player's HP bar is
-- red, every battle frame calls Sound.startLoop("Low_Health_Alarm"), so the
-- two-tone siren runs continuously until the mon heals, faints, or the
-- battle ends.  The engine routes that decision through the
-- `battle.low_health_alarm` hook, whose `ctx.on` mirrors the toggle
-- (src/battle/BattleState.lua and src/ui/gen2/BattleState.lua -- same hook
-- name and same ctx keys, so one wrapper covers Red/Blue/Yellow and Gold).
--
-- So this never touches the audio system: it reshapes `ctx.on` and lets the
-- engine's own vanilla closure start and stop the loop.  With the mod
-- installed and the row on VANILLA, the alarm is byte-for-byte what it was.

local Alarm = {}

-- The player's current HP, for the "beep again on the next hit" rule.  Two
-- shapes because the two engines model the battler differently; anything
-- else answers nil and the retrigger rule simply stays inert rather than
-- guessing.
local function playerHp(ctx)
  local screen = ctx.battle
  if type(screen) ~= "table" then return nil end
  -- Gen 1: the hook's `battle` IS the BattleState, whose player battler
  -- carries the live Pokemon record.
  local battler = screen.player
  if type(battler) == "table" and type(battler.mon) == "table"
      and type(battler.mon.hp) == "number" then
    return battler.mon.hp
  end
  -- Gen 2: the hook's `battle` is the battle screen and the model hangs off
  -- it (src/ui/gen2/BattleState.lua lowHealthAlarmActive reads it the same
  -- way).
  local model = screen.battle
  if type(model) == "table" and type(model.player) == "table"
      and type(model.player.hp) == "number" then
    return model.player.hp
  end
  return nil
end

-- Exposed for the suite: one wrapper, driven with a plain ctx table.
function Alarm.newWrapper(opt, cycleFrames)
  cycleFrames = cycleFrames or 30
  -- `armed` means "this activation has already been given its beeps".
  local state = { armed = false, frames = 0, hp = nil, screen = nil }

  local function rearm()
    state.armed, state.frames = false, 0
  end

  local wrapper = function(nextFn, ctx)
    if type(ctx) ~= "table" then return nextFn(ctx) end

    local mode = opt("alarm_mode")
    if mode == "vanilla" then
      rearm()
      state.hp, state.screen = nil, nil
      return nextFn(ctx)
    end

    -- The siren is off: the engine is between activations (healed, fainted,
    -- switched, battle over).  Reset so the next time HP enters the red is
    -- a fresh beep.
    if not ctx.on then
      rearm()
      state.hp = nil
      return nextFn(ctx)
    end

    -- A different battle (or a re-entered screen) is a fresh activation
    -- even if the siren never turned off in between.
    if ctx.battle ~= state.screen then
      state.screen = ctx.battle
      rearm()
      state.hp = nil
    end

    local hp = playerHp(ctx)
    if state.armed and opt("alarm_retrigger")
        and hp and state.hp and hp < state.hp then
      -- Took another hit while still in the red: that is exactly the moment
      -- a player expects the beep, so give it one more.
      rearm()
    end
    if hp then state.hp = hp end

    if not state.armed then
      state.armed = true
      state.frames = 0
    end

    state.frames = state.frames + 1
    local cycles = (mode == "cycles") and (opt("alarm_cycles") or 1) or 1
    if state.frames > cycleFrames * cycles then
      -- Budget spent: hand vanilla an "off" and it stops the loop, while
      -- the engine's own wLowHealthAlarm latch stays exactly where it was.
      ctx.on = false
    end

    return nextFn(ctx)
  end

  return wrapper, state
end

function Alarm.install(mod, opt, cycleFrames)
  local wrapper, state = Alarm.newWrapper(opt, cycleFrames)
  mod.hooks:wrap("battle.low_health_alarm", wrapper)
  return state
end

return Alarm
