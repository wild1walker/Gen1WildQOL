-- Coverage of this bundle's own additions to the vendored Quality of Life mod.
--
-- Separate from runtime_test.lua because it is specific to Gen1WildQOL: the
-- Quality of Life features are only in this half, so these tests have nothing
-- to run against in Gen1WildUI.
--
-- The subject is modules/QualityOfLife/bundle_common.lua -- the built copy,
-- because that is the one the game loads. tools/build.py --check is what
-- guarantees it matches overlays/.
--
-- Run:  luajit tests/qol_features_test.lua

package.path = "./?.lua;" .. package.path

local passed, failed = 0, 0
local function ok(condition, description)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("  FAIL  ", description, "\n")
  end
end
local function eq(actual, expected, description)
  local same = actual == expected
  if not same then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(same, description)
end

local function load_(path, ...)
  local handle = assert(io.open(path, "r"), path .. " is missing")
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))(...)
end

-- --------------------------------------------- the gate is the feature's alone
--
-- Both battle features used to draw through one overlay host, so a gate
-- applied for one of them must not reach the other.  The XP bar was the one
-- that needed a gate and it is Gen1BattleUI's now, which leaves this bundle
-- with the mechanism and no user of it -- and a mechanism with no user is
-- exactly the one that quietly stops working.  So it is still driven here,
-- against a stand-in predicate rather than against the predicate that left.

do
  io.write("a gated overlay does not gate the ones beside it\n")

  local Common = load_("modules/QualityOfLife/bundle_common.lua")

  local added = {}
  local host = {
    add = function(_, overlay) added[#added + 1] = overlay end,
    install = function() end,
  }

  local gatedDrawn, ungatedDrawn = 0, 0
  local allowed = true

  -- Reproduce the gating Common.install applies.  `gated` is a local, so the
  -- shape is asserted rather than the function -- which is the same thing the
  -- previous version of this test did through the public predicate.
  local proxy = {
    add = function(_, overlay)
      local base = overlay.draw
      overlay.draw = function(battle, ...)
        if not allowed then return end
        return base(battle, ...)
      end
      return host:add(overlay)
    end,
  }
  proxy:add({ id = "gated", draw = function() gatedDrawn = gatedDrawn + 1 end })
  host:add({ id = "ungated",
             draw = function() ungatedDrawn = ungatedDrawn + 1 end })

  eq(#added, 2, "both overlays reached the shared host")

  allowed = false
  for _, overlay in ipairs(added) do overlay.draw({}, {}, {}) end
  eq(gatedDrawn, 0, "a closed gate stops its own overlay")
  eq(ungatedDrawn, 1, "and leaves the overlay beside it drawing")

  allowed = true
  for _, overlay in ipairs(added) do overlay.draw({}, {}, {}) end
  eq(gatedDrawn, 1, "an open gate lets it through again")
  eq(ungatedDrawn, 2, "the other being unaffected throughout")
end

-- The XP bar's own guard -- "stop once the player's Pokemon faints, because
-- the engine has cleared the HUD out from under the bar" -- moved with the
-- feature.  It is asserted in Gen1BattleUI's suite now, not here.

-- ------------------------------- the SELECT menu is a list other mods can join
--
-- It is built fresh on every press out of what is usable RIGHT NOW -- FLY only
-- outdoors, FLASH only in the dark, a repel only while one is in the bag -- so
-- it is not a menu with a fixed shape.  That is what the row ids are for: a
-- label is what a row says and moves with the language and with which repel is
-- in the bag, an id is what the row IS.
--
-- And the list is handed round before it is drawn.  A registry rather than a
-- hook, because mod.hooks gives a mod `wrap` and no way to emit one of its
-- own; Gen1Dex's area.provide is the same answer to the same problem.

do
  io.write("the SELECT menu carries ids, a MAP row, and other mods' rows\n")

  -- Engine stand-ins, kept to what this one menu touches.
  local pushed = {}
  local realLoaded = {}
  local function stub(name, value)
    realLoaded[name] = package.loaded[name]
    package.loaded[name] = value
  end
  stub("src.world.FieldDefaults", { field = function() return {} end })
  stub("src.world.Map", {
    isOutside = function(def) return def and def.outside == true end,
  })
  stub("src.core.Strings", setmetatable({}, {
    __call = function(_, text) return text end,
  }))
  stub("src.inventory.Bag", { remove = function() end,
                              count = function() return 0 end })
  stub("src.render.TextBox", { new = function() return {} end })
  stub("src.core.ItemEffects", { use = function() return "consumed" end })
  stub("src.world.OverworldController", { handleInput = function() end })
  stub("src.world.World", {})
  stub("src.render.Transition", { whiteFlash = function() return {} end })

  local options = { qol_easy_interactions = true }
  local logged = {}
  local mod = {
    id = "qol",
    exports = {},
    log = { warn = function(_, f, e) logged[#logged + 1] = tostring(f) end,
            info = function() end },
    ui = {
      Menu = { new = function(_, items, opts)
        local menu = { items = items, opts = opts }
        pushed[#pushed + 1] = menu
        return menu
      end },
      push = function(_, id, o) pushed[#pushed + 1] = { screen = id, opts = o } end,
    },
    hooks = { wrap = function() end },
    events = { on = function() end, once = function() end },
    world = {},
  }
  local services = {
    options = { value = function(_, key) return options[key] end },
  }

  local ow = {
    map = { id = "ROUTE_1", def = { id = "ROUTE_1", outside = true,
                                    tileset = "OVERWORLD" } },
    dark = false,
    partyKnows = function(_, move) return move == "FLY" end,
    flyTo = function() end,
    beginTeleportOut = function() end,
  }
  local game = { data = {}, save = { inventory = {} }, input = {},
                 stack = { push = function(_, s) pushed[#pushed + 1] = s end,
                           top = function() return ow end } }
  mod.world.game = game

  local feature = load_("modules/QualityOfLife/qol_feature_easy_interactions.lua",
                        { value = 1 })
  ok(type(feature) == "table" and type(feature.install) == "function",
    "the feature loads")
  feature.install(mod, services)

  ok(type(mod.exports.fieldMenu) == "table"
     and type(mod.exports.fieldMenu.provide) == "function",
    "and publishes the SELECT menu registry")

  -- Drive the menu the way SELECT does: through the handler the feature
  -- installed on OverworldController.
  local OverworldController = require("src.world.OverworldController")
  local handlers = rawget(OverworldController, "__qolSelectHandlers") or {}
  local handler = handlers[mod.id]
  ok(type(handler) == "function", "and installs the SELECT handler")

  local function openMenu()
    pushed = {}
    game.input = { wasPressed = function(_, k) return k == "select" end }
    if handler then handler(ow) end
    for _, p in ipairs(pushed) do
      if type(p) == "table" and type(p.items) == "table" then return p.items end
    end
    return nil
  end

  local function idsOf(items)
    local out = {}
    for _, item in ipairs(items or {}) do out[#out + 1] = tostring(item.id) end
    return table.concat(out, ",")
  end

  local items = openMenu()
  ok(items ~= nil, "SELECT opens the menu")
  -- MAP has no switch of its own: it is offered outdoors like any other row,
  -- and the layout editor is what takes it away.  It had one, and that was one
  -- switch too many the moment this menu became arrangeable -- the editor
  -- listed MAP, said ON, and toggling it did nothing.
  eq(idsOf(items), "fly,map,cancel",
    "with a row for every field move usable here, each carrying its id")

  -- indoors there is no map to open, the same reason FLY is outdoors-only
  ow.map.def.outside = false
  local inside = openMenu()
  ok(inside == nil or not idsOf(inside):find("map", 1, true),
    "MAP is not offered indoors")
  ow.map.def.outside = true

  -- another mod's row, and where it lands
  local remove = mod.exports.fieldMenu.provide(function(_, _, rows)
    rows[#rows + 1] = { id = "mine", label = "MINE", onSelect = function() end }
    return rows
  end, "someone")
  eq(idsOf(openMenu()), "fly,map,mine,cancel",
    "a provider's row lands above CANCEL, which stays the floor")
  remove()
  eq(idsOf(openMenu()), "fly,map,cancel", "and removing the provider takes it away")

  -- a provider that raises is skipped, and the menu still opens
  mod.exports.fieldMenu.provide(function() error("boom", 0) end, "bad")
  logged = {}
  eq(idsOf(openMenu()), "fly,map,cancel",
    "a provider that raises does not take the menu down with it")
  ok(#logged > 0, "and it is said once")
  local before = #logged
  openMenu()
  eq(#logged, before, "once, not on every press")

  -- ---- the catalog: what this menu CAN show, not what it is showing
  --
  -- The live list is the answer to "what is usable on this tile".  Anything
  -- that wants to ARRANGE the menu needs the other question answered too, and
  -- it has no other source: a row that only appears outdoors, with FLY in the
  -- party, is invisible to an editor until the player is standing there.
  local catalog = mod.exports.fieldMenu.catalog
  ok(type(catalog) == "function", "the registry publishes a catalog")

  local ids = {}
  for _, entry in ipairs(catalog() or {}) do ids[#ids + 1] = tostring(entry.id) end
  eq(table.concat(ids, ","), "fly,teleport,flash,dig,map,repel,cancel",
    "listing every row this menu can ever show, whatever is usable right now")

  -- the repel row reads SUPER REPEL or MAX REPEL depending on the bag, which
  -- is exactly why the catalog names it plainly and both are keyed by id
  local labels = {}
  for _, entry in ipairs(catalog() or {}) do
    labels[#labels + 1] = tostring(entry.label)
  end
  ok(labels[6] == "REPEL", "and names the repel row plainly, not by the bag")

  -- a provider declares its own rows alongside its handler
  local dropMine = mod.exports.fieldMenu.provide(function(_, _, rows)
    return rows
  end, "someone", { { id = "mine", label = "MINE" } })
  local withMine = {}
  for _, entry in ipairs(catalog() or {}) do
    withMine[#withMine + 1] = tostring(entry.id)
  end
  eq(withMine[#withMine], "mine", "a provider's declared rows join the catalog")
  dropMine()
  local without = {}
  for _, entry in ipairs(catalog() or {}) do
    without[#without + 1] = tostring(entry.id)
  end
  eq(#without, #ids, "and leave it when the provider does")

  for name, value in pairs(realLoaded) do package.loaded[name] = value end
  if handlers then handlers[mod.id] = nil end
end

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
