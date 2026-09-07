-- Gen2Celebi -- the GS BALL event, switched back on.
--
-- Crystal ships the whole Celebi event and cannot reach it.  Every piece is
-- in the cartridge: the receptionist in the Goldenrod POKeCENTER who hands
-- over the GS BALL, KURT taking it away to look at it, KURT giving it back
-- outside his house, the shrine in ILEX FOREST, the forest going quiet, the
-- level 30 CELEBI.  The engine implements the two specials the shrine calls
-- (CelebiShrineEvent and CheckCaughtCelebi, src/script/gen2/specials/
-- crystal_story.lua) and Save carries the flag byte.  None of it runs.
--
-- What stops it is one byte.  The Goldenrod scene asks the Mobile Stadium
-- whether a ball is waiting --
--
--     setval BATTLETOWERACTION_GSBALL
--     special BattleTowerAction
--     ifequal GS_BALL_AVAILABLE, .gsball
--     ../pokecrystal/maps/GoldenrodPokecenter1F.asm:17-21
--
-- and the answer comes out of sGSBallFlag, which only the Mobile Adapter GB
-- ever wrote.  No adapter, no flag, no ball, and the eleven scripts behind it
-- are dead data on every cartridge sold outside Japan.
--
-- So this mod writes the byte and stops.  It does not add an item, a script,
-- an NPC, a map or a line of text.  Everything the player then sees is the
-- cartridge's own event, in the cartridge's own words, in the order its
-- authors wrote it -- which is the whole point: the event is not missing, it
-- is unreachable, and the honest fix is a key rather than a reimplementation.
--
-- ------- Gold and Silver
--
-- There is nothing to switch on.  The GS BALL, the shrine script and CELEBI's
-- event do not exist in those two cartridges at all -- not gated, not unused,
-- absent -- so this feature does nothing there and says so once in the log.
-- CELEBI on GOLD and SILVER is the placement table's problem, not this file's.

-- The mod handle the loader hands a module at chunk scope.  Nil when this
-- file is loaded by the test bench, which is what lets the bench drive `arm`
-- without installing anything.
local mod = ...

local Celebi = {}

-- ../pokecrystal/ram/sram.asm:140 sGSBallFlag.  The engine spells the byte's
-- three live states as words (src/core/gen2/Save.lua:434) and treats any of
-- them as "a ball has been offered"; `have` is the one the adapter would have
-- left behind, so it is the one written here.
local FLAG = "have"

-- "gen1" | "gs" | "crystal" -- the engine's own word for lineage within a
-- generation, which is the right question to ask.  A version test would have
-- to be updated for every cartridge that ever gets an engine; this asks what
-- the running game IS.
local function lineage()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok or type(GameVersion) ~= "table" then return nil end
  if type(GameVersion.engine) ~= "function" then return nil end
  local okCall, value = pcall(GameVersion.engine)
  return okCall and value or nil
end

-- The flag lives on the save, so it is written on the save rather than
-- through src.core.gen2.Save: `crystalState` only fills in defaults, and the
-- special reads the same field back through it either way.  Writing the plain
-- table keeps this file free of an engine require and of the permission that
-- would come with one.
--
-- Idempotent by construction.  A save that has been through the event carries
-- `given` or `used`, and overwriting either with `have` would offer the ball
-- a second time -- so anything already set is left exactly as it is.
function Celebi.arm(save)
  if type(save) ~= "table" then return false end
  local crystal = save.crystal
  if type(crystal) ~= "table" then
    crystal = {}
    save.crystal = crystal
  end
  if crystal.gsBall ~= nil then return false end
  crystal.gsBall = FLAG
  return true
end

function Celebi.install(mod)
  local line = lineage()
  if line ~= "crystal" then
    -- Not a failure and not worth a warning: it is a fact about the
    -- cartridge.  GOLD and SILVER never had the event to lose.
    if line == "gs" then
      mod.log:info("GS BALL: GOLD and SILVER carry no CELEBI event to switch "
        .. "on -- CELEBI is placed instead")
    end
    return
  end

  local function arm(payload)
    local save = payload and payload.save
    if Celebi.arm(save) then
      mod.log:info("GS BALL: a ball is waiting in the GOLDENROD POKeCENTER")
    end
  end

  -- Both, for the reason legendaries.lua gives about map.entered: a save
  -- created this session never fires `save.loaded`, and one continued from
  -- the menu never fires `save.created`.
  mod.events:on("save.created", arm)
  mod.events:on("save.loaded", arm)
end

-- Installed at chunk scope, the way every other module in this bundle is:
-- the loader compiles the file and the file does its own wiring.  The table
-- is returned as well so tests/celebi_test.lua can reach `arm` directly --
-- with no mod handle there is nothing to install, so loading it costs
-- nothing.
if mod then Celebi.install(mod) end

return Celebi
