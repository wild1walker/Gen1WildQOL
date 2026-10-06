-- REUSABLE TMS on FireRed, LeafGreen and Emerald.
--
-- A GBA TM is spent the moment its move is learned, and an HM never is
-- (`ItemUse.useTm`, after pokefirered src/party_menu.c ItemUseCB_TMHM).  This
-- makes a TM behave like the HM beside it in the case.
--
-- The cart spends it in one of two places, and that is the whole difficulty:
-- straight away when the Pokemon had a free move slot, or LATER -- from the
-- forget-a-move prompt's `onDone`, after the player has picked which move
-- goes -- when it did not.  So the TM is not protected from the spend; it is
-- GIVEN BACK after it, on both paths: once when `useTm` returns, and once
-- when the prompt it opened closes.  A teach the player cancels spends
-- nothing and so gets nothing back.  The cart's own logic, text and
-- friendship gain run exactly as they always did.
--
-- Live: the row is read on every teach, so OFF spends the TM again from the
-- next one onward.

return function(mod)
  mod.options:define({
    { key = "qol_reusable_tms", type = "toggle", label = "REUSABLE TMS",
      default = true,
      help = "A TM is kept when it is used, the way an HM always has been." },
  })

  local okU, ItemUse = pcall(require, "src.core.game3.item_use")
  local okB, Bag = pcall(require, "src.core.game3.bag")
  if not (okU and type(ItemUse) == "table" and type(ItemUse.useTm) == "function"
          and okB and type(Bag) == "table" and type(Bag.get) == "function"
          and type(Bag.add) == "function") then
    mod.log:warn("Gen 3 TM use is not where this expects it; TMs stay single-use")
    return
  end

  local function isHm(id)
    local okD, ItemsData = pcall(require, "src.core.game3.items_data")
    if okD and type(ItemsData) == "table" and type(ItemsData.isHm) == "function" then
      local ok, hm = pcall(ItemsData.isHm, id)
      return ok and hm == true
    end
    return false
  end

  local unpack = unpack or table.unpack
  local function pack(...) return { n = select("#", ...), ... } end

  local base = ItemUse.useTm
  ItemUse.useTm = function(session, bag, id, partySlot, ...)
    if mod.options:get("qol_reusable_tms") == false or isHm(id) then
      return base(session, bag, id, partySlot, ...)
    end
    local before = tonumber(Bag.get(bag, id)) or 0
    local function giveBack()
      local now = tonumber(Bag.get(bag, id)) or 0
      if now < before then Bag.add(bag, id, before - now) end
    end

    -- The later path: the forget-a-move prompt this call may open, whose
    -- `onDone` is where the cart spends the TM when the slots were full.
    local okL, LearnMove = pcall(require, "src.core.game3.battle.learn_move")
    local realBegin = okL and type(LearnMove) == "table" and LearnMove.begin
    if realBegin then
      LearnMove.begin = function(opts, ...)
        if type(opts) == "table" and type(opts.onDone) == "function" then
          local done = opts.onDone
          opts.onDone = function(...)
            local results = pack(done(...))
            giveBack()
            return unpack(results, 1, results.n)
          end
        end
        return realBegin(opts, ...)
      end
    end
    local results = pack(pcall(base, session, bag, id, partySlot, ...))
    if realBegin then LearnMove.begin = realBegin end
    -- Before any error is passed on: a teach that spent the TM and then
    -- failed on its message has still spent it.
    giveBack()
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
  end
end
