-- Gen1SoundQOL -- audio quality-of-life for Gen1Recomp (mod api 2).
--
-- The low-HP battle siren beeps a set number of times (six out of the
-- box) instead of looping for the rest of the fight.
--
-- The behaviour is optional and defaults to the least surprising setting;
-- every knob is a row in MODS > Gen1SoundQOL > OPTIONS.
--
-- The mod is split across src/*.lua for readability.  A mod's require is
-- sandboxed to engine modules and other mods' exports, so its own files are
-- loaded the supported way: mod:read through the loader's filesystem, then
-- load into this chunk's environment.  That works identically in the repo
-- and from an installed .zip.

local MODULE_DIR = "src/"

return function(mod)
  -- One place to turn a broken install into an attributed load error rather
  -- than a crash somewhere in the middle of a battle.
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

  local Alarm = loadModule("alarm")
  if Alarm then
    mod.exports.alarm = Alarm.install(mod, opt, Options.ALARM_CYCLE_FRAMES)
  end
end
