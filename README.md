# Gen1WildQOL

**The quality-of-life half of the [Gen1Wild](https://github.com/wild1walker/Gen1Wild)
suite, as one mod.** Thirteen features from eleven sources. Nine are still
their own mods with their own releases, tracked here and not forked; `EXP SHARE`
and the three later-generation conveniences began as other people's mods and are
maintained in this repository now.

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

‡ Maintained in this repository rather than tracked. The source is under
`maintained/`, edits go straight in, and nothing syncs it from anywhere. The
credit for what it does still belongs to the people named in
[Credits](#credits).

## The menu

```
OPTION
  WILD GREEN          13 MODS            <- in place of the MODS row
    GENERAL           ALL 4 ON
      SPRINT          ON (CONFIGURE)     <- LEFT/RIGHT switches it
        HOLD          B                  <- A opens this
        SPRINT SPEED  2x
        BIKE SPEED    2x
        SPRINT SURFING  OFF
        SPRINT ON BIKE  OFF
        RESET DEFAULTS
      AREA BANNER     ON (3 SECONDS)
      ...
    POKEMON           ALL 3 ON
    BATTLE            ALL 2 ON
    SAVE              ALL 2 ON
    INTERFACE         ALL 2 ON
    OTHER MODS        2 MODS             <- anything else that is loaded
    MOD MANAGER       13 INSTALLED       <- the engine's own MODS screen
```

The top row takes the OPTION screen's own `MODS` row rather than sitting next
to it, and `START > MODS` opens the same screen. It is named after the cart
when one is running — `WILD GREEN` — and after the bundle (`GEN1WILD QOL`) when
one half is installed on its own. The engine's mod list is `MOD MANAGER` at the
bottom, one press further in.

The cards are the same six in both halves and in the same order, so the menu
reads the same way round whichever half you opened. A card with nothing in it
is not drawn.

`LEFT`/`RIGHT` switches a feature or changes a setting, `A` opens a card, a
feature's settings, or an explanation of the row, `B` goes back. Every feature
screen ends in `RESET DEFAULTS`.

A row marked `*` needs a relaunch to take effect, and the footer says so. That
happens for features whose upstream mod has no off switch of its own: the
bundle gates those at load rather than pretending to switch something that is
already installed. Features that do have one — SPRINT, AUTO SAVE, AUTO
CONTINUE, ALL 151, AREA BANNER, CAUGHT MARKER and EASY HM USE
— switch live.

## The SELECT menu is a list other mods can join

`EASY HM USE` puts a field-move menu on `SELECT`: `FLY`, `TELEPORT`, `FLASH`,
`DIG`, a repel. It is built fresh on every press out of what is usable *right
now* — `FLY` only outdoors, `FLASH` only in the dark, a repel only while one is
in the bag — so it is not a menu with a fixed shape. It is a question about
this tile, this party and this bag, asked again every time.

Two things follow from that.

**Every row carries an `id`.** A label is what a row says and moves with the
language and with which repel is in the bag; an id is what the row *is*, and
anything that wants to reorder the list, hide a row or add one needs a name for
a row that is not on screen at the moment.

**And the list is handed round before it is drawn.**

```lua
local qol = mod.find("Gen1WildQOL")
qol.exports.fieldMenu.provide(function(game, ow, rows)
  rows[#rows + 1] = { id = "mine", label = "MINE", onSelect = ... }
  return rows
end, mod.id)
```

A registry rather than a hook, because `mod.hooks` gives a mod `wrap` and no
way to *emit* one of its own — Gen1Dex's `area.provide` is the same answer to
the same problem. The provider is handed the rows and hands back the rows;
returning nothing leaves them alone, and it is tagged by owner so a hot reload
replaces it rather than stacking a second copy.

Rows land above `CANCEL`, which stays the floor of the menu. A provider that
raises is skipped and said so once: a menu that fails to open because somebody
else's row threw is a worse bug than a missing row. Gating is the provider's
own business — this only promises that what *it* put there is usable here.

A provider can declare the rows it contributes as a third argument —
`provide(fn, mod.id, { { id = "mine", label = "MINE" } })` — and
`exports.fieldMenu.catalog()` returns every row this menu can *ever* show,
declared rows included. That is what lets a row be arranged before it has ever
been on screen: this menu shows `FLY` only outdoors and `FLASH` only in the
dark, so an editor that knew only what it had seen could arrange almost none of
it.

`MAP` is the first row built on that: the town map, outdoors. It has no switch
of its own — the layout editor is what takes a row off this menu, and a second
switch for the same row is how you get one that reads `ON` and is not there.

## Your settings survive the cart's seal

Wild Green is a **sealed** cart, and a sealed cart's per-mod options are not
the player's. `Loader:_applyCart` rebuilds `loader.modOptions` on every boot
out of what the cart pins and discards the stored values:

```lua
for id, pin in pairs(report.pins) do
  local bucket = {}
  for key, value in pairs(pin.options or {}) do bucket[key] = value end
  if not report.enforced then
    for key, value in pairs(self.modOptions[id] or {}) do bucket[key] = value end
  end
  merged[id] = bucket
end
```

`enforced` is true for any seal that is not `open`, so `sealed` and `sealed+`
both do it. On this cart that meant every setting in the suite reset on the
next launch — and one of them, Wild Green's `PLAYER`, could never take effect
at all: the overworld walker is a record read at load, and the load is exactly
when the choice was being thrown away.

**Unsealing is not the answer.** Online play requires the seal and requires it
to be exactly `sealed`: `ArenaData.profile` refuses any other value, and the
online panel lists no other kind. `open` would keep the settings and lose the
arena.

So `runtime/settings.lua` remembers what you chose in this bundle's own cache —
installation-wide, and untouched by that merge — and puts it back as the bundle
installs, which is before anything reads it. This bundle is first in the cart's
load order, which is what puts the restore ahead of the mod whose option is read
at load time.

It restores into **the same table the engine's mod manager reads**, so there is
no second source of truth: the manager, this suite's own menu and the mods
themselves all see one value, and it is yours.

Nothing here touches the cart file, and the cart file is what online matches on
— `ArenaData.profile` keys its fingerprint on `CartStore`'s hash of the
manifest, never on live option values. The seal keeps every guarantee the arena
asks of it.

The trade is that the cart's pins become **defaults rather than locks**: a
pinned value is what you get until you choose otherwise. A cart that needs a
value fixed for everybody should pin it and not ship this.

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
- **The three remaining Quality of Life features are three rows**, not one
  submenu.
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

Everything here is somebody's work, and mostly not mine. Two of these are
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
