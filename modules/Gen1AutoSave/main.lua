-- Gen1AutoSave
--
-- Saves on its own so manual saving becomes optional, and stays out of the
-- built-in save sync's way while doing it:
--
--   * the timer runs during battles and menus, not only while you stand still
--     on the map -- the write itself still waits for a settled overworld
--   * nothing happened since the last write => no write, so idling on the map
--     never bumps the save revision or wakes an upload
--   * never writes while sync is mid-transfer or holding an unresolved
--     conflict; the save is retried once sync settles
--   * one floor between writes, so a row of doors can't hammer the file
--   * picking QUIT offers the save in the confirm box, and the quit waits
--     for the write -- and for the upload it starts -- before it leaves
--
-- Game:writeSave() already tells the sync engine it happened (5s upload
-- debounce), so nothing here has to ask for a sync -- only choose how often
-- to let one happen, and pay for what a save leaves behind at the save:
--
--   * at most one autosave-woken upload every five minutes; the rest ride the
--     engine's own sweep, which uploads anything whose savedAt moved anyway
--   * finish the collector's cycle in the frame that wrote the file, and in
--     the frame a sync cycle ended, rather than on the route after either

return function(mod)
  local MIN_GAP = 20        -- seconds between any two autosaves
  local SYNC_RETRY = 2.0    -- re-check a busy sync this often
  local NOTIFY_TIME = 1.6
  local GC_STEP = 4096      -- collector work per step, in KB of allocation
  local GC_STEPS = 12       -- ceiling: a cycle on a game-sized heap, no more
  local UPLOAD_GAP = 300    -- least time between two autosave-woken uploads

  local BOX_W, BOX_H = 20, 3
  local ICON_W, ICON_H = 7, 3
  -- One 8x8 tile in from the playfield's corner, the same inset the engine
  -- gives its own furniture.  Both indicators use it, so the ball and the
  -- SAVED panel land on the same spot.  At 2 and 4 GB pixels they sat all but
  -- touching the corner, which on a screen the picture fills is close enough
  -- to the edge to look like a mistake -- and on a phone close enough to go
  -- under a rounded corner.
  local HUD_MARGIN = 8
  local MESSAGE_TEXT = "Game saved."
  local ICON_TEXT = "SAVED"
  local HELD_MESSAGE = "Autosave paused."
  local HELD_ICON = "PAUSED"

  -- The QUIT confirm, in place of the engine's "RETURN TO MAIN MENU?": the
  -- box has to say what YES is about to do, or the save is a surprise.  Both
  -- lines fit the 18 columns a text box gives them.
  local QUIT_PROMPT = "SAVE AND RETURN\nTO MAIN MENU?"
  local QUIT_SAVING = "Now saving..."
  local QUIT_WAIT = 15      -- seconds the quit will hold for save + upload

  local state = {
    clock = 0,
    elapsed = 0,
    lastWriteAt = -math.huge,
    dirty = false,
    due = false,
    inBattle = false,
    saving = false,
    syncWaitUntil = 0,
    lastUploadAt = -math.huge,
    syncWasBusy = false,
    notify = 0,
    heldTold = false,
    game = nil,
  }

  mod.options:define({
    {
      key = "enabled",
      type = "toggle",
      label = "AUTO SAVE",
      default = true,
      help = "Save progress automatically while you play.",
    },
    {
      -- OFF by default.  Battles, catches, evolutions, hatches, trades,
      -- blackouts and every new map already cover ordinary play, and picking
      -- QUIT covers the way out; a clock on top of that mostly buys writes
      -- that had nothing new to write.  Still here for anyone who wants one.
      key = "interval",
      type = "choice",
      label = "INTERVAL",
      default = 0,
      choices = {
        { "OFF", 0 },
        { "1 MIN", 60 },
        { "2 MIN", 120 },
        { "5 MIN", 300 },
        { "10 MIN", 600 },
        { "15 MIN", 900 },
      },
      help = "An extra save every so much play time. Off: events cover it.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "events",
      type = "toggle",
      label = "AFTER EVENTS",
      default = true,
      help = "Also save after battles, catches, evolutions and new areas.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "onquit",
      type = "toggle",
      label = "ON QUIT",
      default = true,
      help = "Offer to save in the QUIT confirm, and wait for it.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "notify",
      type = "choice",
      label = "INDICATOR",
      default = "ball",
      choices = {
        { "OFF", "off" },
        { "POKE BALL", "ball" },
        { "SAVED TEXT", "icon" },
        { "TEXT BOX", "box" },
      },
      help = "How an autosave announces itself.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "backups",
      type = "toggle",
      label = "SAVE BACKUPS",
      default = false,
      help = "Keep rollback copies of recent autosaves. START menu: BACKUPS.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "keep",
      type = "choice",
      label = "BACKUPS KEPT",
      default = 5,
      choices = {
        { "3", 3 },
        { "5", 5 },
        { "10", 10 },
        { "20", 20 },
      },
      help = "How many rollback copies to keep before the oldest is dropped.",
      visible_if = { key = "backups", equals = true },
    },
  })

  -- defined further down, next to the storage helpers it needs
  local captureBackup

  -- ---------- options

  local function on()
    return mod.options:get("enabled") == true
  end

  local function intervalSeconds()
    local value = mod.options:get("interval")
    if type(value) ~= "number" then return 0 end
    return value
  end

  -- ---------- when a write is allowed

  -- Same settled-overworld rule the engine uses for its own snapshots: no
  -- movement, no script, no transition, and the overworld actually on top.
  local function overworldIdle(game)
    local ow = game and game.overworld
    if not (ow and ow.player) then return false end
    if game.stack and game.stack:top() ~= ow then return false end
    if ow.player.moving then return false end
    if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then
      return false
    end
    if #(ow.scriptMoves or {}) > 0 then return false end
    if ow.engaging or ow.emote or ow.teleportOut or ow.transitioning then
      return false
    end
    return true
  end

  -- Everything sync is asked goes through pcall: a host with sync compiled
  -- out, or a Gen 2 one, answers none of these questions and must not take
  -- the autosave down with it.
  local function syncEngineOf(game)
    local ok, engine = pcall(function() return game:syncEngine() end)
    if not ok or type(engine) ~= "table" then return nil end
    return engine
  end

  local function syncConflicted(engine)
    local conflict = false
    pcall(function() conflict = engine.phase == "conflict" end)
    return conflict
  end

  local function syncTransferring(engine)
    local busy = false
    pcall(function() busy = engine:busy() == true end)
    return busy
  end

  -- A transfer in flight or a conflict waiting on the player are both reasons
  -- to hold the file still: writing now either races the upload or adds a
  -- third revision to a disagreement the player has not answered yet.
  local function syncSettled(game)
    if state.clock < state.syncWaitUntil then return false end
    local engine = syncEngineOf(game)
    if not engine then return true end
    local conflict = syncConflicted(engine)
    if conflict or syncTransferring(engine) then
      state.syncWaitUntil = state.clock + SYNC_RETRY
      return false, conflict and "conflict" or "transfer"
    end
    return true
  end

  -- Does the write we just made still owe sync something?  uploadAt is the
  -- engine's own debounce field -- set five seconds out by the
  -- noteSaveWritten inside writeSave, cleared when the upload starts -- and
  -- busy() covers the request in flight plus the queue behind it.  Both have
  -- to be clear before the save is anywhere but this device.
  --
  -- It is read and written directly because there is no accessor for it.  A
  -- conflict answers neither question: nothing is going up until the player
  -- resolves it, so it reads as settled and the quit stops waiting.
  local function syncOwesUpload(engine)
    local owed = false
    pcall(function()
      owed = engine.uploadAt ~= nil or engine:busy() == true
    end)
    return owed
  end

  -- ---------- what a write costs after the write
  --
  -- The lag around an autosave is mostly not the write.  Two things land a
  -- beat later, which is why they read as the game stuttering rather than as
  -- the game saving.

  -- The first is the collector catching up on what the write threw away.
  --
  -- A save is not steady state.  SaveData.save copies the progress table,
  -- serializes the copy into one large string, reads the previous file back
  -- to make the .bak, then writes that string twice more -- and rewrites
  -- options.lua alongside it.  With backups on, the checkpoint deep-copies
  -- the save twice on top of that and mod storage serializes the result
  -- again.  Megabytes of short-lived strings and tables, all in one frame.
  --
  -- The engine's collector budget is one small step per rendered frame
  -- (Game:update ends on collectgarbage("step", 1)), and its own comment says
  -- what that step is for: "ordinary Lua-heap garbage (per-frame tables and
  -- closures)", spread out "so the default lazy schedule never batches it
  -- into a visible pause".  A save is a year of per-frame garbage at once.
  -- The collector falls behind, and the part of a cycle that cannot be split
  -- -- finishing the mark -- surfaces a second or two later, in a frame that
  -- is just ordinary walking.
  --
  -- So finish the cycle here, in the frame that already stopped to touch the
  -- disk and is putting a save indicator on screen while it does.  The work
  -- is the same work; paying for it at the save costs a frame the player has
  -- been told to expect, instead of a slow patch of route afterwards they
  -- haven't.
  --
  -- Bounded, because a large heap on a phone must not turn one hitch into a
  -- freeze: a fixed number of steps, and stop early the moment a step reports
  -- the cycle finished.  The step argument is kilobytes of allocation for the
  -- collector to account for, which is how LuaJIT (the host) and 5.4 (the
  -- test harness) both read it.
  local function settleGarbage()
    if type(collectgarbage) ~= "function" then return end
    for _ = 1, GC_STEPS do
      local ok, finished = pcall(collectgarbage, "step", GC_STEP)
      if not ok or finished then return end
    end
  end

  -- The second is the upload the write woke, and it is the expensive one.
  --
  -- writeSave tells the sync engine it happened, which arms a five second
  -- upload debounce.  When that fires the engine asks the server for its
  -- state, and plans against the reply on the main thread -- planning being
  -- SyncEngine.defaultSaves's list(), which reads and DECODES every save slot
  -- of every game version before any of it reaches a worker.  Decoding runs
  -- SaveSerializer's restricted-grammar reader: a character-at-a-time parser
  -- written in Lua, deliberately, so a tampered save fails to parse instead
  -- of executing.  A quarter-megabyte slot costs tens of milliseconds, per
  -- slot on disk, across six versions -- and a phone is worse.
  --
  -- So every autosave bought a second stall, several frames long, a moment
  -- after the write -- by which time the player is walking again and has no
  -- reason to connect it to a save.  Saves land as often as every 20 seconds,
  -- and so did that stall.  It was the loudest thing this mod did to a linked
  -- device.
  --
  -- None of that work can be made cheaper from here.  It is the engine's, and
  -- it has to happen.  What can be chosen is how often.
  --
  -- At most one autosave-woken upload every UPLOAD_GAP.  Writes in between
  -- still land on disk; their debounce is disarmed, and the engine's own five
  -- minute sweep (SyncEngine.AUTO_INTERVAL, re-armed after every sync) carries
  -- them up, because planning compares each slot's savedAt against the
  -- revision it last saw and uploads anything that moved.  Nothing is lost,
  -- and a linked device stops paying for a sync cycle every 20 seconds to
  -- learn what one cycle every five minutes was going to tell it anyway.
  local function paceUpload(game)
    -- Picking QUIT is exempt.  There is no five minute sweep coming for a
    -- game that is about to stop running, so that write's upload goes now or
    -- never -- and stepQuit pulls it forward and then waits on it.
    if state.quit then return end
    if state.clock - state.lastUploadAt >= UPLOAD_GAP then
      state.lastUploadAt = state.clock
      return
    end
    local engine = syncEngineOf(game)
    if not engine then return end
    -- Only ever our own debounce: a manual save resets the write clock, so
    -- MIN_GAP puts 20 seconds between it and the next autosave, and the
    -- debounce it armed is 5 seconds long.
    pcall(function() engine.uploadAt = nil end)
  end

  -- And a sync cycle leaves the same debt behind it, more of it than the
  -- write that caused it: planning decoded every slot into a full table
  -- again, a character at a time.  Left alone that drag lands after the
  -- stall rather than with it, which is the same complaint one step further
  -- along.  Watch for a cycle finishing -- busy, then not busy -- and pay for
  -- it in the frame it landed on.
  --
  -- Every cycle, not only the ones an autosave woke: the engine's own sweep,
  -- a download, a conflict being resolved all decode the same slots, and
  -- after pacing most cycles are the engine's rather than ours.
  local function settleSyncGarbage(game)
    local engine = syncEngineOf(game)
    if not engine then
      state.syncWasBusy = false
      return
    end
    if syncTransferring(engine) then
      state.syncWasBusy = true
      return
    end
    if not state.syncWasBusy then return end
    state.syncWasBusy = false
    settleGarbage()
  end

  -- ---------- the write

  local function announce(held)
    -- Not during a quit: the box on screen is already saying it, and in TEXT
    -- BOX mode the indicator would be drawn straight over it.
    if state.quit then return end
    if mod.options:get("notify") ~= "off" then
      state.notify = NOTIFY_TIME
      state.held = held == true
    end
  end

  local function clearNotifyText()
    if state.notify <= 0 then
      state.notifyText = nil
      state.held = false
    end
  end

  -- An unresolved sync conflict holds every write, with no timeout and no way
  -- out but the player answering the launcher's prompt -- so staying quiet
  -- about it reads exactly like the mod having stopped working.  Said once
  -- per hold, not once per frame: it is a standing condition, not an event.
  local function tellHeld(why)
    if why ~= "conflict" or state.heldTold then return end
    state.heldTold = true
    announce(true)
    mod.log:warn("autosave held: save sync is waiting on a conflict answer")
  end

  local function write(game)
    if state.saving then return end
    -- snapshot first: a backup taken a frame before the write it accompanies
    -- is the same state, and a failed capture must not cost us the save
    captureBackup(game)
    state.saving = true
    local ok, result = pcall(game.writeSave, game)
    state.saving = false

    if ok and result ~= false then
      state.elapsed = 0
      state.dirty = false
      state.due = false
      state.lastWriteAt = state.clock
      paceUpload(game)
      settleGarbage()
      announce()
      mod.log:info("autosave written")
    elseif ok then
      -- another mod vetoed this write through save.write; stop asking
      state.due = false
    else
      state.due = false
      mod.log:warn("autosave failed: %s", tostring(result))
    end
  end

  local function request()
    if not on() then return end
    state.due = true
  end

  -- ---------- what counts as progress
  --
  -- The digest problem in one line: playtime always moves, so comparing save
  -- bytes would call every idle minute a change.  Instead the events the
  -- engine already emits mark the save dirty, and a save with nothing dirty
  -- is skipped -- which is what keeps sync quiet while the game sits paused.

  local TOUCHED = {
    "world.stepped", "world.interacted", "world.object_toggled",
    "world.block_replaced", "world.boulder_moved", "flag.changed",
    "battle.started", "battle.ended", "pokemon.caught", "pokemon.received",
    "pokemon.evolved", "pokemon.level_up", "pokemon.move_learned",
    "egg.hatched", "trade.completed", "mail.written", "happiness.changed",
    "map.entered",
  }

  for _, name in ipairs(TOUCHED) do
    mod.events:on(name, function() state.dirty = true end)
  end

  local CHECKPOINTS = {
    "battle.ended", "map.entered", "pokemon.caught", "pokemon.evolved",
    "egg.hatched", "trade.completed", "world.blacked_out",
  }

  for _, name in ipairs(CHECKPOINTS) do
    mod.events:on(name, function()
      state.dirty = true
      if mod.options:get("events") then request() end
    end)
  end

  mod.events:on("battle.started", function() state.inBattle = true end)
  mod.events:on("battle.ended", function() state.inBattle = false end)

  -- A manual save resets everything: the player just did the thing.  It is
  -- otherwise none of this mod's business -- writeSave notifies the sync
  -- engine itself, whoever called it.
  mod.events:on("save.writing", function()
    state.elapsed = 0
    state.dirty = false
    state.due = false
    state.lastWriteAt = state.clock
    -- A manual save wakes the sync engine exactly the way ours does, and its
    -- upload does the same planning work.  Count it: the next autosave has
    -- nothing to tell sync that this one is not already on its way to say.
    --
    -- Not when the write is ours.  writeSave emits this from inside write(),
    -- before paceUpload has decided anything, so counting our own write here
    -- would leave the gap permanently closed and no autosave would ever wake
    -- sync again.  state.saving is set for exactly that window.
    if not state.saving then state.lastUploadAt = state.clock end
  end)

  local function reset()
    state.elapsed = 0
    state.dirty = false
    state.due = false
    state.inBattle = false
    state.lastUploadAt = -math.huge
    state.syncWasBusy = false
    state.notify = 0
    state.heldTold = false
    state.held = false
    state.lastWriteAt = state.clock
  end

  mod.events:on("save.loaded", reset)
  mod.events:on("save.created", reset)

  mod.events:on("mod.options_changed", function(ev)
    if ev and ev.mod == mod and (ev.key == "enabled" or ev.key == "interval") then
      state.elapsed = 0
      state.due = false
    end
  end)

  -- ---------- backups
  --
  -- A backup is an engine checkpoint (the data-only progress snapshot plus the
  -- player's map/tile/facing and the RNG state) parked in mod storage, which is
  -- scoped per game version and per playthrough and written atomically.  It
  -- deliberately does NOT touch save.lua: the sync engine watches that file, so
  -- keeping history beside it costs no revisions and no uploads.
  --
  -- Only autosave moments get captured: Checkpoint.inspect refuses while a
  -- menu is on top, and a manual save happens from inside the START menu.  A
  -- manual save is untouched either way -- it writes and syncs exactly as it
  -- does without this mod, and just resets the timer here.

  local INDEX_KEY = "backups"

  local function slotKey(seq) return "backup/b" .. tostring(seq) end

  local function readIndex(game)
    local ok, data = pcall(function() return mod.storage:read(game, INDEX_KEY) end)
    if ok and type(data) == "table" and type(data.list) == "table" then
      data.seq = tonumber(data.seq) or 0
      return data
    end
    return { seq = 0, list = {} }
  end

  local function writeIndex(game, index)
    pcall(function() return mod.storage:write(game, INDEX_KEY, index) end)
  end

  local function keepCount()
    local value = mod.options:get("keep")
    if type(value) ~= "number" or value < 1 then return 5 end
    return value
  end

  -- Label the row with wall-clock time, which is the thing a player actually
  -- recognizes ("the one from before the gym").  Map ids are engine constants
  -- and would need sanitizing for the tile font, so they stay out of the list.
  local function stamp(game, at)
    local ok, text = pcall(function() return mod.datetime:time(game, at) end)
    if ok and type(text) == "string" and text ~= "" then return text end
    return os.date("%H:%M", at)
  end

  function captureBackup(game)
    if not (mod.options:get("backups") and mod.checkpoints and mod.storage) then
      return
    end
    local ok, checkpoint = pcall(function()
      return mod.checkpoints:capture(game)
    end)
    if not ok or type(checkpoint) ~= "table" then return end

    local index = readIndex(game)
    index.seq = index.seq + 1
    local key = slotKey(index.seq)
    local stored = pcall(function()
      return mod.storage:write(game, key, checkpoint)
    end)
    if not stored then return end

    index.list[#index.list + 1] = { seq = index.seq, at = os.time() }
    local keep = keepCount()
    while #index.list > keep do
      local dropped = table.remove(index.list, 1)
      pcall(function() return mod.storage:delete(game, slotKey(dropped.seq)) end)
    end
    writeIndex(game, index)
  end

  local function say(game, text)
    local TextBox = mod.ui and mod.ui.TextBox
    if not (TextBox and game and game.stack) then return end
    pcall(function() game.stack:push(TextBox.new(game, text)) end)
  end

  local function confirmRestore(game, entry)
    local TextBox = mod.ui and mod.ui.TextBox
    if not TextBox then return end
    game.stack:push(TextBox.new(game,
      "Roll back to the\nsave from " .. stamp(game, entry.at) .. "?", nil, {
        defaultNo = true,
        choice = function(yes)
          if not yes then return end
          -- Don't touch the stack here: the text box is still tearing itself
          -- down.  Park the request and let the update pump unwind the menus.
          state.pendingRestore = entry.seq
        end,
      }))
  end

  local function openBackups(game)
    local ListMenu = mod.ui and mod.ui.ListMenu
    if not ListMenu then return end
    local index = readIndex(game)
    local items = {}
    -- newest first: the row a player wants is almost always the last one taken
    for i = #index.list, 1, -1 do
      local entry = index.list[i]
      items[#items + 1] = { label = stamp(game, entry.at), value = entry }
    end
    game.stack:push(ListMenu.new(game, "BACKUPS", items, {
      kind = "gen1autosave_backups",
      footer = #items == 0 and "No backups yet." or nil,
      onChoose = function(item)
        if item and item.value then confirmRestore(game, item.value) end
      end,
    }))
  end

  -- ---------- the quit save
  --
  -- Picking QUIT is the last moment the game is still fully alive: the engine
  -- is still pumping, and an upload started here runs its course normally.
  -- Writing at the other end -- inside the engine's quit hook, whichever exit
  -- it is -- is what kept manufacturing conflicts, because a write there can
  -- only ever be a revision nothing gets to finish sending.
  --
  -- So the save goes here, but as an offer rather than a surprise: the
  -- confirm box says it is going to save, and YES then holds the quit until
  -- the write and its upload are done.  A save the player did not ask for,
  -- taken behind a box that says nothing about it, is the same silent write
  -- this mod spends the rest of its time avoiding.

  -- Is there a save worth offering?  A clean save has nothing to write, and a
  -- conflict is the one condition this mod never writes under -- in either
  -- case the vanilla prompt is the honest one, because it promises nothing.
  local function quitSaveOffered(game)
    if not (on() and mod.options:get("onquit")) then return false end
    if type(game.writeSave) ~= "function" then return false end
    -- the flow ends by quitting itself, so there has to be a quit to make
    if type(game.returnToTitle) ~= "function" then return false end
    if not (state.dirty and not state.inBattle) then return false end
    local engine = syncEngineOf(game)
    if engine and syncConflicted(engine) then return false end
    local ow = game.overworld
    -- no overworldIdle here: the start menu is on top of it by definition.
    -- Mid-script and mid-step are still reasons to leave the file alone.
    if not ow then return false end
    if (ow.runner and ow.runner.isRunning and ow.runner:isRunning())
        or #(ow.scriptMoves or {}) > 0
        or ow.teleportOut or ow.transitioning then
      return false
    end
    return true
  end

  -- Same defaultNo the engine's own QUIT box uses, so a mis-picked QUIT still
  -- costs one B press.  YES only parks the request: the text box is still
  -- tearing itself down here, the same reason the rollback confirm parks its.
  local function askQuit(game)
    local TextBox = mod.ui and mod.ui.TextBox
    if not (TextBox and game.stack) then return false end
    return pcall(function()
      game.stack:push(TextBox.new(game, QUIT_PROMPT, nil, {
        defaultNo = true,
        choice = function(yes)
          if yes then state.quit = { waited = 0 } end
        end,
      }))
    end)
  end

  local function finishQuit(game)
    local box = state.quit and state.quit.box
    state.quit = nil
    state.notify = 0            -- nothing of ours belongs on the title screen
    if pcall(function() return game:returnToTitle() end) then return end
    -- returnToTitle empties the stack, hold box and all.  If it somehow did
    -- not happen, that box is ours to take down rather than leave up.
    pcall(function()
      if type(box) == "table" and game.stack:top() == box then
        game.stack:pop()
      end
    end)
  end

  -- The quit, a frame at a time, behind the game's own "Now saving..." box.
  -- `stay` is a box that waits for nothing and pops for nobody, so it holds
  -- the screen -- and the player's input -- until the quit takes it down with
  -- the rest of the stack.  QUIT_WAIT bounds the whole thing: a save that
  -- cannot be finished is not worth stranding someone in front of.
  local function stepQuit(game, dt)
    local q = state.quit
    q.waited = q.waited + dt
    local timedOut = q.waited >= QUIT_WAIT

    if not q.box then
      local TextBox = mod.ui and mod.ui.TextBox
      local pushed = TextBox and game.stack and pcall(function()
        q.box = TextBox.new(game, QUIT_SAVING, nil,
          { stay = { onShown = function() q.typed = true end } })
        game.stack:push(q.box)
      end)
      -- no box to be had: still save, just without the hold in front of it
      if not (pushed and q.box) then q.box, q.typed = true, true end
    end
    -- The write waits for the box to finish typing, the way the manual save's
    -- does.  A box that never types out must not strand the quit, though.
    if not (q.typed or timedOut) then return end

    local engine = syncEngineOf(game)
    if not q.written then
      -- a transfer in flight is the same reason to wait here as anywhere
      -- else: writing under one either races it or hands sync a second
      -- revision to reconcile
      if engine and syncTransferring(engine) and not timedOut then return end
      q.written = true
      write(game)
      -- Pull the upload forward.  The five second debounce exists to coalesce
      -- a burst of writes; on the way out there is no burst coming, only a
      -- player waiting on this box.
      if engine then
        pcall(function()
          if engine.uploadAt then engine.uploadAt = engine.clock or 0 end
        end)
      end
      return
    end

    -- The save is on this device; now wait for it to be somewhere else too.
    -- Timing out costs little: QUIT goes to the title, not out of the
    -- process, so an upload still running finishes on the title screen --
    -- unless the player closes the game from under it, which is the case
    -- this wait is here for.
    if engine and syncOwesUpload(engine) and not timedOut then return end
    finishQuit(game)
  end

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn(game, items)
    if type(out) ~= "table" then return out end
    if on() and mod.options:get("onquit") then
      for _, item in ipairs(out) do
        local isQuit = item.id == "quit" or item.label == "QUIT"
        if isQuit and type(item.onSelect) == "function"
            and not item.gen1autosaveWrapped then
          local original = item.onSelect
          item.gen1autosaveWrapped = true
          item.onSelect = function(...)
            -- our box replaces the engine's, so it is this or that, never
            -- both; anything that stops us falls back to the vanilla prompt
            if not state.quit and quitSaveOffered(game) and askQuit(game) then
              return
            end
            return original(...)
          end
        end
      end
    end
    if not (on() and mod.options:get("backups")) then return out end
    local row = {
      label = "BACKUPS",
      onSelect = function() openBackups(game) end,
    }
    if mod.ui and mod.ui.insertBefore then
      mod.ui.insertBefore(out, "QUIT", row)
    else
      out[#out + 1] = row
    end
    return out
  end)

  -- Restoring needs the same settled overworld a capture does, so it waits for
  -- the menus to come down instead of forcing them.
  local function stepRestore(game)
    local seq = state.pendingRestore
    if not seq then return end

    local top = game.stack and game.stack:top()
    if top ~= game.overworld then
      -- unwind the backups list / start menu, one screen per frame
      if game.stack and game.stack.pop then
        state.popped = (state.popped or 0) + 1
        if state.popped > 8 then
          state.pendingRestore, state.popped = nil, nil
          return
        end
        pcall(function() game.stack:pop() end)
      end
      return
    end
    state.popped = nil

    local ok, checkpoint = pcall(function()
      return mod.storage:read(game, slotKey(seq))
    end)
    if not ok or type(checkpoint) ~= "table" then
      state.pendingRestore = nil
      say(game, "That backup could\nnot be read.")
      return
    end

    local ok2, result, code, message = pcall(function()
      return mod.checkpoints:restore(game, checkpoint)
    end)
    if ok2 and result == true then
      state.pendingRestore, state.retries = nil, nil
      -- Persist immediately so the file (and the next sync upload) carries the
      -- rolled-back state rather than the newer one it replaced.
      state.dirty = true
      state.lastWriteAt = -math.huge
      state.notifyText = "LOADED"
      request()
      return
    end
    -- These refusals mean "not this frame": a script, an animation or a step
    -- in flight.  Keep the request parked and try again.
    local TRANSIENT = {
      screen_busy = true, script_busy = true, animation_busy = true,
      movement_busy = true, transition_busy = true,
    }
    if ok2 and TRANSIENT[code] then
      state.retries = (state.retries or 0) + 1
      if state.retries < 600 then return end
    end
    state.pendingRestore, state.retries = nil, nil
    say(game, type(message) == "string" and message
      or "That backup could\nnot be restored.")
  end

  -- ---------- indicator

  -- An 8x8 ball, the size the games themselves use for a ball icon.  Drawn as
  -- plain rectangles rather than an image asset: there is no ball sprite a mod
  -- can reach (the battle ones live in the animation tilesets), and 64 filled
  -- pixels cost nothing next to loading a texture.
  --   1 outline  2 top shell  3 bottom shell  4 band  5 button
  local BALL = {
    { 0, 0, 1, 1, 1, 1, 0, 0 },
    { 0, 1, 2, 2, 2, 2, 1, 0 },
    { 1, 2, 2, 2, 2, 2, 2, 1 },
    { 1, 4, 4, 5, 5, 4, 4, 1 },
    { 1, 3, 3, 3, 3, 3, 3, 1 },
    { 1, 3, 3, 3, 3, 3, 3, 1 },
    { 0, 1, 3, 3, 3, 3, 1, 0 },
    { 0, 0, 1, 1, 1, 1, 0, 0 },
  }
  local BALL_COLORS = {
    { 0.09, 0.09, 0.09 },
    { 0.85, 0.25, 0.22 },
    { 0.97, 0.97, 0.97 },
    { 0.09, 0.09, 0.09 },
    { 0.97, 0.97, 0.97 },
  }
  local BALL_SIZE = 8
  local SHAKE_START, SHAKE_PERIOD, SHAKE_COUNT = 0.18, 0.34, 3
  local FADE_TIME = 0.25

  -- Which of the three shapes shows this frame.  The wobble is quantized to
  -- -1/0/+1 instead of a smooth angle because the original does the same: it
  -- swaps in pre-tilted tiles rather than rotating anything.
  local function tiltAt(elapsed)
    if elapsed < SHAKE_START then return 0 end
    local since = elapsed - SHAKE_START
    if since >= SHAKE_PERIOD * SHAKE_COUNT then return 0 end
    local phase = (since % SHAKE_PERIOD) / SHAKE_PERIOD
    local s = math.sin(phase * 2 * math.pi)
    if math.abs(s) < 0.45 then return 0 end
    return s > 0 and 1 or -1
  end

  -- Poor man's rotation, again the way the hardware does it: the top of the
  -- ball leans one way, the base the other, the band stays put.
  local function rowShift(tilt, row)
    if tilt == 0 then return 0 end
    if row <= 2 then return tilt end
    if row >= 7 then return -tilt end
    return 0
  end

  local function drawBall(g, elapsed, alpha)
    local tilt = tiltAt(elapsed)
    for row = 1, BALL_SIZE do
      local shift = rowShift(tilt, row)
      for col = 1, BALL_SIZE do
        local value = BALL[row][col]
        if value ~= 0 then
          local color = BALL_COLORS[value]
          g.setColor(color[1], color[2], color[3], alpha)
          g.rectangle("fill", col - 1 + shift, row - 1, 1, 1)
        end
      end
    end
  end

  -- Is the mobile FAITHFUL RATIO lock on?  This is the whole question behind
  -- where a corner badge belongs, and the engine answers it exactly this way
  -- in four places of its own (Renderer:endFrame's screen veil, the battle
  -- band, the letterbox fills): FaithfulRes.scaleCap() is the locked scale on
  -- a phone, and nil everywhere else.  Looked up lazily and cached, since a
  -- Gen 2 host has no such module; the LOCK ITSELF is re-read every time,
  -- because the player can turn it on and off in OPTIONS mid-game.
  local FaithfulRes = nil     -- nil = not looked up, false = no such module
  local function faithfulLock()
    if FaithfulRes == nil then
      local ok, loaded = pcall(require, "src.core.FaithfulRes")
      FaithfulRes = (ok and type(loaded) == "table" and loaded) or false
    end
    if not FaithfulRes or type(FaithfulRes.scaleCap) ~= "function" then
      return false
    end
    local ok, cap = pcall(FaithfulRes.scaleCap)
    return (ok and type(cap) == "number" and cap > 0) or false
  end

  local function drawNotify(viewport)
    if state.notify <= 0 then return end
    local mode = mod.options:get("notify")
    if mode == "off" then return end

    local g = love and love.graphics
    local Font = mod.ui and mod.ui.Font
    if not (g and viewport) then return end
    -- a held notice is text even in ball mode, so the font matters there too
    if not Font and (mode ~= "ball" or state.held) then return end

    local gx, gy = viewport.gameX or 0, viewport.gameY or 0
    local gw, gh = viewport.gameWidth or 0, viewport.gameHeight or 0
    if gw <= 0 or gh <= 0 then return end

    -- WHERE THE SCREEN IS depends on the FAITHFUL RATIO setting, which is why
    -- neither rect on its own was ever right.
    --
    -- gameX/gameWidth are the 160x144 UI canvas: the picture the engine's own
    -- text boxes are laid out in.  viewX/viewWidth are the whole surface the
    -- game is given.  With the lock OFF they are not the same thing and the UI
    -- canvas is not what the player is looking at -- the world pass is sized
    -- to cover the entire display, "so letterbox voids become more map instead
    -- of black bars" (Renderer:worldViewSize), and the UI canvas is only a box
    -- in the middle where the furniture goes.  A badge on its corner floats in
    -- the middle of the map.  With the lock ON the world pass is sized to the
    -- locked viewport instead, and everything outside it is dead display, so
    -- the picture IS the screen and a badge on the view's corner lands out in
    -- the black beside the game.
    --
    -- So: follow the world pass.  Same rule the engine uses for its own screen
    -- veil, which stops at the letterbox under the lock and covers the view
    -- without it.
    local ax, ay, aw, ah = gx, gy, gw, gh
    if not faithfulLock()
       and (viewport.viewWidth or 0) > 0 and (viewport.viewHeight or 0) > 0 then
      ax, ay = viewport.viewX or 0, viewport.viewY or 0
      aw, ah = viewport.viewWidth, viewport.viewHeight
    end

    local boxed = mode == "box"

    -- viewport.scale is Sp: FRAMEBUFFER pixels per GB pixel.  gameX/gameY/
    -- gameWidth/gameHeight are LOVE units -- Sp divided by the display's DPI
    -- scale.  Drawing at Sp inside a unit-space transform multiplies the panel
    -- by the DPI factor, which on a 3x phone screen is a box three times too
    -- wide that runs off the edge.  Sx/Sy (scale/dpi) is the unit scale, and
    -- the playfield width is the fallback when a field is missing.
    local sx = viewport.scale and viewport.scale / (viewport.dpiX or 1)
    local sy = viewport.scale and viewport.scale / (viewport.dpiY or 1)
    if not sx or sx <= 0 then sx = gw / (BOX_W * 8) end
    if not sy or sy <= 0 then sy = sx end

    -- The ball is its own little panel: sprite-sized, top right, and it fades
    -- on the way out instead of blinking off.
    if mode == "ball" and not state.held then
      local elapsed = NOTIFY_TIME - state.notify
      local alpha = 1
      if state.notify < FADE_TIME then alpha = state.notify / FADE_TIME end
      local bx = ax + aw - math.floor((BALL_SIZE + HUD_MARGIN) * sx)
      local by = ay + math.floor(HUD_MARGIN * sy)
      bx = math.max(ax, math.min(bx, ax + aw - BALL_SIZE * sx))
      by = math.max(ay, math.min(by, ay + ah - BALL_SIZE * sy))
      g.push("all")
      g.translate(bx, by)
      g.scale(sx, sy)
      drawBall(g, elapsed, alpha)
      g.pop()
      return
    end

    local tw = boxed and BOX_W or ICON_W
    local th = boxed and BOX_H or ICON_H
    local text
    if state.held then
      text = boxed and HELD_MESSAGE or HELD_ICON
    else
      text = boxed and MESSAGE_TEXT or (state.notifyText or ICON_TEXT)
    end
    local panelW, panelH = tw * 8, th * 8
    local textX = math.floor((panelW - #text * 8) / 2)

    -- The text box is the game's own furniture -- it stands in for the box the
    -- engine would have drawn -- so it goes where the engine's boxes go,
    -- centred on the UI canvas's bottom edge, whatever the rest of the screen
    -- is doing.  The small corner panel is a HUD badge like the ball, so it
    -- follows the ball to the screen's corner instead.
    local bx0, by0, bw0, bh0 = ax, ay, aw, ah
    if boxed then bx0, by0, bw0, bh0 = gx, gy, gw, gh end

    local x, y
    if boxed then
      x = gx + math.floor((gw - panelW * sx) / 2)
      y = gy + gh - math.floor(panelH * sy)
    else
      x = ax + aw - math.floor((panelW + HUD_MARGIN) * sx)
      y = ay + math.floor(HUD_MARGIN * sy)
    end
    -- never let a rounding error or an odd viewport push it off its own area
    x = math.max(bx0, math.min(x, bx0 + bw0 - panelW * sx))
    y = math.max(by0, math.min(y, by0 + bh0 - panelH * sy))

    g.push("all")
    g.translate(x, y)
    g.scale(sx, sy)
    Font.drawBox(0, 0, tw, th)
    g.setColor(0, 0, 0, 1)
    Font.draw(text, textX, 8)
    g.pop()
  end

  -- ---------- pumps

  mod.hooks:wrap("core.update", function(nextFn, game, dt)
    nextFn(game, dt)

    state.game = game
    state.clock = state.clock + dt
    if state.notify > 0 then state.notify = state.notify - dt end
    clearNotifyText()

    -- A quit in flight outranks everything, and outranks being switched off
    -- too: whatever else changes, the player is sitting in front of a box
    -- that only this can take down.
    if state.quit then
      stepQuit(game, dt)
      return
    end

    if not on() then return end

    -- A sync cycle that just finished left a heap full of decoded save slots
    -- behind it; pay for that here rather than on the route after it.
    settleSyncGarbage(game)

    -- A parked rollback outranks everything else this frame.
    if state.pendingRestore then
      stepRestore(game)
      return
    end

    -- Time accrues wherever the player is.  A long gym battle counts toward
    -- the interval, so "5 MIN" means five minutes of playing rather than five
    -- minutes of standing on a route doing nothing.
    local interval = intervalSeconds()
    if interval > 0 then
      state.elapsed = state.elapsed + dt
      if state.elapsed >= interval then request() end
    end

    if not state.due then return end
    if not state.dirty then
      -- nothing happened; don't spend a revision on it
      state.due = false
      state.elapsed = 0
      return
    end
    -- One floor, and it is about the file: no two writes closer than this,
    -- whatever asked for them.  There was a second and longer one between two
    -- EVENT saves, from when the timer did the steady work and events only
    -- had to catch what it missed.  Now that the events are the mechanism, a
    -- minute between them meant walking through a row of doors and saving at
    -- none of them -- which reads exactly like map entry not being a trigger
    -- at all.  MIN_GAP alone still caps a burst at one write per 20 seconds,
    -- which is the hammering the second floor was really there to stop.
    if state.clock - state.lastWriteAt < MIN_GAP then return end
    if not overworldIdle(game) then return end
    local settled, why = syncSettled(game)
    if not settled then
      tellHeld(why)
      return
    end
    state.heldTold = false

    write(game)
  end)

  mod.hooks:wrap("render.hud", function(nextFn, game, viewport)
    nextFn(game, viewport)
    drawNotify(viewport)
  end)

  -- The engine's quit hook writes nothing at all now.  Both ways out of it
  -- have the same shape: a write here can only produce a revision that
  -- nothing survives to finish sending, and a PUT the server applies while
  -- its reply dies with the process is exactly half of a "played at the same
  -- time" conflict.  The save that used to live here happens in the START
  -- menu's QUIT confirm instead, while there is still a game running to
  -- finish it -- and that quit waits for the upload before it goes.
  --
  -- What is left is the other half: disarm an upload that has been scheduled
  -- but not started, so the exit cannot cut one open. Nothing is lost by
  -- waiting -- the next launch sees an ordinary local change and uploads it.
  mod.hooks:wrap("core.quit_to_launcher", function(nextFn)
    local game = state.game
    if game then
      pcall(function()
        local engine = game:syncEngine()
        if type(engine) == "table" then engine.uploadAt = nil end
      end)
    end
    return nextFn()
  end)
end
