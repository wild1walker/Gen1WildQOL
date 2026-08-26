-- A Gen 2 style experience bar under the player's Pokemon in battle.
--
-- One of the four upstream Quality of Life features, split out so it can be
-- switched on by itself.  Everything of substance is in the vendored
-- qol_feature_xp_bar.lua, which is untouched; this file supplies the
-- generation probe and options reader its install expects, plus one guard.
--
-- The guard is for a bug upstream still has: the bar keeps drawing after the
-- player's Pokemon faints, leaving a blue stripe over the empty space the HUD
-- was cleared from. Common.playerHudVisible is the predicate the vendored
-- file is missing, and the reasoning is written out there.

return function(mod)
  local common = mod:read("bundle_common.lua")
  if not common then
    mod.log:error("bundle_common.lua is missing -- reinstall the mod")
    return
  end
  local chunk = load(common, "@" .. tostring(mod.path) .. "/bundle_common.lua")
  if not chunk then
    mod.log:error("bundle_common.lua did not compile")
    return
  end
  local Common = chunk()
  Common.install(mod, "qol_feature_xp_bar.lua", true, Common.playerHudVisible)
end
