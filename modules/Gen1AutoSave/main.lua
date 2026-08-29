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
--     conflict OVER THIS SAVE; the save is retried once sync settles
--   * a "conflict" whose two sides share a sessionStart is this device's own
--     lost upload, not a second player: answered with keep-this-device rather
--     than put to the player, who has nothing to decide
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
  local HOLD_GRACE = 15     -- a conflict has to stand this long to be said
  local HEAL_TRIES = 3      -- give up healing one key after this many goes
  local NOTIFY_TIME = 1.6
  local GC_STEP = 4096      -- collector work per step, in KB of allocation
  local GC_STEPS = 12       -- ceiling: a cycle on a game-sized heap, no more
  local UPLOAD_GAP = 300    -- least time between two autosave-woken uploads
  local SYNC_HOLD_MAX = 3   -- longest a mid-step frame may hold a sync cycle
  local LOAD_WAIT = 45      -- longest a due save waits for a loading screen

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
    syncHeld = 0,
    dueAt = nil,
    notify = 0,
    heldTold = false,
    heldSince = nil,
    healKey = nil,
    healTries = 0,
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
      key = "heal",
      type = "toggle",
      label = "HEAL CONFLICTS",
      default = true,
      help = "Answer a sync conflict with your own older upload on both sides.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "on_load",
      type = "toggle",
      label = "SAVE ON LOADS",
      default = true,
      help = "Write during the screen a warp or a battle already blacks out.",
      visible_if = { key = "enabled", equals = true },
    },
    {
      key = "quiet_sync",
      type = "toggle",
      label = "QUIET SYNC",
      default = true,
      help = "Hold a sync cycle out of the frames you are mid-step in.",
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

  -- WHOSE conflict is it?  engine.phase is one word for the whole engine, but
  -- the disagreement it stands for is always about one save: the planner walks
  -- every local file it can see and raises a row per key that changed on both
  -- ends (SyncEngine:_planFrom -> _addConflict), so an old playthrough this
  -- account also has on another device turns the phase to "conflict" while the
  -- file we are playing is not in dispute at all.  Holding this game's writes
  -- for that buys nothing -- our save is not the one with two sides.
  --
  -- engine.protectedKey is the key of the save being played.  It is not stale:
  -- Game:syncEngine() re-stamps it from the live save on every call, and
  -- syncEngineOf just made that call.
  local function conflictIsOurs(engine)
    local key, rows
    pcall(function() key = engine.protectedKey end)
    pcall(function() rows = engine.conflicts end)
    -- An engine that cannot say which save it means, or which are in dispute,
    -- gets the careful answer: assume the hold is ours and leave the file be.
    if type(key) ~= "string" or type(rows) ~= "table" then return true end
    for _, row in ipairs(rows) do
      if type(row) == "table" and row.key == key then return true end
    end
    return false
  end

  -- Which conflict, in the terms the launcher's own screen uses for it: two
  -- savedAt stamps and the key they disagree about.  "A conflict is standing"
  -- is not something a player can go and check; "this device 21:42, other
  -- device 21:37" is the same line the SAVE SYNC screen will show them.
  local function stampText(meta)
    local at = type(meta) == "table" and tonumber(meta.savedAt)
    local ok, text = pcall(os.date, "%Y-%m-%d %H:%M", at or 0)
    return (at and ok) and text or "?"
  end

  local function conflictDetail(engine)
    local key, rows
    pcall(function() key = engine.protectedKey end)
    pcall(function() rows = engine.conflicts end)
    if type(rows) ~= "table" then return nil end
    for _, row in ipairs(rows) do
      -- no key to match on means we already gave the hold the careful reading,
      -- so describe the row that reading was about: the first one
      if type(row) == "table" and (type(key) ~= "string" or row.key == key) then
        return string.format("%s (this device %s, other device %s)",
          tostring(row.key), stampText(row.localMeta),
          stampText(row.remoteMeta))
      end
    end
    return nil
  end

  -- ---------- the conflict that is not one
  --
  -- "These saves were played at the same time" does not mean two people.
  -- SyncEngine.overlaps compares [sessionStart, savedAt] on the two sides, and
  -- ONE sessionStart covers a whole play session: Game.sessionStartedAt is
  -- stamped at init and at load, and SaveData.buildMeta copies it into every
  -- save meta written until the game is closed.  So two revisions of one
  -- session always overlap, and the wording is about the intervals rather than
  -- about devices.
  --
  -- When both sides carry the SAME sessionStart they are not two sessions at
  -- all.  A second device would have called os.time() for its own, on its own
  -- load of this playthrough; matching to the second is not something two
  -- machines do.  It is one device's file, twice.
  --
  -- Which happens with nobody doing anything wrong.  An upload the server
  -- commits but whose reply never lands -- a dropped connection, a phone
  -- putting the app to sleep -- leaves state.revs behind the rev the server
  -- now has.  The next plan then reads a save that moved on both ends:
  -- localChanged because we kept playing, remoteChanged because our own upload
  -- did arrive after all.  Nothing on this side can prevent that; by the time
  -- we could look, the reply is already lost.  It can only be recognised
  -- afterwards, and it has exactly one honest answer -- keep this device,
  -- which is the far copy's own successor rather than a rival to it.
  local function selfConflict(engine)
    local key, rows
    pcall(function() key = engine.protectedKey end)
    pcall(function() rows = engine.conflicts end)
    if type(key) ~= "string" or type(rows) ~= "table" then return nil end
    for _, row in ipairs(rows) do
      if type(row) == "table" and row.key == key then
        local mine = type(row.localMeta) == "table" and row.localMeta
        local theirs = type(row.remoteMeta) == "table" and row.remoteMeta
        if not (mine and theirs) then return nil end
        local ourStart, theirStart =
          tonumber(mine.sessionStart), tonumber(theirs.sessionStart)
        local ourSaved, theirSaved =
          tonumber(mine.savedAt), tonumber(theirs.savedAt)
        -- All of it, or it is a real disagreement and none of our business:
        -- one session, said by both sides, and the far side is the revision
        -- ours came after rather than one that went somewhere else.
        if ourStart and theirStart and ourStart > 0 and ourStart == theirStart
            and ourSaved and theirSaved and theirSaved <= ourSaved then
          return row
        end
        return nil        -- one row per key; this was ours and it did not fit
      end
    end
    return nil
  end

  -- Answer it once, the way the player would have had to.  resolveConflict is
  -- the launcher's own "Keep this device" button: it points state.revs at the
  -- rev we never heard about and force-uploads the file we are actually
  -- playing, which is what the lost reply was trying to say to begin with.
  --
  -- Capped, because a heal that keeps coming back is a heal that is wrong
  -- about something.  After HEAL_TRIES on one key the mod stops and lets the
  -- badge and the launcher have it, which is where this used to start.
  local function healSelfConflict(engine)
    if not mod.options:get("heal") then return false end
    if type(engine.resolveConflict) ~= "function" then return false end
    local row = selfConflict(engine)
    if not row then return false end
    if state.healKey ~= row.key then
      state.healKey, state.healTries = row.key, 0
    end
    if state.healTries >= HEAL_TRIES then return false end
    state.healTries = state.healTries + 1
    local ok, done = pcall(engine.resolveConflict, engine, row.key, "local")
    if not (ok and done ~= false) then return false end
    mod.log:info("autosave healed a self-conflict on %s: our own upload from "
      .. "%s, against the file we are still playing (%s)",
      tostring(row.key), stampText(row.remoteMeta), stampText(row.localMeta))
    return true
  end

  local function syncConflicted(engine)
    local conflict = false
    pcall(function() conflict = engine.phase == "conflict" end)
    return conflict and conflictIsOurs(engine)
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

  -- And where the last of it lands.
  --
  -- Pacing chose how OFTEN a cycle runs.  It could not choose WHEN the
  -- expensive part of one happens, and that is the half the player actually
  -- feels.  The plan is built against the server's REPLY, not against the
  -- request: SyncEngine:update polls the handle, and the frame the answer
  -- lands on runs _planFrom, which is the decode of every slot.  So the stall
  -- arrives on network time -- a moment set by latency and the server, with no
  -- relation to anything the player did.  That is exactly why it reads as the
  -- game hiccupping rather than as the game syncing: nothing on screen caused
  -- it, and nothing on screen explains it.  The engine's own five minute sweep
  -- lands the same way, and pacing never touched that one at all.
  --
  -- The work cannot be made cheap from here.  It can be made to land where it
  -- does not show.  A frame dropped while the player is standing still, in a
  -- menu, reading a box or in a battle is a frame nobody sees.  The same frame
  -- dropped mid-step is a visible stutter, because the walk cycle and the
  -- camera are both part-way between tiles and both jump when one frame is
  -- worth two.
  --
  -- So a sync cycle with a reply in hand is not ticked while the player is
  -- mid-step.  The engine's clock stops with it, so nothing fires early
  -- afterwards to make the time back, and the first frame the player is not
  -- mid-step it runs -- which is a fraction of a second later, because a step
  -- IS a fraction of a second.  Any menu, text box, battle, doorway or pause
  -- releases it immediately: all of them take the overworld off the top of the
  -- stack, and none of them is a frame a dropped frame shows in.
  --
  -- Only when a reply is actually in flight.  A tick with nothing pending is
  -- the cheap one that STARTS a cycle, and holding that would stop the clock
  -- for no reason.  And held for at most SYNC_HOLD_MAX, so a player holding a
  -- direction across Route 21 cannot starve sync -- after that it runs
  -- wherever it lands, the way it always did.
  local function midStride(game)
    local ow = game and game.overworld
    if not (ow and ow.player) then return false end
    if game.stack and game.stack.top and game.stack:top() ~= ow then
      return false
    end
    return ow.player.moving and true or false
  end

  local function holdSyncWhileWalking(game)
    local engine = syncEngineOf(game)
    if not engine or engine.gen1autosaveHeld then return end
    local update = engine.update
    if type(update) ~= "function" then return end
    engine.gen1autosaveHeld = true
    engine.update = function(self, dt)
      local hold = on()
        and mod.options:get("quiet_sync") ~= false
        and self.pending
        and state.syncHeld < SYNC_HOLD_MAX
        and midStride(state.game)
      if hold then
        state.syncHeld = state.syncHeld + (tonumber(dt) or 0)
        return
      end
      state.syncHeld = 0
      return update(self, dt)
    end
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

  -- An unresolved sync conflict over this save holds every write, and staying
  -- quiet about that reads exactly like the mod having stopped working.  Said
  -- once per hold, not once per frame: it is a standing condition, not an
  -- event.
  --
  -- But only once it has actually stood.  "Conflict" was treated here as a
  -- state only the player can leave, and it is not one: SyncEngine:syncNow()
  -- empties self.conflicts and re-plans from scratch, and the upload-debounce
  -- path in SyncEngine:update() reaches it with no phase guard at all -- so a
  -- conflict raised by one plan can be gone by the next with nobody having
  -- answered anything.  Announcing on the first frame we see one turns that
  -- blip into a banner about a prompt the launcher will not be showing by the
  -- time the player goes to look for it.  A real conflict is waiting on a
  -- human and will still be here in HOLD_GRACE seconds; a blip will not.
  local function tellHeld(why, game)
    -- A transfer is seconds and clears itself: nothing to say, and it is not
    -- the condition the grace below is timing.
    if why == "transfer" then
      state.heldSince = nil
      return
    end
    -- nil is syncSettled inside its own SYNC_RETRY backoff -- no fresh reading
    -- either way, so the running grace stands rather than restarting.
    if why ~= "conflict" or state.heldTold then return end
    state.heldSince = state.heldSince or state.clock
    if state.clock - state.heldSince < HOLD_GRACE then return end
    state.heldTold = true
    announce(true)
    local engine = game and syncEngineOf(game)
    local detail = engine and conflictDetail(engine)
    if detail then
      mod.log:warn("autosave held: save sync is waiting on an answer to %s",
        detail)
    else
      mod.log:warn("autosave held: save sync is waiting on a conflict answer")
    end
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
      state.dueAt = nil
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
    if not state.due then state.dueAt = state.clock end
    state.due = true
  end

  -- ---------- writing on a loading screen
  --
  -- The write itself is not the expensive part -- the collector catching up on
  -- what it threw away is, and settleGarbage pays that in the same frame.  What
  -- makes it FELT is where that frame lands.  On the route it is a stutter in
  -- the middle of walking, which is the one place a dropped frame shows.
  --
  -- The game already blacks the screen out twice for its own reasons: a warp
  -- fades out, swaps the map and fades back, and a battle ends behind a hold
  -- and a fade.  Nobody can see a frame during either.  So a save that is due
  -- waits for one and goes there, and the cost is spent on a screen the player
  -- was already waiting through -- the loading screen is a few frames longer
  -- and nothing else changes.
  --
  -- map.entered rather than map.exited: exited fires at the top of setMap,
  -- before the new map is loaded, so a save written there records the map you
  -- just left and the position you left it from.  entered fires once the new
  -- map, the player's cell and the facing are all in place, and the transition
  -- is still up -- coherent state, screen still covered.
  --
  -- The overworld is NOT idle at either moment: the transition owns the top of
  -- the stack and the player has just been placed.  overworldIdle would refuse
  -- every one of these, so the load path asks the questions that still matter
  -- -- nothing in flight, sync settled -- and skips the one that is only there
  -- to keep a write off a moving player.
  local function loadScreenWrite(game, why)
    if not game then return end
    if not on() then return end
    if mod.options:get("on_load") == false then return end
    if state.quit or state.pendingRestore then return end
    if not (state.due and state.dirty) then return end
    if state.clock - state.lastWriteAt < MIN_GAP then return end
    local ow = game and game.overworld
    if ow and ow.player and ow.player.moving then return end
    if ow and ow.runner and ow.runner.isRunning and ow.runner:isRunning() then
      return
    end
    if not syncSettled(game) then return end
    mod.log:info("autosave on a %s screen", tostring(why))
    write(game)
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

  -- The two screens the game blacks out on its own.  Both fire while their
  -- transition is still up, so the write lands under it: a warp once the new
  -- map is in place, and a battle in the return hold before the fade back.
  mod.events:on("map.entered", function()
    loadScreenWrite(state.game, "warp")
  end)
  mod.events:on("battle.ended", function()
    loadScreenWrite(state.game, "battle")
  end)

  -- A manual save resets everything: the player just did the thing.  It is
  -- otherwise none of this mod's business -- writeSave notifies the sync
  -- engine itself, whoever called it.
  mod.events:on("save.writing", function()
    state.elapsed = 0
    state.dirty = false
    state.due = false
    state.dueAt = nil
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
    state.heldSince = nil
    state.held = false
    state.healKey, state.healTries = nil, 0
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

  -- A held save in POKE BALL mode is a cross, not the word PAUSED: the ball is
  -- a picture and its failure should be one too, in the same 8x8 slot in the
  -- same corner, so it reads as this indicator having gone wrong rather than
  -- as a second kind of furniture arriving.
  --   1 outline  2 stroke
  local CROSS = {
    { 1, 1, 0, 0, 0, 0, 1, 1 },
    { 1, 2, 1, 0, 0, 1, 2, 1 },
    { 0, 1, 2, 1, 1, 2, 1, 0 },
    { 0, 0, 1, 2, 2, 1, 0, 0 },
    { 0, 0, 1, 2, 2, 1, 0, 0 },
    { 0, 1, 2, 1, 1, 2, 1, 0 },
    { 1, 2, 1, 0, 0, 1, 2, 1 },
    { 1, 1, 0, 0, 0, 0, 1, 1 },
  }
  local CROSS_COLORS = {
    { 0.09, 0.09, 0.09 },     -- the ball's own outline: same family
    { 0.90, 0.22, 0.20 },     -- a shade off the shell red: this is not a ball
  }
  -- It blinks instead of wobbling.  Hard on/off on a fixed period, the way the
  -- hardware blinks anything, and the off half dims rather than disappears --
  -- a shape that vanishes outright for 200ms reads as a dropped frame.
  local BLINK_PERIOD = 0.4
  local BLINK_DIM = 0.28

  local function drawCross(g, elapsed, alpha)
    local on = (elapsed % BLINK_PERIOD) < BLINK_PERIOD / 2
    local a = alpha * (on and 1 or BLINK_DIM)
    for row = 1, BALL_SIZE do
      for col = 1, BALL_SIZE do
        local value = CROSS[row][col]
        if value ~= 0 then
          local color = CROSS_COLORS[value]
          g.setColor(color[1], color[2], color[3], a)
          g.rectangle("fill", col - 1, row - 1, 1, 1)
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
    -- ball mode draws both of its states, held included, so it needs no font
    if not Font and mode ~= "ball" then return end

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
    -- on the way out instead of blinking off.  The held cross shares the slot
    -- exactly -- same size, same corner, same fade -- so the two never move
    -- the indicator around between them.
    if mode == "ball" then
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
      if state.held then
        drawCross(g, elapsed, alpha)
      else
        drawBall(g, elapsed, alpha)
      end
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

    -- Installed on the engine instance the first frame there is one to install
    -- it on: sync is built lazily and a mod loaded before it would find
    -- nothing.  Idempotent, so this is a table lookup on every frame after.
    holdSyncWhileWalking(game)

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

    -- Give a loading screen first refusal.  A save that has only just come due
    -- waits, because a warp or a battle is usually seconds away and the cost
    -- is invisible on either.  LOAD_WAIT is the point at which waiting is worse
    -- than being seen: a player who has not changed maps or fought anything in
    -- three quarters of a minute is standing somewhere quiet, and a save on the
    -- route is better than no save at all.
    if mod.options:get("on_load") ~= false and state.dueAt
       and state.clock - state.dueAt < LOAD_WAIT then
      return
    end

    if not overworldIdle(game) then return end
    local settled, why = syncSettled(game)
    if not settled then
      -- A conflict against our own lost upload is answerable here and now, and
      -- answering it is the difference between a save landing and a badge
      -- about a launcher screen that may not even be showing it yet.
      if why == "conflict" then
        local engine = syncEngineOf(game)
        if engine and healSelfConflict(engine) then return end
      end
      tellHeld(why, game)
      return
    end
    state.heldTold = false
    state.heldSince = nil
    state.healKey, state.healTries = nil, 0

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
