-- Walking off the edge of one route and onto the next, with a follower.
--
-- Crossing an edge is not a map ENTRY.  Nothing loads and nothing warps: the
-- world swaps its map data underneath a step that is still running, which is
-- why `World:tryConnection` passes `{ seamless = true }` and parks the player
-- one cell short of the landing so the same world pixels stay on screen.
--
-- Red does the follower's half of that in three lines
-- (src/world/OverworldController.lua:1956-1971): take the LIVE follower, hand
-- it through setMap as `keepPikachu` so it is adopted rather than re-spawned,
-- and `rebase` it -- and the cell it is chasing -- by the translation the
-- player just took.
--
-- Gold's tryConnection does none of the three, so setMap reached
-- `Follower.onMapEntered(..., viaMapLoad = true)`, whose whole meaning is "a
-- fresh load parks it under the player".  The follower vanished and reappeared
-- standing ON the player at every seam.
--
-- Both engine parts already exist and neither had a caller: `Follower.rebase`
-- is written for exactly this, and `onMapEntered` already honours
-- `opts.keepFollower`.  So this file drives the SHIPPED wraps over a World
-- shaped like Gold's and asserts the three things Red does.
--
-- Run:  luajit tests/followerseam_test.lua

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
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

-- ---- Gold's World and Follower, reduced to what the seam touches

local seen = {}

local Follower = {
  current = function(world) return world.follower end,
  -- The engine's own rebase, copied in shape: the follower AND the cell it is
  -- chasing both slide by the seam's delta.
  rebase = function(world, dx, dy)
    seen[#seen + 1] = { what = "rebase", dx = dx, dy = dy }
    local npc = world.follower
    if npc then
      npc.cellX, npc.cellY = npc.cellX + dx, npc.cellY + dy
      npc.px, npc.py = npc.px + dx * 16, npc.py + dy * 16
    end
    local trail = world.followerTrail
    if trail then trail.x, trail.y = trail.x + dx, trail.y + dy end
  end,
  -- setMap's tail.  viaMapLoad is TRUE for every load on Gold, connection
  -- included, which is the whole bug: without a keepFollower it destroys the
  -- follower and re-spawns it on the player's own cell.
  onMapEntered = function(_game, world, opts, viaMapLoad)
    local keep = opts and (opts.keepFollower or opts.keepPikachu)
    if keep then
      seen[#seen + 1] = { what = "adopted" }
      world.follower = keep
      return
    end
    seen[#seen + 1] = { what = "respawned" }
    local p = world.player
    local x, y = p.cellX, p.cellY
    if not viaMapLoad then x, y = p.cellX, p.cellY - 1 end
    world.follower = { cellX = x, cellY = y, px = x * 16, py = y * 16 }
    world.followerTrail = { x = p.cellX, y = p.cellY }
  end,
}
package.loaded["src.world.PikachuFollower"] = Follower

local World = {}
World.setMap = function(world, mapId, cx, cy, facing, opts)
  world.mapId = mapId
  world.player.cellX, world.player.cellY = cx, cy
  Follower.onMapEntered(nil, world, opts, true)
end
-- The cart's own crossing: swap the map at the LANDING cell, then park the
-- player one cell before it and keep the step running.
World.tryConnection = function(world, dir)
  local conn = world.connections[dir]
  if not conn then return false end
  World.setMap(world, conn.mapId, conn.x, conn.y, dir, { seamless = true })
  local d = ({ up = { 0, -1 }, down = { 0, 1 },
               left = { -1, 0 }, right = { 1, 0 } })[dir]
  local p = world.player
  p.cellX, p.cellY = conn.x - d[1], conn.y - d[2]
  p.px, p.py = p.cellX * 16, p.cellY * 16
  p.moving = true
  return true
end
package.loaded["src.world.gen2.World"] = World

-- ---- the shipped wraps, lifted out of the module
--
-- Read rather than retyped, so an edit that drops the fix fails here instead
-- of passing against a copy of the old code.

local function shipped()
  local handle = assert(io.open("modules/Gen1Follower/main.lua"))
  local source = handle:read("*a")
  handle:close()
  local body = source:match(
    "(  local function installGen2SeamlessFollow%(%).-\n  end)\n")
  assert(body, "could not find installGen2SeamlessFollow in the module")
  return assert(load(
    "local PikachuFollower = ...\n" .. body
      .. "\nreturn installGen2SeamlessFollow", "@Gen1Follower"))(Follower)
end

local install = shipped()
eq(install(), true, "the seam arm installs on Gold")
eq(install(), true, "and a second install is a no-op")

-- ---- a route crossing

local function scene()
  seen = {}
  local world = {
    mapId = "ROUTE_29",
    player = { cellX = 5, cellY = 10, px = 80, py = 160 },
    connections = { right = { mapId = "ROUTE_30", x = 0, y = 12 } },
  }
  -- one cell behind the player, which is where a follower walks
  world.follower = { cellX = 4, cellY = 10, px = 64, py = 160 }
  world.followerTrail = { x = 5, y = 10 }
  return world
end

do
  local world = scene()
  local before = world.follower
  eq(World.tryConnection(world, "right"), true, "the crossing happens")

  -- 1. the SAME follower crossed; it was not destroyed and rebuilt
  eq(world.follower, before, "the live follower crossed the seam")
  local kinds = {}
  for _, e in ipairs(seen) do kinds[#kinds + 1] = e.what end
  eq(table.concat(kinds, ","), "adopted,rebase",
     "it was adopted through setMap and then rebased -- never re-spawned")

  -- 2. it is still exactly one cell behind, in the NEW map's frame
  local p = world.player
  eq(p.cellX, -1, "the player is parked one cell before the landing")
  eq(world.follower.cellX, p.cellX - 1,
     "and the follower is still one cell behind them")
  eq(world.follower.cellY, p.cellY, "on the same row")

  -- 3. the cell it is chasing came with it
  eq(world.followerTrail.x, p.cellX,
     "the cell it is walking toward slid by the same delta")
  eq(world.followerTrail.y, p.cellY, "on both axes")

  -- and the pixels line up with the cells, so nothing jumps on the next frame
  eq(world.follower.px, world.follower.cellX * 16, "its pixels match its cell")
  eq(world.follower.py, world.follower.cellY * 16, "on both axes")
end

-- ---- the delta is the player's own translation, whichever way you leave

do
  local world = scene()
  world.connections = { up = { mapId = "ROUTE_31", x = 5, y = 40 } }
  -- behind a player walking UP is one cell BELOW them
  world.follower = { cellX = 5, cellY = 11, px = 80, py = 176 }
  world.followerTrail = { x = 5, y = 10 }
  World.tryConnection(world, "up")
  local p = world.player
  eq(world.follower.cellY, p.cellY + 1,
     "crossing a top edge keeps the follower behind on the y axis")
  eq(world.follower.cellX, p.cellX, "and in the same column")
end

-- Whatever the offset was, it is what comes out the other side: the rebase is
-- a translation, not a re-placement, so a follower caught mid-step or standing
-- off to one side crosses looking exactly as it did.

do
  local world = scene()
  world.follower = { cellX = 3, cellY = 8, px = 48, py = 128 }
  local dx = world.follower.cellX - world.player.cellX
  local dy = world.follower.cellY - world.player.cellY
  World.tryConnection(world, "right")
  local p = world.player
  eq(world.follower.cellX - p.cellX, dx, "the offset to the player survives")
  eq(world.follower.cellY - p.cellY, dy, "on both axes")
end

-- ---- an edge with nothing on the other side changes nothing

do
  local world = scene()
  local before = { x = world.follower.cellX, y = world.follower.cellY }
  eq(World.tryConnection(world, "left"), false, "there is no connection left")
  eq(world.follower.cellX, before.x, "so the follower is not translated")
  eq(world.follower.cellY, before.y, "on either axis")
  eq(#seen, 0, "and nothing was adopted or rebased")
end

-- ---- a save with no follower still crosses

do
  local world = scene()
  world.follower = nil
  world.followerTrail = nil
  eq(World.tryConnection(world, "right"), true, "the crossing still happens")
  ok(true, "and nothing errored on the way through")
end

-- ---- every OTHER map load still takes the engine's own path
--
-- The adoption is armed only for the length of one tryConnection call, so a
-- door, a warp or the boot re-spawns exactly as the cart does.

do
  local world = scene()
  seen = {}
  World.setMap(world, "ELMS_LAB", 3, 4, "down", { seamless = true })
  local kinds = {}
  for _, e in ipairs(seen) do kinds[#kinds + 1] = e.what end
  eq(table.concat(kinds, ","), "respawned",
     "a seamless load that is NOT a crossing is left to the engine")
end

do
  local world = scene()
  seen = {}
  World.setMap(world, "ELMS_LAB", 3, 4, "down", {})
  local kinds = {}
  for _, e in ipairs(seen) do kinds[#kinds + 1] = e.what end
  eq(table.concat(kinds, ","), "respawned", "and so is an ordinary warp")
end

-- ---- a follower somebody else already named is not overruled

do
  local world = scene()
  seen = {}
  local theirs = { cellX = 99, cellY = 99, px = 0, py = 0 }
  World.setMap(world, "ROUTE_30", 0, 12, "right",
               { seamless = true, keepFollower = theirs })
  eq(world.follower, theirs, "another caller's keepFollower is respected")
end

io.write(("followerseam: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
