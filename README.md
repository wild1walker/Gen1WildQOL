# Gen1WildQOL

**The quality-of-life half of the [Gen1Wild](https://github.com/wild1walker/Gen1Wild)
suite, as one mod.** Thirteen features from ten repositories, each of which is
still its own mod with its own releases — this bundles them, it does not fork
them.

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
| **FOLLOWERS** | on | [Gen1Follower](https://github.com/wild1walker/Gen1Follower) |
| **ALL 151** | on | [Gen151](https://github.com/wild1walker/Gen151) |
| **EXP SHARE** | on, **GEN 5+** | [exp_share](https://github.com/ShaneMcGovernIE/exp_share) |
| **BATTLE XP BAR** | off | [Quality of Life](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol) |
| **CAUGHT MARKER** | off | Quality of Life |
| **AREA BANNER** | off | Quality of Life |
| **EASY HM USE** | off | Quality of Life |
| **MENU LAYOUT** † | on | [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) |
| **MOD MANAGER** † | on | [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu) |

† Also in [Gen1WildUI](https://github.com/wild1walker/Gen1WildUI). These two are
not really quality-of-life or visual — they are the furniture everything else
is reached through — so both halves carry them and neither loses them. Install
both bundles and exactly one of them sets it up; see
[Features in both bundles](#features-in-both-bundles).

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
    AREA BANNER       ON (2 SECONDS)
    ...
```

`LEFT`/`RIGHT` switches a feature or changes a setting, `A` opens a feature's
settings or explains a row, `B` goes back. Every feature screen ends in
`RESET DEFAULTS`.

A row marked `*` needs a relaunch to take effect, and the footer says so. That
happens for features whose upstream mod has no off switch of its own: the
bundle gates those at load rather than pretending to switch something that is
already installed. Features that do have one — SPRINT, AUTO SAVE, AUTO
CONTINUE, ALL 151, AREA BANNER — switch live.

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
- **The XP bar stops drawing when your Pokémon faints.** Upstream's keeps
  going, leaving a blue stripe over the empty space the HUD was cleared from.
  Fixed here without editing the vendored file — see
  `overlays/QualityOfLife/bundle_common.lua`.
- **The four Quality of Life features are four rows**, not one submenu.
- **EXP SHARE is configured here**, not on the engine's own OPTIONS screen.

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

Each feature is a git submodule under `upstream/`, pinned to a release. Nothing
is forked and nothing is hand-copied.

```sh
git submodule update --init --recursive   # first time
python3 tools/sync.py                     # move every pin to its newest release
python3 tools/sync.py Gen1Sprint          # or just one
python3 tools/sync.py --dry-run           # report, change nothing
```

`sync.py` moves the pins and rebuilds `modules/`, which is what the game reads.
Then look at the diff and commit it:

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
overlays/<Dir>/       this bundle's own files, laid over an upstream's
upstream/<Repo>/      submodules; the source of truth, never edited here
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

Everything here is somebody's work, and mostly not mine:

- **[unxpected-uxp](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol)**
  — the XP bar, the caught marker, easy interactions, and the location banner
  this bundle redraws.
- **[ShaneMcGovernIE](https://github.com/ShaneMcGovernIE/exp_share)** —
  exp_share, carried whole.
- **Antigravity, gamecorner33** and the PokéPC / Followers EX lineage, whose
  Gen II sheets descend from **ShockSlayer** and the **Pokémon Crystal Clear**
  team — the follower work `Gen1Follower` is built from.
- **Wowabox (Darklinkduck)** — *All Pokémon Catchable 151*, which reached a
  complete Kanto dex in one save first.
- **[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)** and
  **[pret](https://github.com/pret)** — the engine and the disassemblies all of
  it stands on.

Each vendored mod keeps its own licence file under `modules/<Feature>/`.

Contributions belong in the mod's own repository, behind its link above. Fixes
to the bundling itself belong here.
