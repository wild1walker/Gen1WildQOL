-- What is in Gen1WildQOL, and how each piece is switched.
--
-- This is the whole of the bundle's configuration.  Adding a mod to the QOL
-- half is an entry here plus a submodule; nothing in runtime/ changes.
--
-- Fields:
--   id           the option prefix and the menu screen suffix.  Never change
--                one after release: it is what the player's stored settings
--                are keyed on.
--   dir          the folder under modules/, written by tools/build.py
--   entry        the upstream mod's own entry chunk, from its manifest
--   label        the row in the menu
--   description  shown on A when the feature has no settings of its own
--   group        which folder card in `spec.groups` this feature's row sits
--                on.  A feature naming no card, or one that is not declared,
--                gets a plain row on the top level instead of being hidden.
--   enabledKey   the upstream option row that already acts as a master
--                switch.  Present means the switch is live -- the feature's
--                own code reads it every time it acts, so OFF is the
--                untouched game with no relaunch.  Absent means the bundle
--                synthesizes a switch and gates installation with it, which
--                takes a relaunch to change.
--   default      what that switch ships as
--   defaults     bundle-level overrides for any upstream row's default
--   aliases      every name a sibling might call this feature by, for
--                mod.find
--   priority     the upstream manifest's own load priority.  Features install
--                in ascending priority, ties in declaration order -- which is
--                the order these mods were built and tested against.  It is
--                deliberately independent of the order they are written here,
--                which is the order the menu reads them in.
--   shared       this feature is carried by both bundles.  Exactly one may
--                install it, so the first to load claims it and the other
--                stands down; `storage` is the id its settings live under, so
--                they do not move when the winner does.  See runtime/claims.lua.
--   raw_option_keys  rows this feature writes by calling the engine's mod
--                manager, which does not know about prefixes
--   maintained   true when this repository looks after the source itself,
--                under maintained/<dir>/ rather than as a submodule.  Nothing
--                syncs it; edits go straight in.  It is still somebody else's
--                work by origin, and the credits say so.
--   adapter      a file under adapters/, run after the feature installs
--   suppress_hooks  engine hooks the feature must not register, because the
--                bundle surfaces that setting itself

return {
  spec = {
    id = "gen1_wild_qol",
    menu_label = "GEN1WILD QOL",
    screen_id = "Gen1WildQOL",
    -- Where mod.find looks when a feature asks for one of the mods that
    -- landed in the other half of the split.  Gen151 wants Gen1Dex; Gen1Dex
    -- is in the UI bundle.
    paired_bundle = "gen1_wild_ui",

    -- The folder cards the menu nests its rows under, in the order they are
    -- drawn.  Both halves of the suite declare the same six, because either
    -- half can end up hosting the merged menu and it should read the same way
    -- round whichever one the player opened.  A card with nothing in it is not
    -- drawn, so a half that has no features for a card simply does not show it.
    groups = {
      { id = "general",   label = "GENERAL",
        description = "MOVING AROUND, AND THE THINGS THE GAME DOES ON ITS OWN." },
      { id = "pokemon",   label = "POKEMON",
        description = "THE POKEMON THEMSELVES AND THE SCREENS ABOUT THEM." },
      { id = "battle",    label = "BATTLE",
        description = "WHAT A BATTLE LOOKS LIKE AND HOW IT PLAYS." },
      { id = "items",     label = "ITEMS",
        description = "THE BAG, THE MART, AND WHAT EVERY ITEM IS FOR." },
      { id = "save",      label = "SAVE",
        description = "SAVING, AND PICKING UP WHERE YOU LEFT OFF." },
      { id = "interface", label = "INTERFACE",
        description = "THE MENUS AND SCREENS EVERYTHING ELSE IS REACHED THROUGH." },
    },
  },

  features = {
    -- ---- getting around
    --
    -- The first thing anybody does in this game is walk, so the rows about
    -- walking come first.  A player opening this screen for the first time is
    -- usually looking for the run button, and it is now the first row rather
    -- than one of thirteen.
    {
      id = "sprint",
      group = "general",
      install_seq = 1,
      priority = 100,
      dir = "Gen1Sprint",
      entry = "main.lua",
      label = "SPRINT",
      description = "HOLD A BUTTON TO RUN AT FIRERED'S RUNNING-SHOES SPEED, AND A BICYCLE WORTH RIDING.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen1Sprint", "gen1_sprint" },
    },
    {
      id = "interact",
      group = "general",
      install_seq = 13,
      maintained = true,
      priority = 100,
      dir = "QualityOfLife",
      entry = "bundle_easy_interactions.lua",
      label = "EASY HM USE",
      description = "PRESS A AT BUSHES, BOULDERS AND WATER TO USE CUT, STRENGTH, SURF OR A ROD WITHOUT THE MENU.",
      -- The master is the feature's own row, not a switch of the bundle's.
      -- It used to be the latter, and that was a bug: the synthesized switch
      -- only decided whether to INSTALL, while this row decides whether the
      -- feature does anything -- so turning the feature on installed
      -- something still set to OFF, and the row that actually mattered was
      -- buried one screen down saying the opposite. Donating the row makes
      -- the two one switch, and a live one: the feature reads it every time
      -- it acts, so there is nothing to relaunch.
      -- Its sub-rows are unchanged: WATER INTERACTION ships FISH FIRST,
      -- REPEL PROMPT ships on, CUT GRASS inherits this row until set.
      enabledKey = "qol_easy_interactions",
      default = true,
      -- FieldMenu is the name the SELECT menu's row registry answers to.
      -- Purpose-named rather than dir-named: three features share the
      -- QualityOfLife directory and only this one publishes that surface, so
      -- a sibling asking for it should not have to know which folder it lives
      -- in or guess between the three.
      aliases = { "qol_easy_interactions", "FieldMenu" },
    },
    {
      id = "npcwalk",
      group = "general",
      install_seq = 14,
      maintained = true,
      priority = 100,
      dir = "QualityOfLife",
      entry = "bundle_npc_walk.lua",
      label = "NPC WALK",
      description = "NPCS TAKE ONE STEP PER TILE INSTEAD OF TWO, SO AN ESCORT WALKS INSTEAD OF HOPPING.",
      -- The feature's own row is the master, and it is live: the patched
      -- methods read it every time they draw, so OFF is the engine's own
      -- cadence back with no relaunch.
      enabledKey = "qol_npc_walk",
      default = true,
      aliases = { "qol_npc_walk", "NpcWalk" },
    },
    {
      id = "banners",
      group = "general",
      install_seq = 12,
      maintained = true,
      priority = 100,
      dir = "QualityOfLife",
      entry = "bundle_location_banners.lua",
      label = "AREA BANNER",
      description = "NAMES THE AREA YOU HAVE JUST WALKED INTO, ON A SIGN SIZED TO THE NAME.",
      -- The master here is the duration row rather than a synthesized toggle:
      -- OFF is already one of its values, so the switch is live and the menu
      -- row can say how long the sign stays up instead of merely ON.
      enabledKey = "qol_location_banners",
      -- The master here is the duration, so its default is a number of
      -- seconds rather than a boolean.
      default = 3,
      aliases = { "qol_location_banners" },
    },

    -- ---- your POKeMON
    --
    -- The two rows about the POKeMON themselves rather than about the game
    -- around them: the one walking behind you, and the moves the one in front
    -- of you can be taught.
    {
      id = "follower",
      group = "pokemon",
      install_seq = 5,
      priority = 100,
      dir = "Gen1Follower",
      entry = "main_sandbox.lua",
      label = "FOLLOWERS",
      description = "ALL 251 OVERWORLD FOLLOWERS, AND THE POKEMON STANDING ON THE MAPS, SIZED BY POKEDEX HEIGHT.",
      default = true,
      aliases = { "Gen1Follower", "PokePCFollowers", "followers" },
    },
    {
      id = "remember",
      group = "pokemon",
      install_seq = 7,
      priority = 1200,
      dir = "Gen1Remember",
      entry = "main.lua",
      label = "REMEMBER MOVES",
      description = "TEACH A POKEMON A MOVE IT HAS FORGOTTEN, FROM THE POPUP YOU ALREADY OPEN ON IT.",
      -- No master row of its own to donate: PARTY REMEMBER and BOX REMEMBER
      -- are two surfaces, not a switch for the mod. So the bundle
      -- synthesizes one, gates installation with it, and the menu marks the
      -- row as needing a relaunch.
      default = true,
      -- It asks for Gen1BillsBox to hang its row in the box popup too, and
      -- Gen1BillsBox lives in the other half. That lookup crosses the split
      -- through runtime/registry.lua, which is also why the handle it gets
      -- back has to be shaped like the engine's -- the mod reads
      -- `box.exports.actions`.
      aliases = { "Gen1Remember" },
    },

    -- ---- battles
    --
    -- EXP SHARE was the tenth row, below the mod manager, which is a strange
    -- place for the setting that decides how the whole party levels.  It is
    -- the one row here most likely to be changed before a new save is started,
    -- so it sits with the other battle rows near the top.
    {
      id = "expshare",
      group = "battle",
      install_seq = 10,
      priority = 100,
      dir = "ExpShare",
      entry = "main.lua",
      label = "EXP SHARE",
      description = "PARTY-WIDE EXPERIENCE: GEN 1, GEN 5+, BALANCED, AVERAGE OR A CUSTOM PERCENTAGE.",
      default = true,
      aliases = { "exp_share", "ExpShare" },
      maintained = true,
      adapter = "expshare",
      suppress_hooks = { ["ui.options.rows"] = true },
    },
    {
      id = "caught",
      group = "battle",
      install_seq = 11,
      maintained = true,
      priority = 100,
      dir = "QualityOfLife",
      entry = "bundle_caught_indicator.lua",
      label = "CAUGHT MARKER",
      description = "SHOWS WHETHER YOU HAVE ALREADY CAUGHT THE POKEMON YOU ARE FIGHTING.",
      -- The master is the feature's own row, not a switch of the bundle's.
      -- It used to be the latter, and that was a bug: the synthesized switch
      -- only decided whether to INSTALL, while this row decides whether the
      -- feature does anything -- so turning the feature on installed
      -- something still set to OFF, and the row that actually mattered was
      -- buried one screen down saying the opposite. Donating the row makes
      -- the two one switch, and a live one: the feature reads it every time
      -- it acts, so there is nothing to relaunch.
      -- Its OFF is a choice value rather than false, and RED and GREY
      -- are the Gen 1 looks beside GEN2.
      enabledKey = "qol_caught_indicator",
      default = "gen2",
      aliases = { "qol_caught_indicator" },
    },

    -- ---- catching everything
    --
    -- Not a visual change and not strictly a convenience either, but it is the
    -- one mod in the index that is neither, and it belongs with the half a
    -- player turns on to make a single save complete.  Its own switch is live,
    -- so OFF here really is vanilla encounters.
    {
      id = "gen151",
      group = "pokemon",
      install_seq = 6,
      priority = 900,
      dir = "Gen151",
      entry = "main.lua",
      label = "ALL 151",
      description = "EVERY ONE OF THE 151 OBTAINABLE IN ONE SAVE, ON ONE VERSION, WITHOUT TRADING.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen151", "gen151" },
    },

    -- ---- saving
    {
      id = "autosave",
      group = "save",
      install_seq = 2,
      priority = 50,
      dir = "Gen1AutoSave",
      entry = "main.lua",
      label = "AUTO SAVE",
      description = "SAVES ON A TIMER AND AFTER BATTLES, CATCHES AND NEW AREAS, WITH OPTIONAL ROLLBACK BACKUPS.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen1AutoSave", "gen1autosave" },
    },
    {
      id = "autocontinue",
      group = "save",
      install_seq = 3,
      priority = 100,
      dir = "Gen1AutoContinue",
      entry = "main.lua",
      label = "AUTO CONTINUE",
      description = "BOOT TO TITLE, ONE PRESS, PLAYING. SKIPS THE INTRO AND THE CONTINUE MENU.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen1AutoContinue", "gen1_auto_continue" },
    },

    -- ---- sound
    {
      id = "sound",
      group = "general",
      install_seq = 4,
      priority = 100,
      dir = "Gen1SoundQOL",
      entry = "main.lua",
      label = "SOUND",
      description = "THE LOW-HP SIREN BEEPS ONCE INSTEAD OF LOOPING, AND MOBILE MUTES WHEN ANOTHER APP TAKES THE AUDIO.",
      -- Gen1SoundQOL has no master row of its own: its rows are ALARM MODE,
      -- ALARM CYCLES and ALARM RETRIGGER, none of which is an off switch for
      -- the whole mod.  So the bundle synthesizes one.
      default = true,
      aliases = { "Gen1SoundQOL", "gen1_sound_qol" },
    },

    -- ---- the furniture
    --
    -- Last, and last in Gen1WildUI too, so the two halves read the same way
    -- round.  These two are in both bundles deliberately: they are not really
    -- conveniences or visual overhauls, they are how every other feature is
    -- reached.  A player who installs only this half should not lose the mod
    -- manager redraw, and one who installs only the other half should not lose
    -- it either -- so both carry them, and runtime/claims.lua makes sure only
    -- one of them ever installs one.
    --
    -- Their settings are stored under `gen1_wild_shared` rather than under
    -- either bundle, so which one won is invisible to the player: install the
    -- other half later, and the row order and manager layout are still what
    -- they were.
    {
      id = "menus",
      group = "interface",
      install_seq = 8,
      priority = 900,
      dir = "Gen1MenuManager",
      entry = "main.lua",
      label = "MENU LAYOUT",
      description = "REORDER THE START AND PC MENUS, HIDE ROWS YOU NEVER TOUCH, AND PIN FIELD MOVES TO ROWS OF THEIR OWN.",
      default = true,
      aliases = { "Gen1MenuManager" },
      shared = {
        claim = "gen1wild_menu_manager",
        storage = "gen1_wild_shared",
        owner = "gen1_wild_ui",
      },
    },
    {
      id = "modmenu",
      group = "interface",
      install_seq = 9,
      priority = 500,
      dir = "Gen1ModMenu",
      entry = "main.lua",
      label = "MOD MANAGER",
      description = "THE MOD MANAGER REDRAWN IN THE GAME'S OWN OPTION-SCREEN IDIOM, WITH SORTING AND FILTERS.",
      default = true,
      aliases = { "Gen1ModMenu", "gen1_mod_menu" },
      -- Set from this mod's own in-game quick menu, which goes through the
      -- engine manager's setOption and writes them unprefixed.
      raw_option_keys = { "sort", "hide_disabled", "only_options" },
      shared = {
        claim = "gen1wild_mod_menu",
        storage = "gen1_wild_shared",
        owner = "gen1_wild_ui",
      },
    },
  },
}
