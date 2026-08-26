-- Gen1Sprint -- hold B to run, for Gen1Recomp (mod api 2).
--
-- FireRed's running shoes are twice walking speed: 16 frames per tile
-- becomes 8.  This gives you the same thing on a button you are already
-- holding nothing else with, and 8 frames per tile is a pace this engine
-- has always drawn -- it is what the BICYCLE rides at.
--
-- It is one link on the engine's own `movement.speed` hook, which exists
-- for exactly this ("running shoes, dash, etc." is the comment on it in
-- src/world/Player.lua).  Nothing is patched, nothing is polled, and the
-- work happens once per step rather than once per frame; src/sprint.lua
-- opens with the full cost argument.
--
-- Every knob is a row in MODS > Gen1Sprint > OPTIONS, and SPRINT: OFF
-- unsubscribes the hook outright, so switched off it is the untouched game.
--
-- The mod is split across src/*.lua for readability.  A mod's require is
-- sandboxed to engine modules and other mods' exports, so its own files are
-- loaded the supported way: mod:read through the loader's filesystem, then
-- load into this chunk's environment.  That works identically in the repo
-- and from an installed .zip.

local MODULE_DIR = "src/"

return function(mod)
  -- One place to turn a broken install into an attributed load error rather
  -- than a crash somewhere out on Route 1.
  local function loadModule(name)
    local relative = MODULE_DIR .. name .. ".lua"
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

  local Options = loadModule("options")
  if not Options then return end

  mod.options:define(Options.schema)
  local opt = Options.reader(mod)

  local Sprint = loadModule("sprint")
  if Sprint then
    mod.exports.sprint = Sprint.install(mod, opt, Options.MULTIPLIERS)
  end
end
