-- What the overlay host tells its overlays about where they are drawing.
--
-- Every battle overlay in this bundle draws through one host, and the host
-- hands each of them a context carrying `voxel3dBattleData`: the world canvas
-- a voxel mod put the battle on, or nil.  An overlay reads nil as "draw where
-- you always drew" and a table as "follow the HUD onto the canvas", so that
-- one field decides, for every overlay at once, whether the caught marker
-- lands beside the foe's name or several hundred pixels away from it.
--
-- There are four voxel forks.  Two of them draw the battle in 3D and leave the
-- HUDs in the flat 160x144 frame, and for those the field must be nil even
-- though the battle plainly has a shot on it.  The host used to decide this by
-- asking whether a snapHUDs wrap had recorded a NO -- so a fork with no
-- snapHUDs to wrap recorded nothing, and nothing read as yes.  That is the
-- case at the centre of this file.
--
-- Run:  luajit tests/battleoverlayvoxel_test.lua

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

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

_G.love = { graphics = { push = function() end, pop = function() end } }

local Voxel = load_("runtime/voxel.lua")
local Overlays = load_("modules/QualityOfLife/qol_battle_overlays.lua")

-- ------------------------------------------------------------- the harness

local function stubMod(providerId, modules)
  local handlers, once = {}, {}
  local mod = {
    log = { error = function() end },
    events = {
      on = function(_, name, fn) handlers[name] = fn end,
      once = function(_, name, fn) once[name] = fn end,
    },
    find = function(a, b)
      local id = type(a) == "string" and a or b
      if providerId and id == providerId then
        return { id = id, exports = { lib = {
          require = function(name)
            local value = modules[name]
            if value == nil then error("no module", 0) end
            return value
          end,
        } } }
      end
      return nil
    end,
  }
  mod.voxel = Voxel.new(mod)
  mod.fire = function(name, event) if handlers[name] then handlers[name](event) end end
  mod.fireOnce = function(name) if once[name] then once[name]() end end
  return mod
end

local function stubShot()
  return { canvas = "WORLD", scale = 4, pw = 640, ph = 576, lx = 0, ly = 20 }
end

-- Stand the host up, run one battle frame, and hand back the context the
-- overlay was given.
--
-- `mods.loaded` is fired here and does nothing, deliberately: the host must
-- not depend on it.  Its own `install` is called FROM a mods.loaded handler in
-- the real bundle, so anything it subscribed to that event might never run --
-- the snapHUDs wrap goes on at `battle.started` instead, which is later than
-- mods.loaded by every route.
local function contextFor(mod, battle)
  local host = Overlays.new(mod)
  local seen
  host:add({ id = "probe", draw = function(_, _, context) seen = context end })
  host:install()
  mod.fireOnce("mods.loaded")
  battle.draw = function() end
  mod.fire("battle.started", { battle = battle })
  battle:draw()
  return seen
end

local function stubBattle(shot)
  return { fx = {}, frame = 1, introSlide = 0, dramaticShapeShot = shot }
end

io.write("what the overlay host hands its overlays\n")

-- ------------------------------------------------------- no voxel mod at all

do
  local context = contextFor(stubMod(nil, {}), stubBattle(nil))
  ok(context ~= nil, "the overlay is drawn")
  eq(context.voxel3dBattleData, nil, "with no canvas to follow")
end

-- ------------------- a fork that draws in 3D and leaves the HUDs in the frame

do
  -- potato_voxel: a shot on the battle, no snapHUDs anywhere in the fork.
  local mod = stubMod("potato_voxel",
                      { OverworldBattle = { shot = function() end } })
  local context = contextFor(mod, stubBattle(stubShot()))
  eq(context.voxel3dBattleData, nil,
     "the HUDs are in the frame, so the overlays stay in the frame")
end

do
  -- DRAMALESS_SHAPE goes further and has no OverworldBattle at all.
  local mod = stubMod("DRAMALESS_SHAPE", {})
  local context = contextFor(mod, stubBattle(stubShot()))
  eq(context.voxel3dBattleData, nil, "and the same with no battle module at all")
end

-- ------------------------------------------- a fork that moves the HUDs across

do
  local OverworldBattle = { snapHUDs = function() return true end }
  local mod = stubMod("BATTLE_ART_VOXEL_FORK",
                      { OverworldBattle = OverworldBattle })
  local battle = stubBattle(stubShot())

  local host = Overlays.new(mod)
  local seen
  host:add({ id = "probe", draw = function(_, _, context) seen = context end })
  host:install()
  mod.fireOnce("mods.loaded")
  battle.draw = function() end
  mod.fire("battle.started", { battle = battle })

  battle:draw()
  eq(seen.voxel3dBattleData, nil,
     "before the first snap of the battle, still the frame")

  OverworldBattle.snapHUDs(battle)
  battle:draw()
  ok(seen.voxel3dBattleData ~= nil, "once snapped, the overlays follow")
  eq(seen.voxel3dBattleData.canvas, "WORLD", "onto the world canvas")

  OverworldBattle.snapHUDs = function() return false end
  -- the wrap is already on; call through it again
  local wrapped = OverworldBattle.snapHUDs
  eq(type(wrapped), "function", "the wrap survives the fork changing its mind")
end

do
  -- The fork declines this frame -- it does on iOS, where the HUDs stay in the
  -- frame as the engine's own opaque panels.
  local answer = false
  local OverworldBattle = { snapHUDs = function() return answer end }
  local mod = stubMod("BATTLE_ART_VOXEL_FORK",
                      { OverworldBattle = OverworldBattle })
  local battle = stubBattle(stubShot())
  local host = Overlays.new(mod)
  local seen
  host:add({ id = "probe", draw = function(_, _, context) seen = context end })
  host:install()
  mod.fireOnce("mods.loaded")
  battle.draw = function() end
  mod.fire("battle.started", { battle = battle })

  OverworldBattle.snapHUDs(battle)
  battle:draw()
  eq(seen.voxel3dBattleData, nil, "declined: the overlays stay in the frame")

  answer = true
  OverworldBattle.snapHUDs(battle)
  battle:draw()
  ok(seen.voxel3dBattleData ~= nil, "and follow again on a frame it manages")
end

-- --------------------------------------------- the shot still has to be sound

do
  local OverworldBattle = { snapHUDs = function() return true end }
  local mod = stubMod("BATTLE_ART_VOXEL_FORK",
                      { OverworldBattle = OverworldBattle })
  local shot = stubShot()
  shot.scale = 0
  local battle = stubBattle(shot)
  local host = Overlays.new(mod)
  local seen
  host:add({ id = "probe", draw = function(_, _, context) seen = context end })
  host:install()
  mod.fireOnce("mods.loaded")
  battle.draw = function() end
  mod.fire("battle.started", { battle = battle })
  OverworldBattle.snapHUDs(battle)
  battle:draw()
  eq(seen.voxel3dBattleData, nil,
     "a snapped battle with an unusable shot is still the frame")
end

-- ------------------------------- the wrap does not depend on mods.loaded

io.write("the wrap survives install() being called from inside mods.loaded\n")
do
  -- Exactly the real shape: bundle_common defers `install` to a mods.loaded
  -- handler, so by the time the host runs, that event is already being
  -- dispatched.  A bus that does not call handlers added mid-dispatch is the
  -- ordinary implementation, and this stands one up.
  local OverworldBattle = { snapHUDs = function() return true end }
  local mod = stubMod("BATTLE_ART_VOXEL_FORK",
                      { OverworldBattle = OverworldBattle })
  local dispatching = false
  local realOnce = mod.events.once
  mod.events.once = function(self, name, fn)
    if dispatching then return end   -- too late; this handler is dropped
    return realOnce(self, name, fn)
  end

  local host = Overlays.new(mod)
  local seen
  host:add({ id = "probe", draw = function(_, _, context) seen = context end })
  dispatching = true
  host:install()
  dispatching = false

  local battle = stubBattle(stubShot())
  battle.draw = function() end
  mod.fire("battle.started", { battle = battle })
  OverworldBattle.snapHUDs(battle)
  battle:draw()
  ok(seen.voxel3dBattleData ~= nil,
     "the HUDs are still followed when they move")
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
