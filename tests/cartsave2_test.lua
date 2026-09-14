-- A Gen 2 cart keeps its own save -- checked against the ENGINE, which is
-- what does it now.
--
-- This suite used to test a shim.  `src/core/gen2/Save.lua` named its file out
-- of the VERSION alone, so a cart on Gold, Silver or Crystal read and wrote the
-- base game's playthrough and registered its slot in the base game's registry
-- on the way, and runtime/cartsave2.lua rewrote the paths on their way to disk.
-- The first thing the file did was REPRODUCE that bug against the untouched
-- modules, with a note saying that if a later engine fixed `saveNames` itself,
-- that assertion is the one that would fail and the runtime should come out
-- rather than be adjusted.
--
-- A later engine did (gen1recomp 5920402, first released in v0.2.57), to the
-- SAME filenames the shim produced -- `save_cart_<id>.lua` flat and
-- `saves/cart_<id>/<slot>.lua` with a slot -- so no save moved on anybody's
-- disk when the shim came out.  The bundle's floor is that release, which is
-- what makes the deletion safe rather than merely tidy.
--
-- So the file kept its harness and changed what it is FOR.  Everything below
-- is the engine's own behaviour, asserted against the real modules, because
-- this is a promise about where a player's Crystal cart save lives and a
-- silent regression in it loses playthroughs.  It also asserts the shim is
-- gone: two layers scoping the same path is how a fix becomes the next bug.
--
-- Run:  luajit tests/cartsave2_test.lua

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
  if actual ~= expected then
    description = ("%s (got %s, wanted %s)")
      :format(description, tostring(actual), tostring(expected))
  end
  ok(actual == expected, description)
end

local ENGINE do
  local candidates = { os.getenv("GEN1RECOMP") }
  for _, prefix in ipairs({ "..", "../../..", "../../../..", "../..",
                            "../../../../.." }) do
    candidates[#candidates + 1] = prefix .. "/bryanthaboi/gen1recomp"
    candidates[#candidates + 1] = prefix .. "/gen1recomp"
  end
  for _, dir in ipairs(candidates) do
    if dir then
      local probe = io.open(dir .. "/src/core/gen2/Save.lua")
      if probe then probe:close(); ENGINE = dir; break end
    end
  end
end
if not ENGINE then
  io.write("cartsave2: SKIPPED -- no engine tree found "
    .. "(set GEN1RECOMP to a gen1recomp checkout)\n")
  os.exit(0)
end
package.path = ENGINE .. "/?.lua;" .. package.path

-- ---- the disk

local files = {}
local noop = function() end
_G.love = {
  timer = { getTime = function() return 0 end },
  graphics = setmetatable({}, { __index = function() return noop end }),
  filesystem = {
    getInfo = function(p)
      if files[p] ~= nil then return { type = "file", size = #files[p] } end
      return nil
    end,
    read = function(p) return files[p] end,
    write = function(p, d) files[p] = d; return true end,
    append = function(p, d) files[p] = (files[p] or "") .. d; return true end,
    remove = function(p) files[p] = nil; return true end,
    createDirectory = function() return true end,
    getDirectoryItems = function() return {} end,
    isFile = function(p) return files[p] ~= nil end,
    isDirectory = function() return false end,
  },
}

local CART = "wild_crystal_nightly"

local GameVersion = require("src.core.GameVersion")
GameVersion.set("crystal")
local SaveData = require("src.core.SaveData")
local Save2 = require("src.core.gen2.Save")

local function chunkOf(path)
  local handle = assert(io.open(path))
  local source = handle:read("*a")
  handle:close()
  return assert(load(source, "@" .. path))()
end

-- Write through whatever filesystem the Gen 2 save layer would be handed,
-- at whatever name it would use -- which is the whole round trip in one line.
local function whereAGoldSaveLands()
  local main = Save2.filenames("crystal")
  local fs = SaveData.persistenceFs()
  fs.write(main, "SAVE")
  for path in pairs(files) do
    if files[path] == "SAVE" then return path end
  end
  return nil
end
local function forgetSaves()
  for path in pairs(files) do
    if files[path] == "SAVE" then files[path] = nil end
  end
end

-- ---- 1. no cart: the base game's own file, untouched

eq(Save2.filenames("crystal"), "save_crystal.lua",
   "with no cart the Gen 2 save layer names the base game's file")
eq(SaveData.persistenceFs(), love.filesystem,
   "with no cart the persistence seam is the real filesystem")

-- ---- 2. the engine scopes a cart itself

SaveData.setCart(CART, "hash")
ok(Save2.filenames("crystal") ~= "save_crystal.lua",
   "with the cart active the Gen 2 save layer does NOT name the base game's "
   .. "file -- which is the whole bug, and the engine's to answer now")

-- ---- 3. and this bundle does not scope it a second time
--
-- Not a style check.  The shim rewrote a path on its way to disk; the engine
-- now hands it over already rewritten, and a second pass over an
-- already-scoped path is how a fix turns into the next bug.  So the file is
-- gone and nothing loads it.

do
  local shim = io.open("runtime/cartsave2.lua")
  if shim then shim:close() end
  ok(shim == nil,
     "runtime/cartsave2.lua is gone: the engine does this, and two layers "
     .. "scoping one path is worse than neither")

  local handle = assert(io.open("runtime/bundle.lua"))
  local text = handle:read("*a")
  handle:close()
  ok(text:find('loadRuntime("cartsave2")', 1, true) == nil,
     "and the bundle does not reach for it")
end

-- ---- 4. the flat branch: a cart with no slot of its own

forgetSaves()
eq(whereAGoldSaveLands(), "save_cart_" .. CART .. ".lua",
   "with no cart slot a Gold save lands on the cart's flat name")

-- ---- 5. the slot branch: the file lands where the launcher looks

local made = SaveData.createCartSlot(CART)
SaveData.setActiveCartSlot(CART, made)
forgetSaves()

local main, bak, tmp = Save2.filenames("crystal")
eq(main, "saves/cart_" .. CART .. "/" .. made .. ".lua",
   "the Gen 2 save layer names the CART's own slot file")
eq(whereAGoldSaveLands(), main, "and the bytes land in it")
-- .bak and .tmp travel with it, so a crash mid-write recovers from the cart's
-- own copies rather than the base game's.
eq(bak, main .. ".bak", "the backup is beside it")
eq(tmp, main .. ".tmp", "and the write witness")
eq(main:match("^(.*)/[^/]+$"), "saves/cart_" .. CART,
   "in the cart's own directory, which is where the launcher looks")

-- ---- 6. and the base game's registry is left alone
--
-- The other half of the bug, and the quieter one: a cart's first save used to
-- register a slot in the BASE GAME's list, so a Crystal the player had never
-- started grew a playthrough in the launcher.

local opts = SaveData.loadOptions()
eq(tostring(opts.saveSlots and opts.saveSlots.crystal), "nil",
   "no phantom slot against the base game")
local reg = opts.cartSlots and opts.cartSlots[CART]
eq(reg and reg.list and reg.list[1], made,
   "the slot is in the cart's own registry")
eq(SaveData.activeCartSlot(CART), made, "and it is the cart's active slot")

-- ---- 7. handing back to the launcher takes it all down

SaveData.setCart(nil)
eq(SaveData.persistenceFs(), love.filesystem,
   "with the cart cleared the persistence seam is the real filesystem again")
forgetSaves()
eq(whereAGoldSaveLands(), "save_crystal.lua",
   "and the base game writes its own save once more")

io.write(("cartsave2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
