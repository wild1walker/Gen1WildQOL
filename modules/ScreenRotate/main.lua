-- ROTATE PROFILES -- the screen settings follow the phone.
--
-- Turn an iPhone or an Android phone sideways and the picture gets wider;
-- turn it back and it does not.  Which shape the game should be drawn in is
-- therefore two answers, and the engine's OPTION screen only holds one at a
-- time -- so a player who wants the widescreen battle in landscape has to go
-- and set it, and go and unset it, every time they turn the device.
--
-- This is the second answer.  A landscape profile is a set of screen
-- settings that go on when the display is wider than it is tall and come
-- straight back off when it is not.  The upright settings are never touched:
-- they are what the profile is put on top of, and what it puts back.
--
-- It covers the screen and nothing else -- see the SETTINGS table in
-- profile.lua for exactly which rows, and why the rest are not there.
--
-- What it is not: an orientation lock.  ORIENTATION on the engine's own
-- OPTION screen decides which way up the game is allowed to be
-- (src/core/Orientation.lua), and it is left alone.  Lock the game to
-- portrait there and this feature simply never has anything to do.
--
-- Desktop and console installs never see it act: the display does not rotate
-- and a resizable window that happens to be wide is not a phone held
-- sideways.  The mobile check is the engine's own, so POKEPORT_FORCE_MOBILE=1
-- drives the whole thing from a draggable desktop window.

-- How often the display is measured, in seconds.  A rotation is a rare event
-- with an animation in front of it, so a fifth of a second is invisible to
-- the player and costs the frame loop nothing between turns.
local INTERVAL = 0.2

return function(mod)
  -- A mod's `require` is sandboxed to engine modules, so this file's own
  -- sibling is loaded the supported way: mod:read, then load.
  local function loadModule(name)
    local relative = name .. ".lua"
    local source = mod:read(relative)
    if not source then
      mod.log:error("%s is missing from %s -- reinstall the mod",
        relative, tostring(mod.path))
      return nil
    end
    local chunk, compileError = load(source, "@" .. tostring(mod.path) .. "/" .. relative)
    if not chunk then
      mod.log:error("%s did not compile: %s", relative, tostring(compileError))
      return nil
    end
    local ok, value = pcall(chunk)
    if not ok then
      mod.log:error("%s failed to run: %s", relative, tostring(value))
      return nil
    end
    return value
  end

  local Profile = loadModule("profile")
  if not Profile then return end

  -- ---- the rows

  local schema = {
    {
      key = "enabled", type = "toggle", label = "ROTATE PROFILES", default = true,
      description = "TURNS THE PHONE'S SCREEN SETTINGS OVER TO THE LANDSCAPE PROFILE WHILE IT IS SIDEWAYS.",
    },
    {
      key = "sideways", type = "choice", label = "SIDEWAYS", default = "wide",
      choices = { { "WIDE", "wide" }, { "CUSTOM", "custom" } },
      description = "WIDE PUTS THE WIDESCREEN BATTLE ON AND THE 10:9 LOCK OFF. CUSTOM IS THE ROWS BELOW, YOURS TO SET.",
    },
  }
  for _, setting in ipairs(Profile.SETTINGS) do
    schema[#schema + 1] = {
      key = setting.key,
      type = "choice",
      label = setting.label,
      default = "same",
      choices = setting.choices,
      description = setting.description,
      -- The preset answers these rows itself, so they are only worth showing
      -- when the player is the one answering them.
      visible_if = { key = "sideways", equals = "custom" },
    }
  end
  mod.options:define(schema)

  local function get(key) return mod.options:get(key) end

  -- ---- the display

  local function engine(name)
    local ok, module = pcall(require, "src.core." .. name)
    if ok and type(module) == "table" then return module end
    return nil
  end

  -- Whether this is a device whose screen turns.  Asked once: it cannot
  -- change while the process runs, and the engine's own answer
  -- (src/core/FaithfulRes.lua) is the one that honours POKEPORT_FORCE_MOBILE,
  -- which is how the whole feature is driven on a desktop window.
  local mobile = (function()
    local FaithfulRes = engine("FaithfulRes")
    if FaithfulRes and type(FaithfulRes.isMobile) == "function" then
      local ok, value = pcall(FaithfulRes.isMobile)
      if ok then return value == true end
    end
    local Platform = engine("Platform")
    if Platform and type(Platform.detect) == "function" then
      local ok, detected = pcall(Platform.detect)
      if ok and type(detected) == "table" then return detected.mobile == true end
    end
    return false
  end)()

  local function sideways()
    local graphics = love and love.graphics
    if not (graphics and graphics.getDimensions) then return false end
    local ok, width, height = pcall(graphics.getDimensions)
    if not ok then return false end
    return Profile.landscape(width, height)
  end

  -- Three of the covered settings are live module state rather than a value
  -- read back out of the options table each frame, so writing the option is
  -- only half of setting them.  The rest -- the battle layout, size and HUD,
  -- and the UI layout -- are read from `save.options` where they are used, so
  -- writing the option is the whole of it.
  --
  -- This is deliberately not Game:applyOptions: that re-pushes the palette,
  -- the shader chain, the music and the input bindings as well, and a
  -- rotation has nothing to say about any of them.
  local PUSH = {
    faithfulRes = function(value)
      local FaithfulRes = engine("FaithfulRes")
      if FaithfulRes and FaithfulRes.apply then FaithfulRes.apply(value) end
    end,
    uiLetterbox = function(value)
      local ok, Letterbox = pcall(require, "src.render.Letterbox")
      if ok and type(Letterbox) == "table" and Letterbox.setMode then
        Letterbox.setMode(value)
      end
    end,
    screenPos = function(value)
      local ScreenPosition = engine("ScreenPosition")
      if ScreenPosition and ScreenPosition.setMode then
        ScreenPosition.setMode(value)
      end
    end,
  }

  local function push(options, touched)
    for key in pairs(touched) do
      local apply = PUSH[key]
      if apply then pcall(apply, options[key]) end
    end
  end

  -- ---- state

  -- engine key -> { value = the upright value }, for every setting the
  -- landscape profile is currently holding.  Empty means upright, or nothing
  -- to hold.
  local held = {}
  -- engine key -> the value this feature last wrote.  See Profile.reconcile.
  local applied = {}
  -- The options table these two were measured against.  Loading a save can
  -- hand the game a different one, and values taken off the old table have no
  -- business being written back into the new.
  local measured = nil
  local elapsed = INTERVAL

  -- ---- keeping the upright settings the ones on disk
  --
  -- This feature never persists a profile: it writes the landscape values
  -- into the live options table and takes them back out again, and options.lua
  -- keeps saying what the player set upright.  That is what makes a phone
  -- killed while sideways harmless.
  --
  -- Except that anything else may persist the options while the profile is
  -- on -- turning the music down on the engine's OPTION screen writes the
  -- whole table -- and that would put the landscape values on disk as if the
  -- player had chosen them there.  So the write is guarded: while the profile
  -- is holding settings, whatever calls writeOptions writes the upright
  -- values for those settings and the live table is put back afterwards.
  local guardedGame = nil
  local guards = setmetatable({}, { __mode = "k" })

  local function guardWrites(game)
    if guardedGame == game then return end
    local original = game.writeOptions
    if type(original) ~= "function" then return end
    -- Already ours, reached through a game object we had not seen before.
    -- Wrapping a wrapper would swap the values twice and write the wrong set.
    if guards[original] then guardedGame = game return end

    local guarded = function(self, ...)
      local options = self and self.save and self.save.options
      if type(options) ~= "table" or next(held) == nil then
        return original(self, ...)
      end
      local live = {}
      for key, box in pairs(held) do
        live[key] = { value = options[key] }
        options[key] = box.value
      end
      local ok, err = pcall(original, self, ...)
      for key, box in pairs(live) do options[key] = box.value end
      if not ok then error(err, 0) end
    end

    guards[guarded] = true
    game.writeOptions = guarded
    guardedGame = game
  end

  -- ---- the frame

  local function follow(game)
    if type(game) ~= "table" then return end
    local options = game.save and game.save.options
    if type(options) ~= "table" then return end

    -- A different options table is a different set of upright values; the old
    -- ones are gone with the table they came from.  Nothing is written back,
    -- because nothing on the new table was ever taken.
    if measured ~= options then
      held, applied, measured = {}, {}, options
    end

    local wanted = {}
    if mobile and sideways() then wanted = Profile.target(get, options) end

    local touched = Profile.reconcile(wanted, options, held, applied)
    if next(touched) == nil then return end

    guardWrites(game)
    push(options, touched)
  end

  -- `core.update` is the engine's own per-frame seam for a mod that has to
  -- watch something outside the game (docs/modding.md).  Vanilla runs
  -- whatever `next` is, unconditionally, and so does this: the profile is
  -- decided before the frame and the frame is never skipped.
  mod.hooks:wrap("core.update", function(next_, game, dt)
    elapsed = elapsed + (tonumber(dt) or 0)
    if elapsed >= INTERVAL then
      elapsed = 0
      follow(game)
    end
    return next_(game, dt)
  end)
end
