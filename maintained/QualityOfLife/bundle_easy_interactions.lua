-- Cut, Strength, Surf, Fish, Fly, Dig, Flash and Teleport without the menu.
--
-- One of the four upstream Quality of Life features, split out so it can be
-- switched on by itself.  Everything of substance is in the vendored
-- qol_feature_easy_interactions.lua, which is untouched; this file only supplies the
-- generation probe and options reader its install expects.

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
  Common.install(mod, "qol_feature_easy_interactions.lua", false)
end
