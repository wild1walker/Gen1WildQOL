-- The Mew gate (SPEC 5): a thing found in the world flips a flag, and only
-- then does Mew become a very-rare renewable encounter.
--
-- What the gate is, decided: read all four Pokemon Mansion journals.
--
--   Diary: July 5   Guyana, South America
--                   A new #MON was discovered deep in the jungle.
--   Diary: July 10  We christened the newly discovered #MON, MEW.
--   Diary: Feb. 6   MEW gave birth. ...
--   Diary; Sept. 1  MEWTWO is far too powerful. ...
--
-- They are the game's own in-world text about Mew's origin, they sit on three
-- separate floors of a late-game optional dungeon, and a player who reads
-- everything finds them without being told to.  Discoverable but not
-- guessable, which is the bar: nothing here can be reached by walking into
-- grass four thousand times.
--
-- Three things make this safe to ship:
--
--   * The unlock is an EVENT FLAG, not a save-schema addition, so it survives
--     uninstall and reinstall cleanly and the debug console can inspect it
--     with `flag GEN151_MEW_FOUND` / set it with `flag GEN151_MEW_FOUND on`.
--   * Before the flag is set, MEW is not in data.encounters AT ALL.  This is
--     the one placement that has to be populated at runtime rather than at
--     load, because src/ui/TownMap.lua scans the live table when AREA is
--     opened -- so a load-time append would let the dex spoil the location
--     the moment anyone pressed AREA.  Verified: TownMap.new does that scan
--     inside its constructor, i.e. on every push, so a table mutated at
--     runtime is picked up and a table not yet mutated shows nothing.
--   * The whole feature sits behind a mod option that defaults OFF.  It is an
--     invention rather than a restoration.

local M = {}

local FOUND = "GEN151_MEW_FOUND"

-- The four journals, by the TEXT constant their map object carries.  Read out
-- of the map object tables rather than from coordinates: pokered and
-- pokeyellow agree on the constants and on which floor each one is, and a
-- constant survives a map edit that moves the bookshelf.
local JOURNALS = {
  TEXT_POKEMONMANSION2F_DIARY1 = "GEN151_MEW_DIARY_1",
  TEXT_POKEMONMANSION2F_DIARY2 = "GEN151_MEW_DIARY_2",
  TEXT_POKEMONMANSION3F_DIARY = "GEN151_MEW_DIARY_3",
  TEXT_POKEMONMANSIONB1F_DIARY = "GEN151_MEW_DIARY_4",
}

local TOTAL = 4

function M.new(mod, ctx)
  local gate = { mod = mod, ctx = ctx, rows = {} }

  local function world()
    return mod.world
  end

  function gate.unlocked()
    local w = world()
    return w ~= nil and w:getFlag(FOUND) == true
  end

  -- Add or remove MEW's appended slots so the live table always agrees with
  -- the flag.  Idempotent, and safe to call on every save load: a player who
  -- switches saves must not carry the other save's unlock into the dex.
  function gate.sync()
    local game = mod.game
    local data = game and game.data
    if not (data and data.encounters) then return end
    local on = gate.unlocked()
    for _, row in ipairs(gate.rows) do
      local record = data.encounters[row.map]
      local group = record and record[row.method == "water" and "water" or "grass"]
      local slots = group and group.slots
      if slots then
        -- drop any slot we previously added, from the end, so a vanilla slot
        -- of the same species (there is none, but a mod could add one) is
        -- never touched
        for i = #slots, 1, -1 do
          if slots[i].__gen151 then table.remove(slots, i) end
        end
        if on then
          slots[#slots + 1] = { species = row.species, level = row.levels[1],
                                __gen151 = true }
        end
      end
    end
  end

  function gate.install(rows)
    for _, row in ipairs(rows) do
      if row.gated == "mew" then gate.rows[#gate.rows + 1] = row end
    end
    if #gate.rows == 0 then return end

    -- The flag lives on the save, so the live table has to be re-synced
    -- whenever the save changes underneath it.
    mod.events:on("save.loaded", function() gate.sync() end)
    mod.events:on("save.created", function() gate.sync() end)
    mod.events:on("game.ready", function() gate.sync() end)

    mod.hooks:wrap("world.talk", function(nextLink, overworld, npc)
      local textId = npc and npc.def and npc.def.text
      local flag = textId and JOURNALS[textId]
      if not flag then return nextLink(overworld, npc) end

      local w = world()
      if not w then return nextLink(overworld, npc) end
      if w:getFlag(FOUND) == true then return nextLink(overworld, npc) end

      w:setFlag(flag, true)
      local read = 0
      for _, name in pairs(JOURNALS) do
        if w:getFlag(name) == true then read = read + 1 end
      end
      if read < TOTAL then return nextLink(overworld, npc) end

      -- The last one.  Let the journal print exactly as it always does, then
      -- extend the box the vanilla path just pushed rather than pushing a
      -- second one on top of it -- a box pushed here would be shown FIRST
      -- and the journal second, which reads backwards.
      local result = nextLink(overworld, npc)
      w:setFlag(FOUND, true)
      gate.sync()
      local game = mod.game
      local box = game and game.stack and game.stack.top and game.stack:top()
      local TextBox = mod.ui.TextBox
      local extra = "The last page is\nloose.\fSomething small\nwas here,\fand is not now."
      if box and type(box.pages) == "table" and box.maxCols then
        for _, page in ipairs(TextBox.paginate(
            TextBox.substitute(game, extra), box.maxCols)) do
          box.pages[#box.pages + 1] = page
        end
      elseif game then
        game.stack:push(TextBox.new(game, extra))
      end
      mod.log:info("the Mansion journals are all read; MEW is now in the "
        .. "table (flag %s)", FOUND)
      return result
    end)
  end

  return gate
end

return M
