-- The caught marker's true-colour MARKS, counted.
--
-- Reported as "with dark mode on the caught marker looks broken, and the exp
-- bar looks broken" -- one bug with two faces.
--
-- The ball is drawn a pixel at a time, because a row can change colour along
-- its length.  It used to be MARKED a pixel at a time too: thirty-seven 1x1
-- true-colour rects for a 7x7 icon.
--
--   * DARK paints a one-pixel skirt round every mark (Gen1WildUI
--     runtime/theme.lua, watchArt), suppressed only where it would land in a
--     rect ALREADY recorded.  So each pixel skirted its not-yet-marked
--     neighbours, and the ball's transparent corners -- never marked at all --
--     were painted dark and stayed dark.  A Poke Ball came out a blob.
--   * That theme keeps at most forty art rects a frame.  Thirty-seven went
--     here, so the EXP bar's single mark fell off the end and lost the zone
--     that themes it.
--
-- So what this asserts is not "it draws" but the SHAPE of what it reports:
-- one rect per contiguous run, covering the drawn pixels and nothing else.
--
-- Run:  luajit tests/caughtmark_test.lua

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

local function slurp(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local text = handle:read("*a")
  handle:close()
  return text
end

-- ---- the shipped body, read rather than restated

local SOURCE = "modules/QualityOfLife/qol_feature_caught_indicator.lua"
local src = slurp(SOURCE)
local body = assert(src:match("(local function drawBallRows.-\nend)\n"),
                    "could not find drawBallRows in " .. SOURCE)
local ROWS = {}
for row in src:match("local BALL_ROWS = {(.-)}"):gmatch('"([^"]+)"') do
  ROWS[#ROWS + 1] = row
end
eq(#ROWS, 7, "the Gen 1 ball is seven rows")

local drawn, marks
local love = {
  graphics = {
    setColor = function() end,
    rectangle = function(_, x, y, w, h)
      for px = x, x + w - 1 do
        for py = y, y + h - 1 do drawn[px .. "," .. py] = true end
      end
    end,
  },
}
_G.love = love

-- Two doors into the same recording, so the suite can say WHICH one the ball
-- went through.  The theme installs the second (Gen1WildUI runtime/theme.lua,
-- MARK_FLAT): it records the rect but paints no ring round it, which is the
-- half of this bug that the run-marking did not fix.
local flat
local PaletteFX = {
  markTrueColor = function(x, y, w, h)
    marks[#marks + 1] = { x = x, y = y, w = w, h = h, flat = false }
  end,
}
package.loaded["src.render.PaletteFX"] = PaletteFX
local function withFlatMark(present)
  if present then
    PaletteFX.__gen1WildMarkFlat = function(x, y, w, h)
      marks[#marks + 1] = { x = x, y = y, w = w, h = h, flat = true }
    end
  else
    PaletteFX.__gen1WildMarkFlat = nil
  end
end
withFlatMark(true)

local drawBallRows = assert(load(body .. "\nreturn drawBallRows"))()

local COLORS = { x = { 0, 0, 0 }, d = { 90, 90, 90 }, l = { 200, 200, 200 } }

local function run(rows, scale, mark)
  drawn, marks = {}, {}
  drawBallRows(rows, 10, 20, scale, COLORS, mark)
end

-- ---- and through the mark that draws no ring round it
--
-- The run-marking fixed the BUDGET and not the ball, and the report came back.
-- DARK rings every mark, suppressed only inside a rect ALREADY recorded, so
-- each run's ring reached into the concave corners the next row has not drawn
-- yet and the row above never draws -- twelve pixels of dark inside the ball's
-- own 7x7.  A skirt hides the seam where art the theme did not draw meets a
-- shaded page; this ball has no seam, and marks flat.

do
  io.write("the ball marks flat, so nothing is drawn round it\n")
  run(ROWS, 1, true)
  local flatCount = 0
  for _, m in ipairs(marks) do if m.flat then flatCount = flatCount + 1 end end
  eq(flatCount, #marks, "every run goes through the flat mark")

  -- and a build with no theme installed marks exactly as it always did
  withFlatMark(false)
  run(ROWS, 1, true)
  eq(#marks, 7, "with no theme there are still seven rects")
  local plain = 0
  for _, m in ipairs(marks) do if not m.flat then plain = plain + 1 end end
  eq(plain, #marks, "reported through the ordinary mark, as before")
  withFlatMark(true)
end

-- ---- one rect per run

do
  io.write("the ball reports one rect per row-run, not one per pixel\n")
  run(ROWS, 1, true)

  local pixels = 0
  for _ in pairs(drawn) do pixels = pixels + 1 end
  eq(pixels, 37, "thirty-seven pixels are drawn")
  eq(#marks, 7, "and seven rects are reported -- one per row, each row a run")
  ok(#marks < 40, "which leaves the frame's forty-rect budget for everyone else")
end

-- ---- and they cover the drawn pixels EXACTLY

do
  io.write("the rects cover what was drawn, and nothing that was not\n")
  run(ROWS, 1, true)

  local covered = {}
  for _, m in ipairs(marks) do
    for px = m.x, m.x + m.w - 1 do
      for py = m.y, m.y + m.h - 1 do
        local key = px .. "," .. py
        ok(covered[key] == nil, "no pixel is marked twice (" .. key .. ")")
        covered[key] = true
      end
    end
  end

  local missing, extra = 0, 0
  for key in pairs(drawn) do if not covered[key] then missing = missing + 1 end end
  for key in pairs(covered) do if not drawn[key] then extra = extra + 1 end end
  eq(missing, 0, "every drawn pixel is inside a rect")
  eq(extra, 0,
     "and no transparent pixel is -- a rect over the ball's corners would "
     .. "re-blit the HUD behind them raw")
end

-- ---- the same, scaled up

do
  io.write("a scaled ball scales its rects with it\n")
  run(ROWS, 3, true)
  eq(#marks, 7, "still seven")
  local widest = 0
  for _, m in ipairs(marks) do
    eq(m.h, 3, "each is one row tall, at scale")
    if m.w > widest then widest = m.w end
  end
  eq(widest, 21, "and the widest run is seven cells of three")
end

-- ---- mark = false reports nothing at all
--
-- The Gold arm draws the same ball through this and passes false, because it
-- is drawing into the battle overlay rather than onto a themed page.

do
  io.write("mark = false reports nothing\n")
  run(ROWS, 1, false)
  eq(#marks, 0, "no rects when the caller does not ask for them")
  local pixels = 0
  for _ in pairs(drawn) do pixels = pixels + 1 end
  eq(pixels, 37, "but the ball is still drawn")
end

-- ---- a row with a HOLE in it splits, rather than marking the hole
--
-- The Gen 2 ball has them: "xxoxxx" and "xoooox" are two runs each.

do
  io.write("a row with a gap reports two rects, not one across the gap\n")
  run({ "xxoxxx" }, 1, true)
  eq(#marks, 2, "two runs, two rects")
  eq(marks[1].w, 2, "the first is two wide")
  eq(marks[2].w, 3, "the second is three")
  eq(marks[2].x - (marks[1].x + marks[1].w), 1, "with the hole left unmarked")
end

io.write(("\ncaughtmark: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
