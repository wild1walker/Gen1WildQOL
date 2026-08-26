-- What the AREA map says about a Pokemon this mod placed.
--
-- The SCREEN is not this mod's any more.  Opening AREA on an entry you have
-- never met, the box under the map, the press that takes it down, the d-pad
-- that works again while it is down -- all of that lives in Gen1Dex now,
-- which is the mod that owns the POKeDEX and draws the rows the press lands
-- on.  Two releases were spent reaching that list from the outside: the
-- vanilla constructor had to be wrapped, then the rows it built had to be
-- stamped with their species so a dex mod replacing them wholesale did not
-- strand the lookup -- and Gen1Dex replaces them wholesale, which is exactly
-- the bug that shipped.  A content mod has no business owning a UI surface
-- it has to reach two screens deep to install.
--
-- What is left here is the half that was always this mod's: the SENTENCE.
-- The encounter tables can say "GRASS  Lv12" for anything the cartridge can
-- roll, and that is what Gen1Dex says on its own.  They cannot say which
-- tier this mod rolled a spawn at, that a map needs SURF to reach at all, or
-- that MEW's row exists but must not be spoken of yet.  Those are facts
-- about the placement, and the placement is here.
--
-- So this registers one provider (Gen1Dex's area.provide) and answers three
-- ways, which is the whole of the contract:
--
--   lines   this mod placed the species -- these words, from the same
--           resolved rows the spawn itself was built from, so a hint cannot
--           drift from the thing it describes
--   false   the species is this mod's and its answer is WITHHELD: MEW,
--           while its gate is shut.  Withholding is not the same as having
--           nothing to say, and it has to outrank the generic reading --
--           a caption would spoil the basement more precisely than a nest
--           ever could.  Gen1Dex then draws its own no-record line over the
--           map, which is what it draws over a species nobody can answer for
--           at all: MEW's sealed screen and ARTICUNO's are the same screen,
--           to the glyph, and a seal that read differently would tell the
--           player MEW is in there somewhere
--   nil     no opinion.  Every one of the other 128 species, which Gen1Dex
--           answers for out of the live encounter tables

local M = {}

-- install(mod, ctx) -> probe | nil
--
-- ctx.hints     the generated hint vocabulary (hints.lua)
-- ctx.rows      the resolved slot rows
-- ctx.fishing   the resolved Super Rod rows
-- ctx.unlocked  the MEW gate, or nil when the event is off
--
-- Returns the bench's probe -- what to print when a player asks why AREA is
-- not doing what the README says -- or nil when there is no Gen1Dex to hang
-- any of this on.
function M.install(mod, ctx)
  local Hints = ctx.hints

  -- Gen1Dex loads FIRST when it is installed at all: this mod names it in
  -- optional_dependencies, and the loader's guarantee for one of those is
  -- exactly that -- if it is present and active it loads before us, and if
  -- it is absent nothing blocks.  So a lookup here either finds a mod that
  -- has finished publishing its exports, or finds nothing; there is no third
  -- state to code around.
  local dex = mod.find("Gen1Dex")
  local area = dex and dex.exports and dex.exports.area
  if not area or type(area.provide) ~= "function" then
    if dex then
      mod.log:warn("Gen1Dex %s is installed but publishes no AREA surface, "
        .. "so this mod's hints have nowhere to go -- update it to 1.3.0 or "
        .. "newer", tostring(dex.version))
    else
      mod.log:info("AREA HINTS is on, but the AREA screen it writes on "
        .. "belongs to Gen1Dex, which is not installed -- install it and the "
        .. "hints turn up on their own")
    end
    return nil
  end

  -- The budget for the SECOND line, which is the tight one: the box puts its
  -- blinking prompt in that line's last column.  Asked for rather than
  -- assumed, so a change to the box over there does not silently make a
  -- caption over here one column too wide.
  local cols = tonumber(area.cols) or 17

  -- species -> the placement rows that are live RIGHT NOW.  Recomputed per
  -- ask rather than cached, because MEW's row is behind a flag and the
  -- answer changes when the flag does.
  local function rowsFor(species)
    local live, gated = {}, false
    for _, row in ipairs(ctx.rows or {}) do
      if row.species == species then
        if not row.gated then
          live[#live + 1] = row
        elseif ctx.unlocked and ctx.unlocked() then
          live[#live + 1] = row
        else
          gated = true
        end
      end
    end
    for _, row in ipairs(ctx.fishing or {}) do
      if row.species == species then live[#live + 1] = row end
    end
    return live, gated
  end

  -- Tagged with this mod's id, so a hot reload REPLACES this provider rather
  -- than stacking a second one closed over the previous load's rows.
  area.provide(function(_, species)
    local live, gated = rowsFor(species)
    if #live > 0 then return Hints.caption(live, cols) end
    -- placed, gated, and the gate is still shut: refuse, loudly enough that
    -- the encounter tables do not answer in our place.  What the player sees
    -- is Gen1Dex's no-record line -- the same one a legendary gets
    if gated then return false end
    return nil
  end, mod.id)

  mod.log:info("this mod's spawns caption themselves on Gen1Dex's AREA screen")

  -- What the bench prints.  Gen1Dex's own probe walks the chain from the dex
  -- list to the A handler; this adds the one link that is this mod's, which
  -- is whether the words ever got handed over.
  return function(game)
    local ours = "HINTS: ON\f"
    if type(area.probe) == "function" then
      local ok, report = pcall(area.probe, game)
      if ok and type(report) == "string" then return ours .. report end
      return ours .. "GEN1DEX's probe\ndid not run.\f" .. tostring(report)
    end
    return ours .. "GEN1DEX is here,\nbut has no probe."
  end
end

return M
