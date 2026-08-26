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
  },

  features = {
    -- ---- movement and pacing

    {
      id = "sprint",
      priority = 100,
      dir = "Gen1Sprint",
      entry = "main.lua",
      label = "SPRINT",
      description = "HOLD A BUTTON TO RUN AT FIRERED'S RUNNING-SHOES SPEED, AND A BICYCLE WORTH RIDING.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen1Sprint", "gen1_sprint" },
    },

    -- ---- saving

    {
      id = "autosave",
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

    -- ---- followers

    {
      id = "follower",
      priority = 100,
      dir = "Gen1Follower",
      entry = "main_sandbox.lua",
      label = "FOLLOWERS",
      description = "ALL 251 GEN 1 AND GEN 2 OVERWORLD FOLLOWERS, SIZED BY POKEDEX HEIGHT.",
      default = true,
      aliases = { "Gen1Follower", "PokePCFollowers", "followers" },
    },

    -- ---- catching everything
    --
    -- Not a visual change and not strictly a convenience either, but it is the
    -- one mod in the index that is neither, and it belongs with the half a
    -- player turns on to make a single save complete.  Its own switch is live,
    -- so OFF here really is vanilla encounters.

    {
      id = "gen151",
      priority = 900,
      dir = "Gen151",
      entry = "main.lua",
      label = "ALL 151",
      description = "EVERY ONE OF THE 151 OBTAINABLE IN ONE SAVE, ON ONE VERSION, WITHOUT TRADING.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen151", "gen151" },
    },

    -- ---- the furniture
    --
    -- These two are in Gen1WildUI as well, and deliberately.  They are not
    -- really visual overhauls or conveniences: they are how every other
    -- feature is reached.  A player who installs only this half should not
    -- lose the mod manager redraw, and one who installs only the other half
    -- should not lose it either -- so both carry them, and runtime/claims.lua
    -- makes sure only one of them ever installs one.
    --
    -- Their settings are stored under `gen1_wild_shared` rather than under
    -- either bundle, so which one won is invisible to the player: install the
    -- other half later, and the row order and manager layout are still what
    -- they were.

    {
      id = "menus",
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

    -- ---- experience sharing
    --
    -- Originally ShaneMcGovernIE's exp_share, maintained here now rather than
    -- tracked: the source is under maintained/ExpShare and edits go straight
    -- in.  It keeps its mode on the engine's own OPTION screen and in the
    -- save rather than in mod options, so the bundle does not try to move its
    -- storage -- it seeds the default and mirrors the rows into the bundle
    -- menu, and suppresses the original row so the setting has one home
    -- rather than two.

    {
      id = "expshare",
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

    -- ---- later-generation conveniences
    --
    -- Originally unxpected-uxp's Quality of Life mod, maintained here now
    -- rather than tracked: the source is under maintained/QualityOfLife and
    -- edits go straight in.  It shipped these four as one mod behind one
    -- submenu; here each is its own row, because they are unrelated to each
    -- other and a player who wants easy HM use has no particular reason to
    -- want an XP bar.

    {
      id = "xpbar",
      maintained = true,
      priority = 100,
      dir = "QualityOfLife",
      entry = "bundle_xp_bar.lua",
      label = "BATTLE XP BAR",
      description = "A GEN 2 STYLE EXPERIENCE BAR UNDER YOUR POKEMON IN BATTLE.",
      default = true,
      -- The master switch decides whether the feature is installed; the
      -- feature's own row decides whether it draws. Both have to be on for
      -- the bar to appear, so the row is defaulted here alongside the
      -- switch -- otherwise ON would install something set to OFF.
      defaults = { qol_exp_bar = "on" },
      gen1_only = true,
      aliases = { "qol_xp_bar" },
    },

    {
      id = "caught",
      maintained = true,
      priority = 100,
      dir = "QualityOfLife",
      entry = "bundle_caught_indicator.lua",
      label = "CAUGHT MARKER",
      description = "SHOWS WHETHER YOU HAVE ALREADY CAUGHT THE POKEMON YOU ARE FIGHTING.",
      default = true,
      -- "gen2" is the first of its three ON styles; RED and GREY are the
      -- Gen 1 looks, one row away.
      defaults = { qol_caught_indicator = "gen2" },
      aliases = { "qol_caught_indicator" },
    },

    {
      id = "banners",
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

    {
      id = "interact",
      maintained = true,
      priority = 100,
      dir = "QualityOfLife",
      entry = "bundle_easy_interactions.lua",
      label = "EASY HM USE",
      description = "PRESS A AT BUSHES, BOULDERS AND WATER TO USE CUT, STRENGTH, SURF OR A ROD WITHOUT THE MENU.",
      default = true,
      -- Its sub-rows need nothing here: WATER INTERACTION already ships
      -- FISH FIRST, REPEL PROMPT already ships on, and CUT GRASS inherits
      -- this row when it has never been set.
      defaults = { qol_easy_interactions = true },
      aliases = { "qol_easy_interactions" },
    },
  },
}
