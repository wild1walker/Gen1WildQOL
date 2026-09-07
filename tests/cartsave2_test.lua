-- A Gen 2 cart keeps its own save, checked against the CART's own SaveData.
--
-- This one is engine-backed rather than stubbed, and deliberately so.  The
-- whole fix is a claim about two modules that disagree with each other:
--
--   * src/core/SaveData.lua scopes a cart's saves by cart id, and the
--     launcher lists them from that scope;
--   * src/core/gen2/Save.lua names its file out of the VERSION alone, and so
--     reads and writes the base game's playthrough instead.
--
-- A stub of either would be written by the same hand that has to be right
-- about the disagreement, so it would agree with whichever half that hand
-- misread.  The two shapes this rests on -- `saveNames` reading
-- `SaveData.activeSlot`, and `Save.save` conjuring a slot when it answers nil
-- -- are the engine's, and this file reads them from the engine.
--
-- So the first thing it does is REPRODUCE the bug against the untouched
-- modules.  If a later engine fixes `saveNames` itself, that assertion is the
-- one that fails, and this runtime should come out rather than be adjusted.
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

-- ---- 1. the untouched engine, with no cart: already correct

eq(Save2.filenames("crystal"), "save_crystal.lua",
   "with no cart the Gen 2 save layer names the base game's file")
eq(SaveData.persistenceFs(), love.filesystem,
   "with no cart the persistence seam is the real filesystem")

-- ---- 2. the bug, reproduced

SaveData.setCart(CART, "hash")
eq(Save2.filenames("crystal"), "save_crystal.lua",
   "BUG: with the cart active the Gen 2 save layer still names save_crystal.lua")
do
  -- and a slot registered in the cart's own scope does not move it either:
  -- `saveNames` resolves the slot through the VERSION, so it never sees one.
  local id = SaveData.createCartSlot(CART)
  SaveData.setActiveCartSlot(CART, id)
  eq(Save2.filenames("crystal"), "save_crystal.lua",
     "BUG: a registered CART slot does not move it either")
  -- put the cart's registry back to empty so the flat branch is testable below
  SaveData.deleteCartSlot(CART, id)
end
eq(tostring(SaveData.activeCartSlot(CART)), "nil",
   "the cart's registry is empty again before the fix goes in")

-- ---- 3. the fix

local CartSave2 = chunkOf("runtime/cartsave2.lua")
local installed, why = CartSave2.install()
ok(installed, "install reports success (" .. tostring(why) .. ")")

-- ---- 4. the flat branch: a cart with no slot of its own

forgetSaves()
eq(whereAGoldSaveLands(), "save_cart_" .. CART .. ".lua",
   "with no cart slot a Gold save lands on the cart's flat name")

-- ---- 5. Save.save's own slot bookkeeping goes to the cart's registry
--
-- src/core/gen2/Save.lua:914 asks `SaveData.activeSlot(version)` and, when it
-- answers nil, calls `createSlot` + `setActiveSlot` in the VERSION's name.
-- Unwrapped that registers the cart's playthrough in the launcher's Crystal
-- list.  This is that exact sequence.

eq(tostring(SaveData.activeSlot("crystal")), "nil",
   "before the first save the cart has no slot")
local made = SaveData.createSlot("crystal")
SaveData.setActiveSlot("crystal", made)
local opts = SaveData.loadOptions()
eq(tostring(opts.saveSlots and opts.saveSlots.crystal), "nil",
   "no phantom slot is registered against the base game")
local reg = opts.cartSlots and opts.cartSlots[CART]
eq(reg and reg.list and reg.list[1], made,
   "the slot went into the cart's own registry")
eq(SaveData.activeCartSlot(CART), made, "and it is the cart's active slot")

-- ---- 6. the slot branch: the file lands where the launcher looks

forgetSaves()
eq(Save2.filenames("crystal"), "saves/crystal/" .. made .. ".lua",
   "the Gen 2 save layer now names the CART's slot id")
eq(whereAGoldSaveLands(), "saves/cart_" .. CART .. "/" .. made .. ".lua",
   "and the bytes land in the cart's slot directory")
-- .bak and .tmp travel with it, so a crash mid-write recovers from the
-- cart's own copies rather than the base game's.
local main, bak, tmp = Save2.filenames("crystal")
eq(CartSave2.rewrite(bak, CartSave2.targets("crystal", CART)),
   "saves/cart_" .. CART .. "/" .. made .. ".lua.bak", "the backup moves too")
eq(CartSave2.rewrite(tmp, CartSave2.targets("crystal", CART)),
   "saves/cart_" .. CART .. "/" .. made .. ".lua.tmp", "and the write witness")
-- Save.save creates the parent before staging; the directory has to move as
-- well or the write goes to a folder the launcher never reads.
eq(CartSave2.rewrite(main:match("^(.*)/[^/]+$"),
                     CartSave2.targets("crystal", CART)),
   "saves/cart_" .. CART, "the parent directory moves with it")

-- ---- 7. everything that is not a base-game save path is untouched

local map = CartSave2.targets("crystal", CART)
for _, path in ipairs({
  "options.lua",
  "options.lua.bak",
  "save_cart_" .. CART .. ".lua",
  "saves/cart_" .. CART .. "/slot1.lua",
  "saves/gold/slot1.lua",
  "save_gold.lua",
  "mods/storage/whatever.lua",
}) do
  eq(CartSave2.rewrite(path, map), path, path .. " passes through")
end

-- ---- 8. the narrowing: a question about another game gets the other game's answer
--
-- ModProfile.capture walks every version asking `activeSlot` for each.  A
-- cart's slot id is an answer about THIS playthrough, so only the running
-- version's question is redirected.

SaveData.setActiveSlot("gold", "slot1")
eq(tostring(SaveData.activeSlot("gold")), "slot1",
   "a question about Gold is still answered by Gold")
eq(SaveData.activeSlot("crystal"), made,
   "and a question about the running version by the cart")

-- ---- 9. handing back to the launcher takes it all down

SaveData.setCart(nil)
eq(SaveData.persistenceFs(), love.filesystem,
   "with the cart cleared the persistence seam is the real filesystem again")
eq(tostring(SaveData.activeSlot("crystal")), "nil",
   "and the base game's slot resolution is its own again")
forgetSaves()
eq(whereAGoldSaveLands(), "save_crystal.lua",
   "so the base game writes its own save once more")

io.write(("cartsave2: %d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
