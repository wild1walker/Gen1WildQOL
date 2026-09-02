-- See qol_feature_forget_hm.lua, which is where the whole of this lives.
--
-- One of the bundle's split Quality of Life features: this file only supplies
-- the generation probe and the options reader its install expects, the same
-- way bundle_caught_indicator.lua does.  `false` because it draws nothing --
-- there is no battle overlay to hang on the shared host.

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
  Common.install(mod, "qol_feature_forget_hm.lua", false)
end
