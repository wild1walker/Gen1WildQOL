-- Gen1Remember: what a POKéMON is allowed to remember, and nothing about
-- how it is drawn.
--
-- No require, no love, no engine module: this file is a pure function of the
-- merged dataset and one mon table, which is what lets the suite drive it
-- against hand-built species and assert on the answer instead of on a
-- screenshot.  main.lua publishes both builders on mod.exports for exactly
-- that reason, and so a mod that wants the same answer without opening the
-- screen can read it.
--
-- ------- what counts as forgotten
--
-- Gen 1 keeps no move history.  A save records the four moves a POKéMON has
-- and not one byte about what it used to know, so "the moves it has
-- forgotten" cannot be read back -- it has to be DERIVED, and the derivation
-- is the whole design of this file.
--
-- A move is rememberable when the POKéMON should already have had it: it is
-- in the level-up learnset at or below the level the mon has reached, and it
-- is not in the four slots now.  That is exactly the set Pokemon.movesAtLevel
-- (src/pokemon/Pokemon.lua) threw away on the way up -- it keeps the most
-- recent four and drops the rest -- so what this offers back is what the
-- level-up path actually took, which is what a player means by forgotten.
--
-- It needs no save state, which is the reason to prefer it over recording
-- what got overwritten: a POKéMON caught before this mod was installed
-- answers the same as one caught after, and a save that has never seen this
-- mod loses nothing by adding it and nothing by removing it again.
--
-- ------- and the pre-evolutions
--
-- A CHARIZARD's learnset is CHARIZARD's.  The moves it learned as a
-- CHARMANDER are in CHARMANDER's, and a player who evolved past EMBER did
-- not stop having forgotten it -- so the chain is walked backwards and every
-- form's learnset counted, gated on the same level test.  This is what makes
-- the answer match the POKéMON rather than the species record.
--
-- The chain is walked through a reverse index built per call from
-- data.pokemon, not from a table of pre-evolutions, because no such table
-- exists: `evolutions` points forward only (Schemas.lua `evolutions[]` is
-- { method, level, item, species }).  Building it per call rather than once
-- at load is what lets a content mod that registers a species AFTER this one
-- still be seen -- the same reason Gen1Dex rebuilds its rows per open.
--
-- TM and HM moves are deliberately NOT in the pool.  A machine move is not
-- forgotten, it is bought: the player still has the TM, or knowingly spent
-- it, and handing those back free would quietly rewrite what a TM costs.
-- Level-up moves are the ones the game took away without asking.

local Relearn = {}

Relearn.MAX_MOVES = 4

-- species -> { species that evolve INTO it }, built from the forward table.
-- One pass over the dataset; a species naming an evolution target that is not
-- in the dataset is skipped rather than trusted, because a half-merged
-- content mod is a thing that happens and a nil def is not worth throwing
-- over.
local function preIndex(data)
  local into = {}
  for id, def in pairs(data.pokemon or {}) do
    for _, evo in ipairs((type(def) == "table" and def.evolutions) or {}) do
      local target = evo.species
      if target and (data.pokemon or {})[target] then
        into[target] = into[target] or {}
        into[target][#into[target] + 1] = id
      end
    end
  end
  return into
end

-- The mon's form and everything it evolved from, nearest form first.
--
-- Breadth-first over the reverse index with a visited set, because the index
-- is data and data can name a cycle (a content mod that evolves A into B and
-- B into A is a mistake, but it is a mistake that must not hang the party
-- menu).  Every species is visited once, so the walk terminates on any graph.
function Relearn.chain(data, species)
  if not (data and species and (data.pokemon or {})[species]) then return {} end
  local into = preIndex(data)
  local order, seen, queue = {}, { [species] = true }, { species }
  local head = 1
  while head <= #queue do
    local current = queue[head]
    head = head + 1
    order[#order + 1] = current
    for _, parent in ipairs(into[current] or {}) do
      if not seen[parent] then
        seen[parent] = true
        queue[#queue + 1] = parent
      end
    end
  end
  return order
end

-- Every level-up move a species grants at or below `level`, as
-- { move = id, level = n }, lowest level first and each move once.
--
-- level1Moves come first at level 1: they are the moves a species is born
-- with and the learnset does not always restate them.  A learnset naming the
-- same move at two levels keeps the LOWER, which is the one that is true --
-- the same call Gen1Dex's movelist makes about the same duplicate.
local function grants(def, level)
  local out, at = {}, {}
  local function add(move, moveLevel)
    if not move then return end
    if at[move] == nil or moveLevel < at[move] then
      if at[move] == nil then out[#out + 1] = move end
      at[move] = moveLevel
    end
  end
  for _, move in ipairs(def.level1Moves or {}) do add(move, 1) end
  for _, entry in ipairs(def.learnset or {}) do
    if entry.level and entry.level <= level then add(entry.move, entry.level) end
  end
  local rows = {}
  for _, move in ipairs(out) do
    rows[#rows + 1] = { move = move, level = at[move] }
  end
  return rows
end

-- The pool: what this POKéMON may be taught to remember, in the order the
-- screen draws it.
--
-- opts.preEvolutions (default true) walks the chain; false reads the current
-- form's learnset alone, which is the later-generation move reminder's own
-- rule and is offered for anyone who wants that instead.
--
-- Each row is { move, name, level, species, inherited } -- `species` is the
-- form that grants it and `inherited` is true when that is not the mon's own
-- form, so the screen can say where a move came from without re-deriving it.
--
-- Sorted by level then by name: a stable order that reads like the dex's
-- movelist, and one that does not move under the cursor when the same pool
-- is rebuilt on the next open.
function Relearn.pool(data, mon, opts)
  opts = opts or {}
  if not (data and type(mon) == "table" and mon.species) then return {} end
  local def = (data.pokemon or {})[mon.species]
  if not def then return {} end

  local known = {}
  for _, slot in ipairs(mon.moves or {}) do
    if slot and slot.id then known[slot.id] = true end
  end

  local level = tonumber(mon.level) or 1
  local forms = opts.preEvolutions == false and { mon.species }
    or Relearn.chain(data, mon.species)

  local rows, at = {}, {}
  for _, species in ipairs(forms) do
    local sdef = (data.pokemon or {})[species]
    if sdef then
      for _, grant in ipairs(grants(sdef, level)) do
        -- known moves are out, and a move two forms both grant is listed
        -- once, against the NEAREST form that grants it (the chain is
        -- ordered nearest-first, so the first sighting wins)
        if not known[grant.move] and not at[grant.move] then
          local mdef = (data.moves or {})[grant.move]
          -- a learnset naming a move the dataset does not carry is a broken
          -- record, not a move to offer: it would draw as a blank row and
          -- teach a slot the battle engine cannot resolve
          if mdef then
            at[grant.move] = true
            rows[#rows + 1] = {
              move = grant.move,
              name = mdef.name or grant.move,
              level = grant.level,
              species = species,
              inherited = species ~= mon.species,
            }
          end
        end
      end
    end
  end

  table.sort(rows, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return tostring(a.name) < tostring(b.name)
  end)
  return rows
end

-- Whether the row is worth showing at all, asked before the popup is built.
-- Cheap enough to ask per open (one dataset pass and one learnset walk), and
-- asking it per open is what keeps the row honest as the mon levels up.
function Relearn.any(data, mon, opts)
  return #Relearn.pool(data, mon, opts) > 0
end

return Relearn
