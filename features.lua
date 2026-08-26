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
      dir = "Gen151",
      entry = "main.lua",
      label = "ALL 151",
      description = "EVERY ONE OF THE 151 OBTAINABLE IN ONE SAVE, ON ONE VERSION, WITHOUT TRADING.",
      enabledKey = "enabled",
      default = true,
      aliases = { "Gen151", "gen151" },
    },

    -- ---- experience sharing
    --
    -- Upstream keeps this on the engine's own OPTION screen and stores it in
    -- the save rather than in mod options, so the bundle does not try to move
    -- its storage -- it seeds the default and mirrors the rows into the
    -- bundle menu, and suppresses the upstream row so the setting has one
    -- home rather than two.

    {
      id = "expshare",
      dir = "ExpShare",
      entry = "main.lua",
      label = "EXP SHARE",
      description = "PARTY-WIDE EXPERIENCE: GEN 1, GEN 5+, BALANCED, AVERAGE OR A CUSTOM PERCENTAGE.",
      default = true,
      aliases = { "exp_share", "ExpShare" },
      adapter = "expshare",
      suppress_hooks = { ["ui.options.rows"] = true },
    },

    -- ---- later-generation conveniences
    --
    -- Upstream ships these four as one mod with its own submenu.  Here each is
    -- its own row in the bundle menu, because they are unrelated to each other
    -- and a player who wants easy HM use has no particular reason to want an
    -- XP bar.

    {
      id = "xpbar",
      dir = "QualityOfLife",
      entry = "bundle_xp_bar.lua",
      label = "BATTLE XP BAR",
      description = "A GEN 2 STYLE EXPERIENCE BAR UNDER YOUR POKEMON IN BATTLE.",
      default = false,
      gen1_only = true,
      aliases = { "qol_xp_bar" },
    },

    {
      id = "caught",
      dir = "QualityOfLife",
      entry = "bundle_caught_indicator.lua",
      label = "CAUGHT MARKER",
      description = "SHOWS WHETHER YOU HAVE ALREADY CAUGHT THE POKEMON YOU ARE FIGHTING.",
      default = false,
      aliases = { "qol_caught_indicator" },
    },

    {
      id = "banners",
      dir = "QualityOfLife",
      entry = "bundle_location_banners.lua",
      label = "AREA BANNER",
      description = "NAMES THE AREA YOU HAVE JUST WALKED INTO, ON A SIGN SIZED TO THE NAME.",
      -- The master here is the duration row rather than a synthesized toggle:
      -- OFF is already one of its values, so the switch is live and the menu
      -- row can say how long the sign stays up instead of merely ON.
      enabledKey = "qol_location_banners",
      default = false,
      aliases = { "qol_location_banners" },
    },

    {
      id = "interact",
      dir = "QualityOfLife",
      entry = "bundle_easy_interactions.lua",
      label = "EASY HM USE",
      description = "PRESS A AT BUSHES, BOULDERS AND WATER TO USE CUT, STRENGTH, SURF OR A ROD WITHOUT THE MENU.",
      default = false,
      aliases = { "qol_easy_interactions" },
    },
  },
}
