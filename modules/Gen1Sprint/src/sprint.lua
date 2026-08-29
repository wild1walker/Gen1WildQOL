-- The whole mod: one link on the engine's `movement.speed` hook.
--
-- Gen1Recomp already has the seam this needs.  Player:stepLength picks the
-- duration of a step -- 16 frames walking, 8 on the BICYCLE -- and then
-- offers that number to mods before returning it, with the comment
-- "movement.speed lets a mod multiply or replace that (running shoes, dash,
-- etc.)".  Running shoes is exactly what this is, so there is nothing to
-- patch, override or re-implement: the mod answers a question the engine
-- was already asking.
--
-- Two independent things come out of that one link:
--
--   * the SPRINT, which shortens a step while its button is held, and
--   * the BIKE SPEED, which shortens every step taken on the bicycle
--     whether or not anything is held at all.
--
-- They stack, in that order, and either can be switched off without the
-- other noticing.
--
-- WHY THIS DOES NOT COST FRAMES, since a speed mod is an easy place to make
-- the game stutter:
--
--   * stepLength is called once per STEP, from Player:tryMove as the step
--     begins -- never per frame.  Walking, that is once every 16 frames;
--     riding, once every four to eight.  A handful of calls a second while
--     the player is moving, and none at all while they stand still, sit in
--     a menu, or fight a battle.
--   * The call site is guarded by Runtime.wantsHook("movement.speed"), which
--     is one table lookup, and the ctx table is only built when some mod is
--     subscribed.  So a mod with nothing to say unsubscribes (see
--     Sprint.install) rather than returning early: with the chain empty the
--     engine allocates nothing, and the mod turned all the way off costs
--     precisely what the mod uninstalled does.
--   * The link itself does a few table reads, one comparison per gate and
--     at most two divides.  It allocates nothing: the settings table is one
--     this closure already owns, and the ctx is the engine's, forwarded
--     rather than copied.
--
-- The follower comes along on its own -- PikachuFollower copies the player's
-- live stepFramesCur onto itself every step -- and the walk-cycle clock is
-- deliberately independent of step length in Player:update, so legs keep a
-- constant cadence and a shortened step reads as covering more ground per
-- stride rather than as an animation played at double speed.  That is the
-- same thing the BICYCLE has always done here.

local Sprint = {}

Sprint.HOOK = "movement.speed"

-- The option rows, flattened to the plain values the hot path reads.
-- Rebuilt only when mod.options_changed says something moved.
function Sprint.snapshot(opt, multipliers)
  return {
    sprint   = opt("enabled") and true or false,
    button   = opt("button"),
    mult     = multipliers[opt("speed")] or 2,
    bikeMult = multipliers[opt("bike_speed")] or 1,
    surf     = opt("surf") and true or false,
    bike     = opt("bike") and true or false,
  }
end

-- True when the settings would change at least one step somewhere.  What
-- Sprint.install subscribes on, and the reason BIKE SPEED alone is enough to
-- keep the link on the chain with SPRINT switched off.
function Sprint.wouldActOn(cfg)
  return cfg.sprint or cfg.bikeMult ~= 1
end

-- Whether a SCRIPT is walking the player rather than the player walking.
--
-- Sprinting is a thing you do by pressing a direction.  A cutscene walk is not
-- that: the escort out of Pallet Town, a warp's step through a door, a trainer
-- marching you into place.  The engine drives those through scriptMoves and
-- asks stepLength for their duration exactly as it does for a real step, so
-- without this a held B shortened them too.
--
-- Which was not just unfaithful, it desynchronised the one cutscene that
-- reads the player's live speed.  story2.lua's Oak escort pins his walk to
-- yours once, at the top -- `oak.stepFrames = ow.player.stepFramesCur` -- and
-- then drives the pair off the PLAYER's completion.  Sprint made that number
-- input-dependent, so Oak could be left running at double the speed the
-- player was actually walking: he finished each step in half the time and
-- then stood waiting for you.  Step, pause, step, pause, the whole way to the
-- lab.
--
-- Asked through mod.world, which is the supported way to reach the live
-- overworld, and answered false whenever there is no overworld to ask -- the
-- title screen, a battle, a stub in a test.  Only the PLAYER's own scripted
-- moves count: an NPC walking somewhere else on the map is not this.
local function scriptWalking(world, player)
  if not (world and player) then return false end
  local ok, ow = pcall(function() return world:overworld() end)
  if not ok or type(ow) ~= "table" then return false end
  for _, mv in ipairs(ow.scriptMoves or {}) do
    if mv.entity == player then return true end
  end
  return false
end

-- `read` is a zero-argument function returning the current snapshot.
-- `world` is mod.world, or nil where there is none to ask.
function Sprint.newWrapper(read, world)
  return function(next, frames, ctx)
    -- Whatever this hands `next` REPLACES the argument list for the whole
    -- rest of the chain (src/mods/Hooks.lua nextFn), so ctx is passed along
    -- on every path including the ones that change nothing.  Returning
    -- `next(frames)` alone would hand the mod after this one a nil context.
    if type(frames) ~= "number" or type(ctx) ~= "table" then
      return next(frames, ctx)
    end

    -- Mid-ledge-hop nothing is shortened, sprint or bicycle.  pokered skips
    -- DoBikeSpeedup while BIT_LEDGE_OR_FISHING is set, and Player:stepLength
    -- ports that by forcing onBike false for the hop.  The hop arc is drawn
    -- against the step's own progress, so shortening the step mid-air lands
    -- the sprite early and reads as a teleport.  Stand down on exactly the
    -- frames vanilla does.
    local player = ctx.player
    if player and player.ledgeHop then return next(frames, ctx) end

    -- a script is walking you: this step is the game's, not yours
    if scriptWalking(world, player) then return next(frames, ctx) end

    local cfg = read()
    local out = frames

    -- ------- 1. the bicycle's own speed, held or not

    if ctx.onBike and cfg.bikeMult ~= 1 then
      out = out / cfg.bikeMult
    end

    -- ------- 2. the sprint, on top, while its button is down

    if cfg.sprint then
      local input = ctx.input
      if input and input.isDown and input:isDown(cfg.button) then
        -- Where the sprint stands down.  Both rows default OFF, which is the
        -- FireRed answer: running shoes are a thing you do on foot.
        local applies = true
        if ctx.surfing and not cfg.surf then applies = false end
        if ctx.onBike and not cfg.bike then applies = false end
        if applies then out = out / cfg.mult end
      end
    end

    if out == frames then return next(frames, ctx) end

    -- Floored once at the end rather than after each divide: two roundings
    -- compound, and a 1.5x bike under a 1.5x sprint should land on the step
    -- the arithmetic says it should.  Fewer frames per tile is more speed,
    -- and one frame is the floor however the rows are set.
    return next(math.max(1, math.floor(out)), ctx)
  end
end

-- Wire the link to the live game.  Returns the handle published as
-- mod.exports.sprint.
function Sprint.install(mod, opt, multipliers)
  local cached = nil
  local function read()
    if not cached then cached = Sprint.snapshot(opt, multipliers) end
    return cached
  end

  local wrapper = Sprint.newWrapper(read, mod.world)
  local unwrap = nil

  -- A mod with nothing to say leaves the chain rather than short-circuiting
  -- inside it; see the note at the top of this file for why that is worth
  -- the handful of lines.  "Nothing to say" is both rows inert, not just
  -- SPRINT: OFF -- a player running BIKE SPEED alone still needs the link.
  local function sync()
    cached = nil
    local want = Sprint.wouldActOn(read())
    if want and not unwrap then
      unwrap = mod.hooks:wrap(Sprint.HOOK, wrapper)
    elseif not want and unwrap then
      unwrap()
      unwrap = nil
    end
  end

  sync()

  -- The manager writes an option and broadcasts; nothing polls.  A payload
  -- naming another mod is ignored, and one naming nothing at all is taken
  -- as "something changed", which is the safe reading.
  mod.events:on("mod.options_changed", function(ev)
    if type(ev) == "table" and ev.mod ~= nil and ev.mod ~= mod.id then return end
    sync()
  end)

  return {
    -- Is the sprint engaged right now?  For a neighbouring mod that wants
    -- to draw or sound something while the player is running.  False while
    -- SPRINT is off even though the link may still be on the chain for the
    -- bicycle's sake.
    active = function(game)
      local cfg = read()
      if not cfg.sprint then return false end
      local input = game and game.input
      if not input or not input.isDown then return false end
      return input:isDown(cfg.button) and true or false
    end,
    -- The live settings, copied: a caller cannot reach in and edit them.
    settings = function()
      local cfg, out = read(), {}
      for key, value in pairs(cfg) do out[key] = value end
      return out
    end,
    -- What this mod would turn `frames` into for that ctx.  The suite drives
    -- it, and it is the honest answer to "how fast am I actually going".
    stepFrames = function(frames, ctx)
      local seen
      wrapper(function(value) seen = value end, frames, ctx)
      return seen
    end,
  }
end

return Sprint
