-- The host every battle overlay in this bundle draws through.
--
-- One wrap of `battle.draw` rather than one per overlay, and one place that
-- works out WHERE an overlay is drawing: the flat 160x144 GB frame, or the
-- world canvas a voxel mod put the battle on.  See runtime/voxel.lua for why
-- that second question has more than two answers and why "no" is the default.

local M = {}

function M.new(mod)
  local voxel = mod.voxel
  local overlays = {}
  local wrapped = setmetatable({}, { __mode = "k" })
  local installed = false
  local service = {}

  function service:add(overlay)
    overlays[#overlays + 1] = overlay
  end

  -- Wrap the voxel mod's `snapHUDs` so its per-frame answer is readable off
  -- the battle.  Tried at the start of each battle rather than on
  -- `mods.loaded`, and that is not a preference: `install` is itself called
  -- FROM a mods.loaded handler (bundle_common.battleService), so a second
  -- subscription to the event being dispatched is a subscription that may
  -- never be called.  A battle is later than mods.loaded by any route, which
  -- is all this needs -- and retrying per battle also picks up a voxel mod
  -- that arrived late.
  --
  -- Cheap after the first success: the provider is memoised and the wrap tags
  -- the table it is on, so every call after the first is a table lookup.  With
  -- no voxel mod -- the ordinary case -- it is a lookup that finds nothing.
  local hooked = false
  local function hookHudSnap()
    if hooked or not voxel then return end
    local ok, result = pcall(voxel.installHudSnapHook)
    if ok and result then hooked = true end
  end

  function service:install()
    if installed then return end
    installed = true
    mod.events:on("battle.started", function(event)
      local battle = event and event.battle
      if not battle or wrapped[battle] or type(battle.draw) ~= "function" then
        return
      end
      hookHudSnap()

      local states = {}
      local failed = {}
      for i, overlay in ipairs(overlays) do
        states[i] = overlay.start and overlay.start(event) or {}
      end
      wrapped[battle] = states

      local baseDraw = battle.draw
      battle.draw = function(self, ...)
        baseDraw(self, ...)
        if self.blankForAskName then return end

        local fx = self.fx
        local sx = fx and fx.shakeX or 0
        local sy = fx and fx.shakeY or 0
        if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
          sx = self.frame % 4 < 2 and 2 or -2
        end
        -- Set ONLY while the HUDs are genuinely on the world canvas this
        -- frame.  An overlay reads it as "follow the HUD onto the canvas",
        -- and nil as "draw where you always drew" -- which is the answer with
        -- no voxel mod, and equally the answer under a fork that leaves the
        -- HUDs in the GB frame.  Deciding this once here is why no overlay
        -- has to know a voxel mod exists.
        local voxel3dBattleData = voxel and voxel.snappedShot(self) or nil
        local context = {
          sx = sx,
          sy = sy,
          slide = (self.introSlide or 0) * 4,
          voxel3dBattleData = voxel3dBattleData,
        }

        for i, overlay in ipairs(overlays) do
          if not failed[i] then
            love.graphics.push("all")
            local ok, err = pcall(overlay.draw, self, states[i], context)
            love.graphics.pop()
            if not ok then
              failed[i] = true
              mod.log:error("%s battle overlay disabled: %s",
                overlay.id, tostring(err))
            end
          end
        end
      end
    end)
  end

  return service
end

return M
