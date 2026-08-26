-- Gen1Remember: the REMEMBER popup, and the teach that follows it.
--
-- Two surfaces open this and neither owns it: the party menu's per-mon
-- submenu (through the engine's own ui.party.submenu hook) and Gen1BillsBox's
-- box popup (through the extension point it publishes).  Both hand over the
-- same three things -- the game, the mon, and a way to say the flow is done --
-- so the screen has no idea which one it is standing in front of, and a third
-- caller costs nothing.
--
-- ------- what it reuses rather than redraws
--
-- The four-move case is the engine's own MoveLearnMenu (src/ui/MoveLearnMenu.
-- lua): the "trying to learn / delete an older move?" prompt, the forget
-- list, the HM refusal, and the "1, 2 and... Poof!" pages.  Every one of
-- those is text a player already knows, and a mod that redrew them would get
-- one of them subtly wrong.  It is reached through Screens.push rather than
-- by requiring the module, so a mod that has replaced MoveLearnMenu -- a
-- translation, or a UI overhaul -- is the one that answers here too.
--
-- The under-four case is the same three lines the bag's TM path uses when it
-- teaches into an empty slot (src/ui/BagMenu.lua): insert the slot, then
-- LearnedMove1Text with the jingle riding the box.  Same shape, `{ id, pp }`,
-- which is what every learn site in the engine writes and what the battle
-- engine's PP arithmetic expects to find.
--
-- ------- why the picker is a Menu
--
-- Menu (src/ui/Menu.lua) already has the blinking cursor, the wrap, the
-- scroll window and the B-to-close every vanilla popup has, and it grows its
-- frame to the widest label so a long move name or a translated one does not
-- overflow.  A hand-rolled list would be a second implementation of all of
-- that, one that drifts.  The rows carry the level the move is learned at
-- because the pool is ordered by it, and a column that explains the order it
-- is sorted in is worth the four columns it costs.

return function(mod, Relearn)
  local S = {}

  local Menu = require("src.ui.Menu")
  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local romText = require("src.core.RomText")

  -- Six rows is the most this box can take and still hang clear of the
  -- bottom dialogue box; anything longer scrolls.  A full pool is rarely
  -- this long -- a Gen 1 learnset is a dozen moves and four of them are in
  -- the slots -- but MEW's is, and a mod's species can be anything.
  local VISIBLE = 6

  local function monName(game, mon)
    local def = game.data and game.data.pokemon and game.data.pokemon[mon.species]
    return mon.nickname or (def and def.name) or tostring(mon.species)
  end

  -- Read per open rather than once at load, so flipping the toggle in the
  -- mod manager shows up the next time the popup is opened.
  local function option(key, fallback)
    local ok, value = pcall(function() return mod.options:get(key) end)
    if not ok or value == nil then return fallback end
    return value
  end

  function S.pool(game, mon)
    if not (game and game.data and mon) then return {} end
    return Relearn.pool(game.data, mon,
      { preEvolutions = option("pre_evolutions", true) ~= false })
  end

  -- Is the row worth putting in a popup at all?  Asked before the popup is
  -- built, so a POKéMON with nothing to remember can simply not carry the
  -- row (REMEMBER EMPTY off) instead of carrying one that only ever refuses.
  function S.available(game, mon)
    return #S.pool(game, mon) > 0
  end

  -- ------- the teach

  -- Put the move in a free slot.  Mirrors BagMenu's TM path exactly, jingle
  -- included: the same event should sound the same however it was started.
  local function learnIntoFreeSlot(game, mon, moveId, onDone)
    local mdef = game.data.moves[moveId]
    table.insert(mon.moves, { id = moveId, pp = mdef.pp })
    game.stack:push(TextBox.new(game,
      romText(game.data, "_LearnedMove1Text", "%s learned\n%s!",
              monName(game, mon), mdef.name),
      function() if onDone then onDone(true) end end,
      TextBox.soundOpts(game, "Get_Item1")))
  end

  -- Teach `moveId`, whichever of the two paths that takes.
  --
  -- Guarded on the move still being unknown and still being in the dataset:
  -- the pool was built when the popup opened and this runs a press later, and
  -- in between a hot reload can have taken the move out from under it.  A
  -- duplicate slot is the one outcome worth refusing outright -- the battle
  -- engine indexes moves by slot and two slots naming one move is a state no
  -- vanilla path can produce.
  function S.teach(game, mon, moveId, onDone)
    local mdef = game.data and game.data.moves and game.data.moves[moveId]
    if not mdef then
      mod.log:warn("%s is not a move in this dataset; nothing was taught",
                   tostring(moveId))
      if onDone then onDone(false) end
      return
    end
    for _, slot in ipairs(mon.moves or {}) do
      if slot.id == moveId then
        if onDone then onDone(false) end
        return
      end
    end
    if #mon.moves < Relearn.MAX_MOVES then
      learnIntoFreeSlot(game, mon, moveId, onDone)
    else
      -- MoveLearnMenu runs the whole four-move exchange and calls back with
      -- whether the move was actually learned
      Screens.push(game, "MoveLearnMenu", mon, moveId,
                   function(learned) if onDone then onDone(learned) end end)
    end
  end

  -- ------- the popup

  -- The row label: the move, then the level it comes in at, right of it.
  --
  -- Padded to the widest name in THIS pool rather than to a constant, so a
  -- list of short names does not carry a trench of blanks between the two
  -- columns.  Menu measures the finished labels and sizes its frame to them.
  local function labelsFor(rows)
    local widest = 0
    for _, row in ipairs(rows) do
      local n = #tostring(row.name)
      if n > widest then widest = n end
    end
    local out = {}
    for i, row in ipairs(rows) do
      out[i] = string.format("%-" .. widest .. "s %s",
                             tostring(row.name), Strings("L%d", row.level))
    end
    return out
  end

  -- Open REMEMBER on `mon`.  onClose runs when the flow is over however it
  -- ended -- taught, abandoned, or nothing to teach -- so a caller can put
  -- its own screen back together afterwards.
  function S.open(game, mon, onClose)
    local function done() if onClose then onClose() end end

    if not (game and game.data and type(mon) == "table" and mon.species) then
      done()
      return
    end

    local rows = S.pool(game, mon)
    if #rows == 0 then
      -- Said rather than silently refused: the row can be hidden entirely
      -- (REMEMBER EMPTY off) and a player who chose to keep it deserves a
      -- reason when it does nothing.
      game.stack:push(TextBox.new(game,
        Strings("%s has no\nmoves to remember!", monName(game, mon)),
        done))
      return
    end

    local labels = labelsFor(rows)
    local items = {}
    for i, row in ipairs(rows) do
      items[i] = {
        label = labels[i],
        onSelect = function() S.teach(game, mon, row.move, done) end,
      }
    end

    local th = math.min(#items, VISIBLE) * 2 + 2
    local menu = Menu.new(game, items, {
      -- hung off the bottom edge the way the party menu's own submenu is, so
      -- the POKéMON the popup is about stays visible above it
      tx = 4, ty = math.max(0, 18 - th), tw = 12, th = th,
      maxVisible = VISIBLE,
      -- No title on the frame.  The row that opened this popup already said
      -- REMEMBER and the box comes up over it, so a heading repeats the word
      -- the player just pressed -- and the vanilla screen this is standing in
      -- for, the forget list in MoveLearnMenu, has no heading either: it is a
      -- framed column of move names and nothing else.
      noSound = true,
      onCancel = done,
    })
    game.stack:push(menu)
  end

  return S
end
