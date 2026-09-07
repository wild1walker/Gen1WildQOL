-- Headless coverage of AUTO CONTINUE's Gold arm
-- (modules/Gen1AutoContinue/main.lua).
--
-- Nothing here can say what a frame LOOKS like.  What it can say is the whole
-- of what this arm does, which is three claims about screens:
--
--   * the boot cinema is ENDED, all four cards of it, and ended in ONE update
--     rather than one card per update -- because a card ended on its own
--     first update has already been drawn once, and three of those is three
--     flashes of a cinema the player asked to skip.
--   * the title's own onContinue is where the menu is answered, so the
--     CONTINUE menu is never a frame.  The answer is the engine's own
--     payload with the engine's own save, not a file this mod went looking
--     for.
--   * B and SELECT mean what they mean on Red, over screens that share
--     nothing with Red's.
--
-- And one claim about Gen 1: none of it runs there.  The two arms are picked
-- apart by generation and the Gen 1 arm is what shipped, so the test that
-- matters most for a Red player is that a Gold boot's wiring is not on their
-- title screen.
--
-- Run:  luajit tests/autocontinue_gen2_test.lua

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

local function load_(path)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- ---------------------------------------------------------------- harness

local generation = 2
package.loaded["src.core.GameVersion"] = {
  generation = function() return generation end,
  engine = function() return "gold" end,
}

-- A stand-in for the engine's mod object, cut to what this module touches.
local function fakeMod(options)
  local mod
  mod = {
    logged = {},
    listeners = {},
    hooks = { wrap = function() end },
    input = { tap = function(_, _game, button)
      mod.tapped[#mod.tapped + 1] = button
    end },
    tapped = {},
  }
  mod.options = {
    define = function() end,
    get = function(_, key)
      local value = options[key]
      if value == nil then return true end
      return value
    end,
  }
  mod.log = {}
  for _, level in ipairs({ "info", "warn", "error", "debug" }) do
    mod.log[level] = function(_, format, ...)
      mod.logged[#mod.logged + 1] = select("#", ...) > 0
        and format:format(...) or format
    end
  end
  mod.events = {
    on = function(_, name, fn)
      mod.listeners[name] = mod.listeners[name] or {}
      table.insert(mod.listeners[name], fn)
    end,
  }
  mod.push = function(state)
    for _, fn in ipairs(mod.listeners["screen.pushed"] or {}) do
      fn({ state = state })
    end
  end
  return mod
end

-- A stack with the one method this arm asks it for.
local function fakeStack()
  local stack = { states = {} }
  function stack:top() return self.states[#self.states] end
  function stack:clear() self.states = {} end
  function stack:push(state)
    self.states[#self.states + 1] = state
    return state
  end
  return stack
end

-- Input that answers one press, once, the way an edge does.
local function fakeInput(pressed)
  return {
    wasPressed = function(_, button)
      if pressed[button] then
        pressed[button] = nil
        return true
      end
      return false
    end,
  }
end

local function install(options)
  local mod = fakeMod(options or {})
  load_("modules/Gen1AutoContinue/main.lua")(mod)
  return mod
end

-- ------------------------------------------------------------ the cinema

-- Gold's four cards, each with the door it actually has.  `drawn` counts the
-- frames a card would have reached the screen on: one per update the card is
-- still the top of the stack and has not ended.
local function bootChain(game)
  local drawn = { copyright = 0, gamefreak = 0, movie = 0, title = 0 }

  local function title()
    local self = { screenId = "Gen2TitleState", game = game,
                   update = function(s) drawn.title = drawn.title + 1 end }
    game.stack:clear()
    game.stack:push(self)
    game.pushed(self)
    return self
  end

  -- The attract movie: skip() and finish(), setting `finished`.
  local function movie()
    local self = { screenId = "Gen2GoldSilverIntro", game = game }
    self.update = function(s) drawn.movie = drawn.movie + 1 end
    self.finish = function(s)
      if s.finished then return end
      s.finished, s.done = true, true
      title()
    end
    self.skip = function(s) s.skipped = true; s:finish() end
    game.stack:clear()
    game.stack:push(self)
    game.pushed(self)
    return self
  end

  -- The GAME FREAK splash: finish() sets `done` and hands `skipped` on, and
  -- Game2:showGameFreak reads a skipped one as "straight to the title".
  local function gamefreak()
    local self = { screenId = "Gen2GameFreakPresents", game = game }
    self.update = function(s) drawn.gamefreak = drawn.gamefreak + 1 end
    self.onDone = function(skipped)
      if skipped then title() else movie() end
    end
    self.finish = function(s)
      if s.done then return end
      s.done = true
      s.onDone(s.skipped)
    end
    game.stack:clear()
    game.stack:push(self)
    game.pushed(self)
    return self
  end

  -- The copyright card: no finish() and no skip() at all.  It ends by
  -- running its own onDone behind a `done` latch.
  local self = { screenId = "Gen2CopyrightSplash", game = game }
  self.update = function(s) drawn.copyright = drawn.copyright + 1 end
  self.onDone = function() gamefreak() end
  game.stack:push(self)
  game.pushed(self)
  return self, drawn
end

do
  io.write("the boot cinema\n")
  local mod = install()
  local game = { stack = fakeStack(), pushed = mod.push }
  local first, drawn = bootChain(game)

  -- One update on the card that was up when the mod attached.
  local top = game.stack:top()
  top:update(1 / 60)

  eq(first.done, true, "the copyright card is ended -- and it has neither "
     .. "finish() nor skip(), so the fallback to its own onDone is what "
     .. "ends it")
  eq(game.stack:top().screenId, "Gen2TitleState",
     "and ONE update lands on the title: every card between was drained in "
     .. "the same frame")
  eq(drawn.gamefreak, 0, "the GAME FREAK splash never updated")
  eq(drawn.movie, 0,
     "and neither did the attract movie -- the splash was ended as SKIPPED, "
     .. "which is what Game2:showGameFreak reads as 'go straight to the "
     .. "title'")
  eq(#mod.logged, 0, "and nothing was warned about")
end

do
  io.write("SKIP INTRO off\n")
  local mod = install({ skip_intro = false })
  local game = { stack = fakeStack(), pushed = mod.push }
  local first, drawn = bootChain(game)

  game.stack:top():update(1 / 60)
  eq(first.done, nil, "the copyright card is left alone")
  eq(drawn.copyright, 1, "and plays")
  eq(game.stack:top(), first, "the cinema is still on the stack")
end

-- -------------------------------------------------------------- the title

-- The title and the menu it builds, as Gold builds them: the title's
-- onContinue clears the stack and pushes Gen2MainMenu, whose CONTINUE row is
-- `onContinue(self.save)` behind a save panel and a second A press.
local function titleWithMenu(game, opts)
  opts = opts or {}
  local seen = { continued = 0, chose = nil, save = nil, confirm = false }
  local menu

  local function showMainMenu()
    menu = {
      screenId = "Gen2MainMenu",
      game = game,
      hasSave = opts.hasSave ~= false,
      save = { player = "GOLD" },
      choose = function(self, value)
        seen.chose = value
        if value == "continue" then seen.confirm = true end
      end,
      onContinue = function(save)
        seen.continued = seen.continued + 1
        seen.save = save
        game.stack:clear()
        game.stack:push({ screenId = "World" })
      end,
    }
    game.stack:clear()
    game.stack:push(menu)
    return menu
  end

  local self = {
    screenId = "Gen2TitleState",
    game = game,
    entranceScx = 0,
    onContinue = showMainMenu,
  }
  self.update = function(s)
    -- engine/menus/intro_menu.asm:1061-1063
    local input = s.game.input
    if input and (input:wasPressed("a") or input:wasPressed("start")) then
      s.onContinue()
    end
  end
  game.stack:push(self)
  game.pushed(self)
  return self, seen, function() return menu end
end

do
  io.write("START on the title\n")
  local mod = install()
  local game = { stack = fakeStack(), pushed = mod.push }
  game.input = fakeInput({})
  local title, seen = titleWithMenu(game)

  game.input = fakeInput({ start = true })
  title:update(1 / 60)

  eq(seen.continued, 1, "the menu's own CONTINUE payload ran")
  ok(seen.save ~= nil,
     "with the save the MENU read -- nothing here went looking for a file")
  eq(seen.confirm, false,
     "and the save panel was never opened, so the second A press it waits "
     .. "for is not owed")
  eq(game.stack:top().screenId, "World",
     "the world is up, in the same update the press was read -- the CONTINUE "
     .. "menu was never a frame")
end

do
  io.write("no save\n")
  local mod = install()
  local game = { stack = fakeStack(), pushed = mod.push }
  game.input = fakeInput({})
  local title, seen, menuOf = titleWithMenu(game, { hasSave = false })

  game.input = fakeInput({ a = true })
  title:update(1 / 60)

  eq(seen.continued, 0, "nothing is continued")
  eq(game.stack:top(), menuOf(),
     "and the ordinary menu is left up, which is what a first boot wants")
end

do
  io.write("B and SELECT\n")
  local mod = install()
  local game = { stack = fakeStack(), pushed = mod.push }
  game.input = fakeInput({ b = true })
  local title, seen, menuOf = titleWithMenu(game)

  title:update(1 / 60)
  eq(seen.continued, 0, "B does not continue")
  eq(mod.tapped[1], "start",
     "it hands the engine the press that builds the menu, rather than "
     .. "reproducing the hand-over")

  -- the queued edge lands on the next step
  game.input = fakeInput({ start = true })
  title:update(1 / 60)
  eq(seen.chose, "exit",
     "and the menu's own EXIT GAME row is what runs -- only the engine knows "
     .. "how this build quits")
  eq(seen.continued, 0, "with no continue on the way past")
end

do
  local mod = install()
  local game = { stack = fakeStack(), pushed = mod.push }
  game.input = fakeInput({ select = true })
  local title, seen, menuOf = titleWithMenu(game)

  title:update(1 / 60)
  eq(mod.tapped[1], "start", "SELECT asks the engine for the menu")

  game.input = fakeInput({ start = true })
  title:update(1 / 60)
  eq(seen.continued, 0, "and the menu is NOT walked through")
  eq(seen.chose, nil, "nor is any row picked for the player")
  eq(game.stack:top(), menuOf(), "the ordinary menu is what is on the screen")
end

do
  io.write("B EXITS GAME off\n")
  local mod = install({ exit_on_b = false })
  local game = { stack = fakeStack(), pushed = mod.push }
  game.input = fakeInput({ b = true })
  local title = titleWithMenu(game)

  title:update(1 / 60)
  eq(#mod.tapped, 0, "B is a dead input again, as it is in vanilla")
end

do
  io.write("AUTO CONTINUE off\n")
  local mod = install({ enabled = false })
  local game = { stack = fakeStack(), pushed = mod.push }
  game.input = fakeInput({ start = true })
  local title, seen, menuOf = titleWithMenu(game)

  title:update(1 / 60)
  eq(seen.continued, 0, "the menu is left alone")
  eq(game.stack:top(), menuOf(), "and it is what the player gets")
end

-- ------------------------------------------------------------- and on Red

do
  io.write("nothing of this on Red\n")
  generation = 1
  local mod = install()
  local game = { stack = fakeStack(), pushed = mod.push }
  game.input = fakeInput({})
  local title, seen = titleWithMenu(game)

  -- Gold's title fails isGen1Title (no openMenu, no toMenu), so on a Red boot
  -- it is not attached to by either arm and its update is its own.
  game.input = fakeInput({ start = true })
  title:update(1 / 60)
  eq(seen.continued, 0,
     "a Gen 2 title on a Gen 1 boot is left entirely alone -- the arms are "
     .. "picked apart before either touches a screen")

  -- And the Gen 1 arm still claims a Gen 1 title.
  local red = {
    screenId = "TitleState",
    game = game,
    phase = "loop",
    openMenu = function() end,
    toMenu = function() end,
    onContinue = function() end,
  }
  local baseUpdate = function() end
  red.update = baseUpdate
  game.pushed(red)
  ok(red.update ~= baseUpdate, "Red's title is still attached to")
  generation = 2
end

io.write(("autocontinue gen2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
