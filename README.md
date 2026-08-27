# Gen1WildQOL

**The quality-of-life half of the [Gen1Wild](https://github.com/wild1walker/Gen1Wild)
suite, as one mod.** Fourteen features: thirteen from eleven sources, and one
written here. Nine are still their own mods with their own releases, tracked
here and not forked; `EXP SHARE` and the three later-generation conveniences
began as other people's mods and are maintained in this repository now.
`ROTATE PROFILES` is this repository's own.

Its other half is [Gen1WildUI](https://github.com/wild1walker/Gen1WildUI),
which carries the visual overhauls. The two know about each other: a feature in
one can still find a feature in the other.

## What is in it

Everything here is a row in `OPTION > GEN1WILD QOL`, switched on or off by
itself. Nothing is all-or-nothing.

| Feature | Ships | From |
|---|---|---|
| **SPRINT** | on | [Gen1Sprint](https://github.com/wild1walker/Gen1Sprint) |
| **AUTO SAVE** | on | [Gen1AutoSave](https://github.com/wild1walker/Gen1AutoSave) |
| **AUTO CONTINUE** | on | [Gen1AutoContinue](https://github.com/wild1walker/Gen1AutoContinue) |
| **SOUND** | on | [Gen1SoundQOL](https://github.com/wild1walker/Gen1SoundQOL) |
| **ROTATE PROFILES** ¶ | on, **WIDE** | written here |
| **FOLLOWERS** | on | [Gen1Follower](https://github.com/wild1walker/Gen1Follower) |
| **ALL 151** | on | [Gen151](https://github.com/wild1walker/Gen151) |
| **EXP SHARE** | on, **GEN 5+** | originally [exp_share](https://github.com/ShaneMcGovernIE/exp_share) ‡ |
| **CAUGHT MARKER** | on | originally [Quality of Life](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol) ‡ |
| **AREA BANNER** | on, 3s | Quality of Life ‡ |
| **EASY HM USE** | on | Quality of Life ‡ |
| **REMEMBER MOVES** | on | [Gen1Remember](https://github.com/wild1walker/Gen1Remember) |
| **MENU LAYOUT** † | on | [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) |
| **MOD MANAGER** † | on | [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu) |

† Also in [Gen1WildUI](https://github.com/wild1walker/Gen1WildUI). These two are
not really quality-of-life or visual — they are the furniture everything else
is reached through — so both halves carry them and neither loses them. Install
both bundles and exactly one of them sets it up; see
[Features in both bundles](#features-in-both-bundles).

¶ Phones and tablets only. Nothing rotates on a desktop or a console, so the
row is there and inert.

‡ Maintained in this repository rather than tracked. The source is under
`maintained/`, edits go straight in, and nothing syncs it from anywhere. The
credit for what it does still belongs to the people named in
[Credits](#credits).

## The menu

```
OPTION
  GEN1WILD QOL        CONFIGURE
    SPRINT            ON (CONFIGURE)     <- LEFT/RIGHT switches it
      HOLD            B                  <- A opens this
      SPRINT SPEED    2x
      BIKE SPEED      2x
      SPRINT SURFING  OFF
      SPRINT ON BIKE  OFF
      RESET DEFAULTS
    AUTO SAVE         ON (CONFIGURE)
    ROTATE PROFILES   ON (CONFIGURE)
      SIDEWAYS        WIDE
      RESET DEFAULTS
    AREA BANNER       ON (3 SECONDS)
    ...
```

`LEFT`/`RIGHT` switches a feature or changes a setting, `A` opens a feature's
settings or explains a row, `B` goes back. Every feature screen ends in
`RESET DEFAULTS`.

A row marked `*` needs a relaunch to take effect, and the footer says so. That
happens for features whose upstream mod has no off switch of its own: the
bundle gates those at load rather than pretending to switch something that is
already installed. Features that do have one — SPRINT, AUTO SAVE, AUTO
CONTINUE, ROTATE PROFILES, ALL 151, AREA BANNER, CAUGHT MARKER and EASY HM USE
— switch live.

## What is different from the standalone mods

- **EXP SHARE defaults to GEN 5+.** The fighters keep their full experience and
  every living bench Pokémon gains half a fighter's share. It is seeded once,
  on a save that has never carried the setting; a stored choice is never
  overwritten, including `OFF`.
- **The area banner is redrawn.** Upstream's is the dialogue box's exact
  geometry — twenty tiles wide, four tall, flush with the bottom of the screen
  — carrying one line of text, over the ground you are walking on. It is now a
  plaque sized to the name it carries, anchored top-left, sliding in and out
  from that edge. `POSITION` moves it and `BOTTOM` restores the original.
- **The XP bar is not here any more.** It is `XP BAR` in
  [Gen1BattleUI](https://github.com/wild1walker/Gen1BattleUI), which ships in
  [Gen1WildUI](https://github.com/wild1walker/Gen1WildUI) — a battle UI
  feature, in the battle UI mod. The move that mattered was not tidiness: from
  here the bar was drawn by a wrapper around `battle.draw`, which runs after
  every `battle.overlay` link whatever priority they carry, so it could not be
  drawn over and clipped itself to `x=88` — where the *vanilla* move panel
  ends. Gen1BattleUI's panel ends at 112, so it lay across that panel's PP
  row. Drawn from inside that mod it simply goes down before the panel does.
- **`ROTATE PROFILES` is not one of the standalone mods at all.** It was
  written here, for this bundle. See [Rotating the phone](#rotating-the-phone).
- **The three remaining Quality of Life features are three rows**, not one
  submenu.
- **EXP SHARE is configured here**, not on the engine's own OPTIONS screen.

## Rotating the phone

`ROTATE PROFILES` is a second set of screen settings, kept for landscape.
Turn the phone sideways and they go on; turn it back and the upright ones come
straight back. It is on iOS and Android only — a desktop window that happens to
be wide is not a phone held sideways, so the row sits there doing nothing
everywhere else.

It ships as `SIDEWAYS: WIDE`, which is the widescreen set the engine's own
`OPTION` screen offers plus the 10:9 lock off:

| Sideways | |
|---|---|
| `BATTLE LAYOUT` | `WIDE` |
| `BATTLE SIZE` | `FILL` |
| `BATTLE HUD` | `EXTENDED` |
| `UI LAYOUT` | `DYNAMIC` |
| `FAITHFUL RATIO` | `OFF` |

`FAITHFUL RATIO` is in there because holding an exact 10:9 is the one setting
that throws away the width a turned phone has just gained — `WIDE` without it
would be half a profile.

`SIDEWAYS: CUSTOM` opens a row per setting instead, each shipping as `SAME`,
which means *leave that one alone*. A profile that is `SAME` all the way down
does nothing at all, which is what `CUSTOM` starts as. The rows are
`BATTLE LAYOUT`, `BATTLE SIZE`, `BATTLE HUD`, `UI LAYOUT`, `FAITHFUL RATIO`,
`UI LETTERBOX` and `SCREEN POS` — the screen and nothing else. Text speed,
battle style, volumes and the rest of the `OPTION` screen mean the same thing
in both orientations, so nothing switches them.

Three things it deliberately does not do:

- **It is not an orientation lock.** `ORIENTATION` on the game's own `OPTION`
  screen decides which way up the game is allowed to be, and this leaves it
  alone. Lock the game to portrait there and this feature never has anything
  to do.
- **It never saves a landscape value.** The profile is put on the live options
  and taken back off; `options.lua` keeps saying what you set upright, so a
  phone closed while sideways loses nothing. Anything that saves the options
  while the profile is on — turning the music down on the `OPTION` screen —
  writes the upright values too.
- **It does not lock what it sets.** Change one of the covered rows by hand
  while the phone is sideways and it stays changed. Turning the phone back is
  still the picture you set upright.

## Features in both bundles

`MENU LAYOUT` and `MOD MANAGER` are in Gen1WildUI too. They are how every other
feature is reached — the START menu, the PC menu, the mod manager itself — so
neither half is the right place to put them and neither half should go without.

Both bundles would install them twice, and neither mod guards against that:
Gen1ModMenu would wrap the manager screen around its own wrapper, and
Gen1MenuManager would apply its row order to an order it had already applied.
So the two bundles agree on who does it. The first to load claims the feature
through a table parked on a shared engine module; the second sees the claim and
stands down, and its menu row says where the settings are:

```
GEN1WILD QOL
  MENU LAYOUT     ON (SET UP IN GEN1WILD UI)
```

The switch on that row is still the real switch — settings for a shared feature
are stored under `gen1_wild_shared` rather than under either bundle, so both
menus read and write the same values, and installing the other half later does
not reset anything.

Which bundle wins does not matter and is not forced: both carry the same mod
pinned at the same version. `tools/check.py` cross-checks the declaration
against the other repo when it is checked out beside this one, because getting
it wrong in one of them fails silently.

Everything else behaves as its own mod does, because it *is* its own mod: the
source is vendored unmodified and re-read on every sync.

## Installing

**MODS > Import mod .zip**, using the `.zip` from
[Releases](https://github.com/wild1walker/Gen1WildQOL/releases/latest). Or copy
this folder into the game's `mods/` directory.

Uninstall the standalone versions of anything above first — the manifest
declares them as conflicts, because they install the same hooks. Settings do
not carry over: they are stored under this bundle's id.

## How it stays up to date

Source lives in one of two places, and which one says who looks after it:

| | |
|---|---|
| `upstream/<Repo>/` | A submodule pinned to a release. Somebody else's mod, tracked, never edited here. |
| `maintained/<Dir>/` | Source this repository looks after itself. Edited here; nothing syncs it. |

`tools/build.py` copies from whichever applies into `modules/`, which is what
the game reads. `tools/check.py` fails if a feature is in both, in neither, or
declared as one and sitting in the other.

For the tracked nine:

```sh
git submodule update --init --recursive   # first time
python3 tools/sync.py                     # move every pin to its newest release
python3 tools/sync.py Gen1Sprint          # or just one
python3 tools/sync.py --dry-run           # report, change nothing
```

`sync.py` moves the pins and rebuilds `modules/`. It never touches
`maintained/` — there is nothing to sync it from — and lists those at the end
of a run so a short report is not a surprise. Then look at the diff and commit
it:

```sh
git diff --stat modules upstream
python3 tools/check.py
git add upstream modules && git commit
```

An upstream that **adds an option row** needs nothing: the schema is read at
load, so the row appears in the menu on its own. An upstream that **adds a
whole feature**, **renames an option key** or **moves its entry file** needs an
edit to `features.lua` — and `tools/check.py` fails loudly if it does.

## Layout

```
main.lua              bootstrap; loads the runtime and gets out of the way
features.lua          what is in the bundle and how each piece is switched
runtime/              how a bundle hosts a mod written to be standalone
  loader.lua            reading and loading a bundled mod's own files
  facade.lua            the `mod` object each feature is handed instead
  optionset.lua         one options table for mods that each expected to own it
  registry.lua          mod.find, across features and across both bundles
  claims.lua            who installs a feature that is in both bundles
  menu.lua              the OPTION screens
  bundle.lua            the order all of the above happens in
adapters/             per-feature bundle glue, run after a feature installs
upstream/<Repo>/      submodules; tracked, never edited here
maintained/<Dir>/     source this repository looks after itself
modules/<Dir>/        built by tools/build.py; what the game loads
tools/                build.py, sync.py, check.py
tests/                headless coverage of the runtime seam
```

`modules/` is committed rather than built at install time, because a mod is
installed by copying a folder and nothing runs a build. CI rebuilds it and
fails if it differs from what is committed, so the two cannot drift.

## How it works

Eleven mods that were each written believing they owned the options table is
the whole problem. Five of them call their master switch `enabled`; two call a
row `species_colours`. Merged naively they would share storage, and turning off
one feature would turn off another.

So no feature is given the real `mod` object. Each gets a facade that keeps its
assumptions true from the inside:

| It asks for | It gets |
|---|---|
| `mod:read("src/x.lua")` | `modules/<Feature>/src/x.lua` |
| `mod.options:get("enabled")` | `<feature>_enabled` |
| `mod.save:get("last_pocket")` | `<feature>.last_pocket` |
| `mod.cache:read("layout")` | `<feature>.layout` |
| `mod.find("Gen1Dex")` | the sibling's exports, in either bundle |

Anything the facade does not name falls through to the real mod untouched, so
hooks, events, world, UI and content behave exactly as they always did — and a
feature that starts using a new engine API keeps working without the facade
being taught about it.

`mod.find` is the interesting one. `Gen151` asks for `Gen1Dex` to hang catch
hints off the Pokédex, and the QOL/UI split puts them in different bundles. A
lookup goes to this bundle first, then to the paired bundle through its
exports, then out to the engine — so the optional-dependency graph survives
being cut in half.

Two mods sharing the engine's `mod.options_changed` event have the same
problem in reverse: each filters it against what it believes its own identity
and option keys are. The facade rewrites that payload into the feature's own
vocabulary, so `Gen1AutoSave` still notices its interval changing.

There is a headless test for each of those seams:

```sh
luajit tests/runtime_test.lua
```

## Credits

Everything here is somebody's work, and mostly not mine — `ROTATE PROFILES`
is the one feature written here rather than adopted. Two of the others are
maintained in this repository now rather than tracked upstream — that changes
who looks after the code, not who wrote it:

- **[unxpected-uxp](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol)**
  — the caught marker, easy interactions, and the location banner this bundle
  redraws. `CAUGHT MARKER`, `AREA BANNER` and `EASY HM USE` descend from their
  work, as does the XP bar that now ships in Gen1BattleUI.
- **[ShaneMcGovernIE](https://github.com/ShaneMcGovernIE/exp_share)** —
  exp_share, essentially whole. `EXP SHARE` is their mod with a different
  default and a different menu around it.
- **Antigravity, gamecorner33** and the PokéPC / Followers EX lineage, whose
  Gen II sheets descend from **ShockSlayer** and the **Pokémon Crystal Clear**
  team — the follower work `Gen1Follower` is built from.
- **Wowabox (Darklinkduck)** — *All Pokémon Catchable 151*, which reached a
  complete Kanto dex in one save first.
- **[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)** and
  **[pret](https://github.com/pret)** — the engine and the disassemblies all of
  it stands on.

The bundling is MIT -- see [LICENSE](LICENSE), which says what that does
and does not cover. Each tracked mod keeps its own licence file under
`modules/<Feature>/`, and those are the terms for that feature.

Contributions to a **tracked** feature belong in that mod's own repository,
behind its link above. Contributions to a **maintained** one, and fixes to the
bundling itself, belong here.
