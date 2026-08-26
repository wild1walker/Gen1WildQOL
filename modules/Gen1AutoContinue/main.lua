-- Gen1AutoContinue
--
-- Vanilla boot is title -> START/A -> CONTINUE / NEW GAME / OPTION / EXIT ->
-- CONTINUE -> the PLAYER / BADGES / POKeDEX / TIME info window -> A -> the
-- overworld.  Four presses to resume a save that was never in question.
--
-- This mod collapses the tail of that.  Everything before the press -- the
-- copyright splash, the attract movie, the logo drop, the title-mon cycle,
-- the exit cry, the white-out -- runs exactly as it does in vanilla, because
-- the boot cinematic is the part worth keeping.
--
--   START / A   load the save
--   B           EXIT GAME
--   SELECT      the ordinary CONTINUE / NEW GAME / OPTION / EXIT menu
--
-- Three buttons, no holds.  B and SELECT are both dead inputs on the vanilla
-- title, so neither takes anything away.
--
-- SKIP INTRO takes the copyright card and the attract movie out too, so the
-- boot is: title, one press, playing.
--
-- HOW IT ATTACHES
--
-- The title screen is a stack state (src/ui/TitleState.lua).  Its journey out
-- of the attract loop is:
--
--   update()   phase "loop", START/A pressed  -> phase "exitCry"
--   update()   cry finished                   -> toMenu()
--   toMenu()   whiteFlash, then               -> menuOpen = true; openMenu()
--   openMenu() builds CONTINUE / NEW GAME / OPTION / EXIT and pushes the Menu
--
-- We take the instance handed to us by screen.pushed and shadow two of its
-- methods.  The engine class is untouched -- these are per-instance fields,
-- so a second title (QUIT from the START menu builds a fresh one) gets its
-- own pair, and uninstalling the mod leaves nothing behind.
--
--   update()   reads B and SELECT, and arms the skip on the one frame the
--              press is registered.
--   openMenu() is where the skip happens, which means the white-out and the
--              cleared screen have already played.  The frame the save lands
--              on is a blank one either way.
--
-- WHY openMenu AND NOT toMenu
--
-- toMenu owns the whiteFlash.  Replacing it would mean re-creating that
-- transition from a mod, which needs src.render.Transition -- a private
-- require and an engine_internals permission, for something the engine is
-- already doing correctly one call further down.  Letting toMenu run and
-- intercepting its payload keeps this mod at zero permissions.
--
-- NO SAVE, OR A SAVE THAT WILL NOT LOAD
--
-- We do not probe for a save file.  TitleState's own hasSave() is a local, and
-- reaching for love.filesystem from a mod is worse than asking the question
-- the honest way: call onContinue and look at the stack.  A successful load
-- runs Game:restoreSave, which empties the stack and pushes the overworld --
-- so if the title is still on top afterwards, nothing loaded, and we fall
-- through to the ordinary menu.  That covers a first boot, a deleted save and
-- an unrecoverable one with the same three lines and no duplicated logic.

return function(mod)
  mod.options:define({
    { key = "enabled", label = "AUTO CONTINUE", type = "toggle", default = true },
    -- Off for anyone who would rather not have a quit one keypress from a
    -- resume.  SELECT still reaches EXIT GAME through the menu either way.
    { key = "exit_on_b", label = "B EXITS GAME", type = "toggle", default = true },
    { key = "skip_intro", label = "SKIP INTRO", type = "toggle", default = true },
  })

  -- ------- the screens before the title
  --
  -- Game:load pushes one screen ahead of the title, with the title as its
  -- onDone: IntroMovie for Red/Blue (the copyright card, the GAME FREAK stars,
  -- the Gengar/Nidorino fight) or YellowIntro for Yellow's eighteen-scene
  -- movie.  Both expose finish(), which pops and runs onDone -- and
  -- IntroMovie already finishes on its first update when field.intro.skip is
  -- set, so finishing there is a path the engine takes itself rather than one
  -- this mod invents.
  --
  -- screen.pushed fires during the push, which happens inside Game:load --
  -- before the first update and so before anything is drawn.  Finishing on
  -- the update after that means not one frame of the intro reaches the
  -- screen: no flash of the copyright card, no clipped note of
  -- Music_IntroBattle, because phase 3 never starts it.
  local INTRO_IDS = { IntroMovie = true, YellowIntro = true }

  local function isIntro(state)
    if type(state) ~= "table" or type(state.finish) ~= "function" then
      return false
    end
    local id = state.screenId -- stamped by Screens.build
    if type(id) ~= "string" then return false end
    if INTRO_IDS[id] then return true end
    -- a total conversion names its own boot screens (field.boot.screens);
    -- honour whatever it put in the splash slot rather than the two builtins
    local game = mod.game
    local field = game and game.data and game.data.field
    local screens = field and field.boot and field.boot.screens
    return screens ~= nil and screens.splash == id
  end

  -- ------- EXIT GAME
  --
  -- The row's action ends in love.event.quit(), which the sandbox blocks
  -- (src/mods/Sandbox.lua BLOCKED_LOVE) and rightly so.  Nor is the closure
  -- ours to rebuild: on desktop that quit is intercepted by main.lua's
  -- love.quit and usually becomes a restart back into the launcher, and only
  -- the engine knows which.  So B runs the engine's own EXIT GAME row rather
  -- than an imitation of it.
  --
  -- Getting hold of that row means letting openMenu build the list once.
  -- This wrap runs at the front of the chain, so `items` is the pristine
  -- vanilla list and its last entry is EXIT GAME (see openMenu's insert
  -- order: CONTINUE?, NEW GAME, OPTION, EXIT GAME).  Reading it on the way in
  -- also means a mod that appends rows after next() returns cannot displace
  -- it.
  local exitRow
  mod.hooks:wrap("ui.title_menu.items", function(nextLink, game, items)
    if type(items) == "table" and type(items[#items]) == "table" then
      exitRow = items[#items]
    end
    return nextLink(game, items)
  end, 1000)

  -- Weak keys: a title state that has been popped and collected must not be
  -- held alive by our bookkeeping.
  local attached = setmetatable({}, { __mode = "k" })

  -- Gen 1's title, specifically.  Gold's title (src/ui/gen2/TitleState.lua)
  -- calls onContinue straight from update and has no openMenu at all, so it
  -- fails this test and the mod stays inert there rather than erroring.
  local function isGen1Title(state)
    return type(state) == "table"
       and type(state.openMenu) == "function"
       and type(state.toMenu) == "function"
       and type(state.onContinue) == "function"
  end

  local function attach(state)
    if attached[state] then return end
    attached[state] = true

    local baseUpdate = state.update
    local baseOpenMenu = state.openMenu
    local armed, menuRequested = false, false

    -- Build the menu to capture EXIT GAME, take it straight back down, and
    -- run the row.  The push and pop happen inside one update, so nothing is
    -- ever drawn; menuOpen is deliberately left alone so the title art is
    -- still up on the frame the quit is dispatched.
    local function exitGame(self)
      local game = self.game
      baseOpenMenu(self)
      local menu = game and game.stack and game.stack:top()
      if menu and menu ~= self then game.stack:pop() end
      if exitRow and type(exitRow.onSelect) == "function" then
        exitRow.onSelect()
        return true
      end
      -- Nothing recognisable to run.  Better a dead button than a menu the
      -- player did not ask for, or a guess at how this build quits.
      mod.log:warn("no EXIT GAME row to run; B ignored")
      return false
    end

    state.update = function(self, dt)
      if self.phase == "loop" then
        local input = self.game and self.game.input
        if input then
          if mod.options:get("exit_on_b") and input:wasPressed("b") then
            local ok, err = pcall(exitGame, self)
            if not ok then mod.log:warn("exit failed: %s", tostring(err)) end
            return
          end
          -- SELECT is the way back to the full menu.  Rather than reproduce
          -- the cry and the white-out, hand the engine the press it already
          -- knows how to answer -- the queued edge lands on the next step
          -- (Input:step), so vanilla plays the whole exit sequence.
          if not menuRequested and input:wasPressed("select") then
            menuRequested = true
            pcall(mod.input.tap, mod.input, self.game, "start")
          end
        end
      end

      local before = self.phase
      baseUpdate(self, dt)
      -- The one transition a button press causes.  Both layouts take it:
      -- Red/Blue cry with the cycling title mon, Yellow with Pikachu.
      if before == "loop" and self.phase == "exitCry" then
        armed = mod.options:get("enabled") and not menuRequested
        menuRequested = false
      end
    end

    state.openMenu = function(self)
      if armed then
        armed = false
        local game = self.game
        local ok, err = pcall(self.onContinue)
        if not ok then
          -- A load that threw is the engine's problem to report; ours is to
          -- make sure the player still gets a menu instead of a dead title.
          mod.log:warn("continue failed, falling back to the menu: %s",
                       tostring(err))
        elseif game and game.stack and game.stack:top() ~= self then
          return -- restoreSave took the stack; the overworld is up
        end
      end
      return baseOpenMenu(self)
    end
  end

  local function attachIntro(state)
    if attached[state] then return end
    attached[state] = true
    if not mod.options:get("skip_intro") then return end

    local baseUpdate = state.update
    -- IntroMovie reads this on its own first-update skip; harmless on any
    -- screen that does not
    state.skipAll = true
    state.update = function(self, dt)
      if not self.finished then
        local ok, err = pcall(self.finish, self)
        if ok and self.finished then return end
        -- it would not end: put the vanilla update back and let the intro
        -- play rather than sit on a screen that never advances
        mod.log:warn("intro would not skip, playing it: %s",
                     ok and "finish() did nothing" or tostring(err))
        self.update = baseUpdate
      end
      return baseUpdate(self, dt)
    end
  end

  mod.events:on("screen.pushed", function(ev)
    local state = ev and ev.state
    if isGen1Title(state) then
      attach(state)
    elseif isIntro(state) then
      attachIntro(state)
    end
  end)
end
