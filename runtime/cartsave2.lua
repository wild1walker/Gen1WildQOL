-- A cart on Gold, Silver or Crystal gets its OWN save.
--
-- ------- the bug, and why only the Gen 2 cart has it
--
-- The engine scopes a cart's saves by cart id.  `bootGame` calls
-- `SaveData.setCart(cartId, cartHash)` (main.lua:495) and every path in
-- src/core/SaveData.lua resolves through `activeScopeKey`, which answers
-- `cart_<id>` while a cart is active:
--
--   flat   save_cart_wild_crystal_nightly.lua
--   slots  saves/cart_wild_crystal_nightly/slot1.lua
--
-- The launcher agrees with it everywhere: RomImporter lists, creates,
-- selects, renames and deletes a cart's slots through the `cartSlots`
-- registry (`_refreshSlots`, `_selectSlot`, `_newSlot` all branch on
-- `cartOfScope`).  Gen 1 saves and loads through SaveData too, so a
-- Red-based cart such as Wild Green already keeps its own playthrough.
--
-- **Gold does not go through that module.**  `Game2` saves and loads through
-- src/core/gen2/Save.lua, which is deliberately separate -- "the save-file
-- naming convention" is one of the things its own header says it owns -- and
-- its `saveNames` builds the path out of the VERSION alone:
--
--   local slot = SaveData.activeSlot(version)
--   if slot then return "saves/" .. version .. "/" .. slot .. ".lua" end
--   return "save" .. GameVersion.saveSuffix(version) .. ".lua"
--
-- Neither branch asks whether a cart is active.  So a Gen 2 cart reads and
-- writes the BASE GAME's playthrough.  Measured rather than reasoned: with
-- the cart set, `SaveData` writes `save_cart_wild_crystal_nightly.lua` and
-- `src.core.gen2.Save` writes `save_crystal.lua`.
--
-- It is worse than sharing.  `Save.save` opens with
--
--   if not SaveData.activeSlot(version) then
--     local id = SaveData.createSlot(version)
--     SaveData.setActiveSlot(version, id)
--   end
--
-- so the first save inside the cart REGISTERS A SLOT IN THE BASE GAME'S
-- registry and makes it active -- the cart's playthrough appears in the
-- launcher's Crystal list, and the player's own Crystal save is what the
-- cart then overwrites.
--
-- ------- the rule this installs
--
-- One sentence: **while a Gen 2 cart is active, the base version's slot
-- resolution and save paths, as seen through SaveData's public API, are the
-- cart's.**  That is the answer SaveData already gives its own callers
-- through `activeScopeKey`; this is only saying it again at the three public
-- entry points and the one filesystem seam that the Gen 2 module reaches it
-- by, because that module asks in the base version's name.
--
--   SaveData.activeSlot(version)          -> SaveData.activeCartSlot(cart)
--   SaveData.createSlot(version)          -> SaveData.createCartSlot(cart)
--   SaveData.setActiveSlot(version, id)   -> SaveData.setActiveCartSlot(...)
--   SaveData.persistenceFs()              -> a filesystem that rewrites
--                                            saves/<version>/  ->  saves/cart_<id>/
--                                            save_<suffix>.lua ->  save_cart_<id>.lua
--
-- The three slot wraps are what stop the phantom base-game slot and put the
-- CART's slot id into the path.  The filesystem wrap is what moves that path
-- into the cart's directory, because `saveNames` builds the directory out of
-- the version even once the slot id is right.  Neither is sufficient alone.
--
-- ------- why the filesystem seam is safe to wrap
--
-- SaveData's own internals never call it: they use a file-local `persistFs`,
-- so options.lua, the slot registries and every launcher listing are outside
-- this.  Its callers are src/online/Trade.lua, src/mods/Storage.lua,
-- src/mods/LegacyCompat.lua, src/import/ImportAccess.lua and
-- src/core/gen2/Save.lua -- and of those only the last names a base-game save
-- path, so only the last is rewritten.  Everything else passes through
-- untouched because it does not match.
--
-- It is a no-op for everything else too:
--
--   * no cart active            the real filesystem, untouched
--   * not a Gen 2 boot          never installed
--   * a path SaveData already   `save_cart_<id>.lua` does not match the base
--     scoped                    game's name, so it passes straight through
--   * options.lua, caches,      not save paths; passed through
--     screenshots
--
-- and the cart is read live from `SaveData.getCart()`, so the moment the game
-- hands back to the launcher -- which calls `SaveData.setCart(nil)`
-- (main.lua:433) -- all four stand down on their own rather than having to be
-- taken down.

local CartSave2 = {}

local PATCH_KEY = "__gen1wildCartSave2"

-- ------- the path rewrite

-- The two shapes SaveData uses for a cart (`slotDir` is "saves/" .. key and
-- `legacyNames` is "save_" .. key .. ".lua" for a cart key), which are what
-- the Gen 2 module has to be pointed at.
local function targets(version, cartId)
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if not okV or type(GameVersion) ~= "table" then return nil end
  if type(GameVersion.saveSuffix) ~= "function" then return nil end
  local okS, suffix = pcall(GameVersion.saveSuffix, version)
  if not okS or type(suffix) ~= "string" then return nil end
  return {
    flatFrom = "save" .. suffix .. ".lua",
    flatTo = "save_cart_" .. cartId .. ".lua",
    dirFrom = "saves/" .. version .. "/",
    dirTo = "saves/cart_" .. cartId .. "/",
  }
end
CartSave2.targets = targets

-- One path, rewritten when it is the base game's and left alone otherwise.
-- Exposed for the headless suite, and pure.
function CartSave2.rewrite(path, map)
  if type(path) ~= "string" or type(map) ~= "table" then return path end
  -- the flat save and its .bak / .tmp companions
  if path == map.flatFrom then return map.flatTo end
  local rest = path:match("^" .. map.flatFrom:gsub("([^%w])", "%%%1") .. "(%..+)$")
  if rest then return map.flatTo .. rest end
  -- and the slot directory, whatever is under it
  if path:sub(1, #map.dirFrom) == map.dirFrom then
    return map.dirTo .. path:sub(#map.dirFrom + 1)
  end
  -- `saves/<version>` with no trailing slash: the directory itself, which is
  -- what Save.save hands createDirectory before staging a slot write
  local bare = map.dirFrom:sub(1, -2)
  if path == bare then return map.dirTo:sub(1, -2) end
  return path
end

-- The methods that take a path first.  Everything else on the filesystem is
-- reached through __index and is untouched.
local PATH_FIRST = {
  "read", "write", "append", "remove", "getInfo", "createDirectory",
  "getDirectoryItems", "lines", "newFile", "getSize", "isFile", "isDirectory",
}

function CartSave2.proxy(fs, map)
  local proxy = setmetatable({}, { __index = fs })
  for _, name in ipairs(PATH_FIRST) do
    local base = fs[name]
    if type(base) == "function" then
      proxy[name] = function(path, ...)
        return base(CartSave2.rewrite(path, map), ...)
      end
    end
  end
  return proxy
end

-- ------- installation

-- The cart this boot is inside, or nil.  Asked every time rather than
-- remembered: `setCart(nil)` on the way back to the launcher has to be able
-- to switch all of this off without anything being un-installed.
local function liveCart(SaveData)
  local ok, cartId = pcall(SaveData.getCart)
  if ok and type(cartId) == "string" and cartId ~= "" then return cartId end
  return nil
end

-- Redirect the three public slot calls to their cart-scoped twins.
--
-- Narrowed to the version this boot is running: ModProfile.capture walks
-- every version asking `activeSlot` for each, and a cart's slot id is an
-- answer about this playthrough, not about the four games the player is not
-- in.  `saveNames` and `Save.save` both ask in the running version's name (or
-- with no name at all), so the narrowing costs them nothing.
local function installSlots(SaveData, GameVersion)
  local pairsOf = {
    { base = "activeSlot", cart = "activeCartSlot", takesId = false },
    { base = "createSlot", cart = "createCartSlot", takesId = false },
    { base = "setActiveSlot", cart = "setActiveCartSlot", takesId = true },
  }
  for _, row in ipairs(pairsOf) do
    if type(SaveData[row.base]) ~= "function"
        or type(SaveData[row.cart]) ~= "function" then
      return false, "SaveData has no " .. row.cart
    end
  end
  for _, row in ipairs(pairsOf) do
    local base, cartFn = SaveData[row.base], SaveData[row.cart]
    local takesId = row.takesId
    SaveData[row.base] = function(version, slotId, ...)
      local cartId = liveCart(SaveData)
      local running = GameVersion.get and GameVersion.get() or nil
      if cartId and (version == nil or version == running) then
        if takesId then return cartFn(cartId, slotId) end
        return cartFn(cartId)
      end
      return base(version, slotId, ...)
    end
  end
  return true
end

local function installFs(SaveData, GameVersion)
  local base = SaveData.persistenceFs
  local cached, cachedFor
  SaveData.persistenceFs = function(injected)
    local fs = base(injected)
    local cartId = liveCart(SaveData)
    if not cartId or type(fs) ~= "table" then return fs end
    local version = GameVersion.get and GameVersion.get() or nil
    if type(version) ~= "string" then return fs end
    -- Rebuilt only when the cart, the version or the underlying filesystem
    -- changes, not per call: the save layer asks for this on every read.
    local key = cartId .. "|" .. version .. "|" .. tostring(fs)
    if cachedFor ~= key then
      local map = targets(version, cartId)
      cached = map and CartSave2.proxy(fs, map) or fs
      cachedFor = key
    end
    return cached
  end
end

function CartSave2.install()
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if not (okV and type(GameVersion) == "table"
          and type(GameVersion.generation) == "function") then
    return false, "no GameVersion; a Gen 2 cart would keep the base game's save"
  end
  local okGen, generation = pcall(GameVersion.generation)
  -- Gen 1 already resolves through SaveData, cart scope and all.  Nothing to do.
  if not (okGen and generation == 2) then return true end

  local okS, SaveData = pcall(require, "src.core.SaveData")
  if not (okS and type(SaveData) == "table"
          and type(SaveData.persistenceFs) == "function"
          and type(SaveData.getCart) == "function") then
    return false, "no SaveData seam; a Gen 2 cart would keep the base game's save"
  end
  if rawget(SaveData, PATCH_KEY) then return true end

  local ok, why = installSlots(SaveData, GameVersion)
  if not ok then return false, why end
  installFs(SaveData, GameVersion)
  SaveData[PATCH_KEY] = true
  return true
end

return CartSave2
