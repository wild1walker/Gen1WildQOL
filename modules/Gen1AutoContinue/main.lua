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
--
-- ON GOLD, SILVER AND CRYSTAL
--
-- Everything above describes Red's boot.  Gold's is a different set of
-- screens end to end -- four cards of cinema instead of one, a title with no
-- menu of its own, and a CONTINUE that opens a save panel and waits for a
-- second press -- so this mod carries a second arm rather than a branch.  The
-- long note at `GEN2_TITLE` below is that arm's; the two share the option
-- rows, the three buttons and what each of them means, and share no code,
-- because there is none to share.
--
-- Until 0.32.24 there was no second arm and the tests above were doing their
-- job too well: `isGen1Title` refused Gold's title, `isIntro` matched none of
-- Gold's cards, and the mod sat inert through the whole boot with its row
-- reading ON.

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

  -- Which game this is, asked once.  The two arms below share the options,
  -- the buttons and the promise and share not one line of the attachment,
  -- because the screens they attach to have nothing in common but their job.
  local isGen2 = (function()
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    if not ok or type(GameVersion) ~= "table" then return false end
    if type(GameVersion.generation) ~= "function" then return false end
    local okCall, generation = pcall(GameVersion.generation)
    return okCall and generation == 2
  end)()

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


  -- ------- GOLD, SILVER AND CRYSTAL
  --
  -- The same three buttons and the same promise, over a boot that is built
  -- out of different parts.  Nothing above this point runs there: Gold's
  -- title (src/ui/gen2/TitleState.lua) has no `openMenu` and no `toMenu`, so
  -- `isGen1Title` refuses it, and its boot cinema is four screens rather than
  -- one, none of which is named `IntroMovie`.  That refusal was correct and
  -- was doing its job -- it kept the mod from erroring on Gold -- but the
  -- outcome a player saw was the mod doing nothing at all: the copyright
  -- card, the GAME FREAK splash, the attract movie, the title, the CONTINUE
  -- menu and the save panel, all of them, with AUTO CONTINUE reading ON.
  --
  -- WHAT THE BOOT IS MADE OF
  --
  -- Game2 chains it one screen at a time, each one's `onDone` pushing the
  -- next (src/core/Game2.lua:showCopyright -> showGameFreak -> showIntro ->
  -- showTitle):
  --
  --   Gen2CopyrightSplash      the (c) card
  --   Gen2GameFreakPresents    the GAME FREAK logo -- Gen2CrystalSplash on
  --                            Crystal, which is the Ditto one
  --   Gen2GoldSilverIntro      the attract movie -- Gen2CrystalIntro on
  --                            Crystal
  --   Gen2TitleState           the title, START/A -> Gen2MainMenu
  --   Gen2MainMenu             CONTINUE / NEW GAME / OPTION / EXIT GAME,
  --                            and CONTINUE opens the save panel and waits
  --                            for a second A (MainMenu:update, phase
  --                            "confirm", after twenty frames of
  --                            DisplaySaveInfoOnContinue)
  --
  -- So the tail this mod collapses on Red -- menu, row, info window, press --
  -- is a menu, a row, a panel and a press here, and SKIP INTRO has three
  -- cards to take out instead of one.
  --
  -- The two splashes are worth a line of their own.  Their `onDone` is handed
  -- `self.skipped`, and Game2:showGameFreak reads it as "go straight to the
  -- title" (src/core/Game2.lua:402-419) -- which is the cart's own answer to
  -- a button press there, and exactly what SKIP INTRO is asking for.  So
  -- finishing the splash as SKIPPED takes the attract movie with it rather
  -- than needing the movie skipped separately.  The movie is still attached
  -- to, because a build that reaches it another way should still skip it.

  local GEN2_TITLE = "Gen2TitleState"
  local GEN2_MENU = "Gen2MainMenu"
  local GEN2_BOOT = {
    Gen2CopyrightSplash = true,
    Gen2GameFreakPresents = true,
    Gen2CrystalSplash = true,
    Gen2GoldSilverIntro = true,
    Gen2CrystalIntro = true,
  }

  local function screenIdOf(state)
    return type(state) == "table" and type(state.screenId) == "string"
      and state.screenId or nil
  end

  local function isGen2Title(state)
    return screenIdOf(state) == GEN2_TITLE
      and type(state.update) == "function"
  end

  local function isGen2Boot(state)
    local id = screenIdOf(state)
    return id ~= nil and GEN2_BOOT[id] == true
  end

  -- All four cards latch themselves shut before running their onDone, and
  -- they do not agree on the name of the latch: the two movies set `finished`
  -- and `done`, the two splashes set `done`, the copyright card sets `done`.
  -- Asking for either is asking the question all four answer.
  local function bootEnded(state)
    return state.finished == true or state.done == true
  end

  -- End one card now, by whatever door it has.  In order, because the doors
  -- are not equivalent: `skip` says skipped AND ends, `finish` ends and tells
  -- its onDone whatever `skipped` already says, and the copyright card has
  -- neither and ends by running its own onDone behind its own latch
  -- (src/ui/gen2/CopyrightSplash.lua:81-85).
  local function endBootScreen(state)
    if bootEnded(state) then return true end
    -- Before any of them, because it is what the splashes pass on.
    state.skipped = true
    if type(state.skip) == "function" then
      local ok = pcall(state.skip, state)
      if ok and bootEnded(state) then return true end
    end
    if type(state.finish) == "function" then
      local ok = pcall(state.finish, state)
      if ok and bootEnded(state) then return true end
    end
    if type(state.onDone) == "function" then
      state.done = true
      local ok = pcall(state.onDone, state.skipped)
      if ok then return true end
      state.done = false
    end
    return false
  end

  -- Each card's onDone pushes the next one, so ending one leaves another on
  -- top of the stack in the same call.  Ending those too, here, is what keeps
  -- the whole cinema off the screen: a card ended on its own first update is
  -- a card that was DRAWN once, on the frame between its push and that
  -- update, and three cards in a row would be three flashes.  Draining them
  -- in one update means the title is the first thing the boot ever draws.
  --
  -- Bounded, and it stops the moment the top stops changing: a card that
  -- says it has ended and is still on top is a card this cannot help, and a
  -- loop is a worse answer than a frame.
  local function drainBoot(game)
    local last
    for _ = 1, #GEN2_BOOT + 2 do
      local top = game and game.stack and game.stack.top and game.stack:top()
      if not isGen2Boot(top) or top == last then return end
      last = top
      if not endBootScreen(top) then return end
    end
  end

  local function attachGen2Boot(state)
    if attached[state] then return end
    attached[state] = true
    if not mod.options:get("skip_intro") then return end

    local baseUpdate = state.update
    state.update = function(self, dt)
      if not bootEnded(self) then
        if endBootScreen(self) then
          drainBoot(self.game)
          return
        end
        -- It would not end: put the vanilla update back and let the cinema
        -- play rather than sit on a card that never advances.
        mod.log:warn("the boot cinema would not skip, playing it")
        self.update = baseUpdate
      end
      return baseUpdate(self, dt)
    end
  end

  local function attachGen2Title(state)
    if attached[state] then return end
    attached[state] = true

    local baseUpdate = state.update
    local baseContinue = state.onContinue
    local menuRequested, exitRequested = false, false

    -- What to do with the menu the title is about to build.
    --
    -- Called from inside the title's OWN onContinue, which is the one place
    -- where the menu exists and the frame has not been drawn yet: Game2:
    -- showMainMenu has returned, so the stack is settled and clearing it
    -- again is safe, and nothing has reached the screen.  A menu walked
    -- straight through here is never seen, which is the whole point -- the
    -- same reason the Gen 1 arm does its work in `openMenu` rather than a
    -- frame later.
    local function resolve(game)
      local menu = game and game.stack and game.stack.top and game.stack:top()
      if screenIdOf(menu) ~= GEN2_MENU then return end

      if exitRequested then
        exitRequested = false
        -- The engine's own EXIT GAME row, run by value rather than rebuilt:
        -- `choose` is what the list calls and it ends in `onExit` or the
        -- host's quit, and only the engine knows which this build wants.
        local ok, err = pcall(menu.choose, menu, "exit")
        if not ok then
          mod.log:warn("no EXIT GAME to run; B ignored: %s", tostring(err))
        end
        return
      end

      if menuRequested then
        menuRequested = false
        return
      end

      if not mod.options:get("enabled") then return end
      -- No save, or a build whose menu carries no CONTINUE payload: the
      -- ordinary menu, which is what it is there for.  Nothing here probes
      -- for a file -- `hasSave` and `save` are what the menu read for itself
      -- (src/ui/gen2/MainMenu.lua:65-70), which is the same honesty the Gen 1
      -- arm buys by calling onContinue and looking at the stack.
      if not menu.hasSave or type(menu.onContinue) ~= "function" then return end
      -- Gold calls it as a plain function with the save it read
      -- (MainMenu:update, phase "confirm"), so this is that call without the
      -- save panel and the second A press in front of it.
      local ok, err = pcall(menu.onContinue, menu.save)
      if not ok then
        -- A load that threw is the engine's problem to report; ours is to
        -- make sure the player still gets a menu instead of a dead title.
        mod.log:warn("continue failed, falling back to the menu: %s",
                     tostring(err))
      end
    end

    if type(baseContinue) == "function" then
      state.onContinue = function(...)
        local game = state.game
        baseContinue(...)
        local ok, err = pcall(resolve, game)
        if not ok then mod.log:warn("continue failed: %s", tostring(err)) end
      end
    end

    state.update = function(self, dt)
      -- TitleScreenEntrance polls no buttons (engine/menus/intro_menu.asm:
      -- 1078-1107) and neither does the timeout's fade, so these are read
      -- exactly where the engine reads its own -- and B and SELECT are dead
      -- inputs on the vanilla title in both games, so neither takes anything
      -- away.
      if (self.entranceScx or 0) <= 0 and not self.fadeStart then
        local input = self.game and self.game.input
        if input then
          if not exitRequested and mod.options:get("exit_on_b")
              and input:wasPressed("b") then
            exitRequested = true
            -- Hand the engine the press it already knows how to answer,
            -- rather than reproducing the hand-over: the queued edge lands on
            -- the next step and the title builds its menu itself.
            pcall(mod.input.tap, mod.input, self.game, "start")
          elseif not menuRequested and input:wasPressed("select") then
            menuRequested = true
            pcall(mod.input.tap, mod.input, self.game, "start")
          end
        end
      end
      return baseUpdate(self, dt)
    end
  end

  mod.events:on("screen.pushed", function(ev)
    local state = ev and ev.state
    if isGen2 then
      if isGen2Title(state) then
        attachGen2Title(state)
      elseif isGen2Boot(state) then
        attachGen2Boot(state)
      end
    elseif isGen1Title(state) then
      attach(state)
    elseif isIntro(state) then
      attachIntro(state)
    end
  end)
end
