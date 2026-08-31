-- Headless coverage of the off-canvas cull in the follower's sprite draw.
--
-- The bug: map POKeMON rendered in the black margin ABOVE the game screen.
-- Measured off a capture, the two strays sat at world y -16 and -31 -- two
-- and four tiles above the top of a 144-tall canvas -- at exactly
-- `worldOrigin + y * scale`, which is the transform of one specific path.
--
-- That path is the POST-ZONE REDRAW.  For an unscaled follower this mod does
-- not draw into the world canvas at all: it queues the sprite with
-- PaletteFX.markSpriteRedraw, and the renderer replays it in SCREEN space
-- after the world blit.  It is the one draw in the game that skips the
-- canvas, so it is the one that does not get the canvas's clipping either --
-- and the renderer's scissor on that replay is the UI's rect, not the
-- world's, which on a portrait phone is the taller of the two.
--
-- 0.10.0 culled the cells that were ENTIRELY off the canvas.  That was half a
-- fix and this file now covers the other half: a cell STRADDLING the edge is
-- not entirely off, so it was still queued and the replay still drew all
-- sixteen of its rows.  The one in the second capture had its art at world y
-- -9 to 0 -- hanging over the edge by nine pixels, exactly the case a cull
-- cannot reach.
--
-- So three bounds are checked here rather than one: entirely off (drop it),
-- wholly on (queue it), and straddling (draw it into the canvas instead,
-- which clips).  Plus the rule that decides whether the replay is wanted at
-- all, and the arithmetic that makes the fall-through draw the same pixels
-- the queue would have.
--
-- Run:  luajit tests/followercull_test.lua

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

-- ------- the cull, as the mod spells it
--
-- Lifted rather than loaded: modules/Gen1Follower/main.lua is 1700 lines that
-- want a whole engine to load against, and the rule under test is eight of
-- them.  tools/check.py compares the two so they cannot drift.
local function cullFor(worldCanvas)
  local rendererModule
  return function(x, y)
    if rendererModule == nil then
      local ok_, found = pcall(function() return { worldCanvas = worldCanvas } end)
      rendererModule = (ok_ and type(found) == "table") and found or false
    end
    if not rendererModule then return false end
    local canvas = rendererModule.worldCanvas
    if not (canvas and canvas.getDimensions) then return false end
    local ok_, w, h = pcall(canvas.getDimensions, canvas)
    if not (ok_ and type(w) == "number" and type(h) == "number") then
      return false
    end
    return x + 16 <= 0 or y + 16 <= 0 or x >= w or y >= h
  end
end

local function canvasOf(w, h)
  return { getDimensions = function() return w, h end }
end

io.write("a cell off the world canvas is culled\n")
do
  local off = cullFor(canvasOf(160, 144))

  -- the two the capture caught, in world-canvas pixels
  eq(off(0, -16), true, "a POKeMON two tiles above the screen")
  eq(off(64, -32), true, "and one four tiles above it")

  eq(off(-16, 40), true, "off the left edge")
  eq(off(160, 40), true, "off the right")
  eq(off(40, 144), true, "off the bottom")
end

io.write("and a cell anyone could see is not\n")
do
  local off = cullFor(canvasOf(160, 144))
  eq(off(0, 0), false, "the top-left cell")
  eq(off(144, 128), false, "the bottom-right one")
  eq(off(72, 64), false, "the middle of the screen")

  -- The edge cases are the ones a sloppier bound gets wrong: a sprite one
  -- pixel onto the screen is a sprite you can see, and cutting it is a
  -- POKeMON that pops in at the edge of the map instead of walking on.
  eq(off(-15, 40), false, "one pixel of a sprite on the left edge")
  eq(off(40, -15), false, "one pixel over the top")
  eq(off(159, 40), false, "one pixel in from the right")
  eq(off(40, 143), false, "one pixel up from the bottom")
end

io.write("the bound is the canvas, not a hardcoded screen\n")
do
  -- A zoomed-out view has a bigger canvas, and the far edges move with it: a
  -- cell at x 200 is off a 160-wide canvas and on a 320-wide one.  Culling at
  -- a hardcoded 160x144 would take those away from a player who had zoomed
  -- out to look at them.
  local narrow, wide = cullFor(canvasOf(160, 144)), cullFor(canvasOf(320, 288))
  eq(narrow(200, 200), true, "past the right edge of a 160-wide canvas")
  eq(wide(200, 200), false, "...and comfortably on a 320-wide one")
  eq(wide(320, 200), true, "off the wider canvas is still off")

  -- The NEAR edges do not move, and it is worth saying why: canvas space
  -- starts at 0 whatever the canvas is, so a wider one reaches further right
  -- and further down and never further up.  A cell at y -16 is above every
  -- canvas there is, which is what makes the strays this cull removes
  -- unreachable at any zoom rather than merely off this screen.
  eq(narrow(0, -16), true, "a cell two tiles above the top is above any canvas")
  eq(wide(0, -16), true, "...on a wider one too")
end

io.write("with no renderer to ask, nothing is culled\n")
do
  eq(cullFor(nil)(0, -16), false,
     "a build this cannot reach behaves exactly as it did before")
  eq(cullFor({})(0, -16), false, "and so does a renderer with no canvas yet")
  eq(cullFor({ getDimensions = function() error("no") end })(0, -16), false,
     "and one whose canvas raises")
end


io.write("wholly-on is a tighter bound than not-off\n")
do
  -- The two together are what sort a cell into three: off, straddling, on.
  local function wholly(w, h)
    return function(x, y)
      return x >= 0 and y >= 0 and x + 16 <= w and y + 16 <= h
    end
  end
  local on = wholly(160, 144)
  local off = cullFor(canvasOf(160, 144))

  eq(on(0, 0), true, "the top-left cell is wholly on")
  eq(on(144, 128), true, "and so is the bottom-right one")

  -- the capture's sprite: nine pixels of it over the top edge
  eq(off(0, -9), false, "a cell nine pixels over the top is not entirely off")
  eq(on(0, -9), false, "...nor is it wholly on")
  -- which is the whole point: it is in neither bucket, so it takes the
  -- canvas draw, which is the only one of the two that can cut it off
  eq(off(0, -9) == false and on(0, -9) == false, true,
     "so it straddles, and straddling is what the replay cannot handle")

  eq(on(152, 40), false, "hanging over the right edge is straddling too")
  eq(on(40, 136), false, "and over the bottom")
end

io.write("the replay is only wanted where markTrueColor is not honoured\n")
do
  -- ADVANCED is the one mode that honours a true-colour rect, so it is the
  -- one mode that does not need the replay -- and the replay is the path that
  -- cannot clip.  Everything else still takes it.
  local function needsRedraw(honors)
    if type(honors) ~= "function" then return true end
    local ok, honored = pcall(honors)
    if not ok then return true end
    return not honored
  end
  eq(needsRedraw(function() return true end), false,
     "ADVANCED marks its rectangle instead, and draws into the canvas")
  eq(needsRedraw(function() return false end), true,
     "SGB and OG RED still want the replay")
  eq(needsRedraw(nil), true, "an engine too old to be asked gets the replay")
  eq(needsRedraw(function() error("no") end), true, "and so does one that raises")
end

io.write("the fall-through draws the same pixels the queue would have\n")
do
  -- The queue draws the frame at (drawX, y) with scale sx.  The fall-through
  -- draws it anchored at (x+8, y+16) with origin (8, 16).  At scale 1 those
  -- have to be the same pixels or ADVANCED would lose something by taking the
  -- second, so the two are worked out here for both mirrors.
  local function queued(x, u, v, flip)
    local drawX = flip and (x + 16) or x
    local sx = flip and -1 or 1
    return drawX + u * sx, v
  end
  local function fallthrough(x, u, v, flip)
    local sx = flip and -1 or 1
    return (x + 8) + (u - 8) * sx, ((0) + 16) + (v - 16)
  end
  for _, flip in ipairs({ false, true }) do
    for _, u in ipairs({ 0, 7, 15 }) do
      for _, v in ipairs({ 0, 9, 15 }) do
        local qx, qy = queued(40, u, v, flip)
        local fx, fy = fallthrough(40, u, v, flip)
        eq(fx, qx, ("column %d lands in the same place (flip=%s)")
          :format(u, tostring(flip)))
        eq(fy, qy, ("row %d lands in the same place (flip=%s)")
          :format(v, tostring(flip)))
      end
    end
  end
end

io.write(("\nfollower cull: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
