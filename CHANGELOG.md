# Changelog

## 1.4.0

Adds **REMEMBER MOVES**, from
[Gen1Remember](https://github.com/wild1walker/Gen1Remember) — teach a Pokémon a
move it has forgotten, from the popup you already open on it. Tracked as a
submodule pinned to 1.0.0. It ships on, and `Gen1Remember` joins the manifest's
conflicts, so the bundle and the standalone are mutually exclusive.

| Row | Ships |
|---|---|
| `PARTY REMEMBER` | on |
| `BOX REMEMBER` | on |
| `PRE-EVO MOVES` | on |
| `HIDE WHEN EMPTY` | on |

`REMEMBER MOVES` takes a relaunch to switch: `PARTY REMEMBER` and `BOX REMEMBER`
are two surfaces rather than a switch for the mod, so there is no row to donate
as its master and the bundle gates it at load.

`BOX REMEMBER` hangs its row in Gen1BillsBox's popup, and Gen1BillsBox lives in
[Gen1WildUI](https://github.com/wild1walker/Gen1WildUI). That lookup crosses the
split, and needs Gen1WildUI 1.3.0 or newer — the version whose Gen1BillsBox
publishes the provider registry. Without it the party row still works.

### Fixed

- **`mod.find` handed back the wrong shape, and cross-mod integrations went
  quietly dead.** The engine's own returns a handle — `{ id, version, exports }`
  — and mods read it that way. The bundle's registry answered with the exports
  table itself, so `dex.exports` was nil and the integration simply did nothing
  rather than failing. Gen151's Pokédex catch hints had never registered inside
  this bundle. Handles now match the engine's, `tools/build.py` writes the
  version map they carry, and the shape is pinned by a test.

## 1.3.0

**`BATTLE XP BAR` has moved out of this bundle.** It is `XP BAR` in
[Gen1BattleUI](https://github.com/wild1walker/Gen1BattleUI) now, which ships in
[Gen1WildUI](https://github.com/wild1walker/Gen1WildUI) — a battle UI feature,
in the battle UI mod.

The move is a bug fix, not a tidy-up. From here the bar was drawn by a wrapper
around `battle.draw`, which runs after **every** link on `battle.overlay`
however high a priority they carry — so it could not be drawn over by anything
and had to clip itself instead. It clipped to `x=88`, which is where the
*vanilla* move panel ends; Gen1BattleUI draws a fourteen-tile panel that ends
at 112, and the twenty-four pixels between were a blue line lying across that
panel's PP row every time a move menu was open. Raising Gen1BattleUI's hook
priority did nothing, because priority was never what decided the order.

Inside Gen1BattleUI the bar and the panel are drawn by one function, bar
first, so the panel covers it the way it covers anything else beneath it — and
a panel that changes width takes the covering with it, which no clip could
have done.

- If you run **Gen1WildUI**, the bar is there and on by default, as it was
  here. Its row is `XP BAR` under `BATTLE MENUS`.
- If you run **this bundle alone**, the bar is gone. That is the cost of the
  move and it is a real one.
- `qol_exp_bar` is retired rather than reused. A key that means something new
  to a save that already has it set is worse than a key that is absent.
- The 3D-battle path is **not** carried over. It drew into another mod's
  canvas through a handshake with that mod's `snapHUDs`, and the handshake
  decided whether the path was taken at all; ported without it, the path would
  be taken whenever that mod was loaded, which is worse than not having it.
- The faint guard moved with the feature — the bar still stops when your
  Pokémon goes down and the engine clears the HUD from under it.

## 1.2.0

Follows [Gen1AutoSave](https://github.com/wild1walker/Gen1AutoSave) to **1.4.0**
(from 1.3.4). Everything else is already on its newest release.

It brings one new row, which appears under `AUTO SAVE` on its own — the bundle
reads each feature's schema at load, so an upstream that adds an option needs
no change here:

| Row | Ships |
|---|---|
| `HEAL CONFLICTS` | on |

No option key was renamed or removed, and `enabled` — the row this bundle uses
as AUTO SAVE's master switch — is still honoured, so the switch keeps working.

### Fixed

- CI ran each vendored mod's own test suite from the wrong directory. Several
  reach their subject with a relative `loadfile("../main.lua")`, so they failed
  on a nil call wherever else they were invoked from, and the step reported
  warnings that said nothing about the mod. Gen1AutoSave's five all pass from
  their own directory.

## 1.1.0

### Fixed

- **The shared-EXP line no longer collides with the continue arrow.** Gen 1's
  battle box draws character *i* at `x = 8 + (i-1)*8`, so the eighteenth lands
  on x=144 — and the blinking arrow is drawn at exactly that column. The line
  read `amongst the party!`, which is eighteen characters, so the bang and the
  arrow rendered as one blob in the corner. It is now `amongst the party`.

- **`EASY HM USE` did nothing when switched on.** It — and `BATTLE XP BAR` and
  `CAUGHT MARKER` with it — had *two* switches: the bundle's, which only
  decided whether to install the feature, and the feature's own row, which
  decided whether it did anything. Turning the feature on installed something
  still set to OFF, and the row that actually mattered sat one screen down
  saying the opposite. Each feature's own row is now its master, the way
  `AREA BANNER`'s already was, so there is one switch — and a live one, with
  no relaunch.

### Changed

Four features that shipped off now ship on:

| Feature | Was | Now |
|---|---|---|
| `BATTLE XP BAR` | off | **on** |
| `CAUGHT MARKER` | off | **on** (`ON (Gen2)`) |
| `AREA BANNER` | off | **on**, 3 seconds |
| `EASY HM USE` | off | **on** |

These only affect a save that has never carried the setting; a stored choice,
including OFF, is untouched. All four switch live now — none of them are among
the rows the menu marks with an asterisk. `EASY HM USE`'s sub-rows are unchanged — `WATER
INTERACTION` already shipped `FISH FIRST`, `REPEL PROMPT` already shipped on,
and `CUT GRASS` inherits the master until it is set.

## 1.0.0

First release. The quality-of-life half of the Gen1Wild index, consolidated
into one installable mod.

### Features

Each of these is a row in `OPTION > GEN1WILD QOL`, switched on or off by
itself, with its own settings one press of A away:

| Feature | From | Ships |
|---|---|---|
| SPRINT | [Gen1Sprint](https://github.com/wild1walker/Gen1Sprint) | on |
| AUTO SAVE | [Gen1AutoSave](https://github.com/wild1walker/Gen1AutoSave) | on |
| AUTO CONTINUE | [Gen1AutoContinue](https://github.com/wild1walker/Gen1AutoContinue) | on |
| SOUND | [Gen1SoundQOL](https://github.com/wild1walker/Gen1SoundQOL) | on |
| FOLLOWERS | [Gen1Follower](https://github.com/wild1walker/Gen1Follower) | on |
| ALL 151 | [Gen151](https://github.com/wild1walker/Gen151) | on |
| EXP SHARE ‡ | originally [exp_share](https://github.com/ShaneMcGovernIE/exp_share) | on, GEN 5+ |
| BATTLE XP BAR ‡ | originally [Quality of Life](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol) | off |
| CAUGHT MARKER ‡ | Quality of Life | off |
| AREA BANNER ‡ | Quality of Life | off |
| EASY HM USE ‡ | Quality of Life | off |
| MENU LAYOUT † | [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) | on |
| MOD MANAGER † | [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu) | on |

‡ Maintained in this repository rather than tracked upstream: the source is
under `maintained/` and edits go straight in. The credit for what these do
still belongs to their original authors, named in the README.

† Carried by Gen1WildUI as well. With both bundles installed exactly one sets
it up, and its settings live under a shared id so they do not move when the
other bundle is the one that wins.

### Changed from upstream

- **EXP SHARE defaults to GEN 5+** rather than OFF. The fighters keep their
  full experience and every living bench Pokémon gains half a fighter's share.
  Seeded once, on a save that has never carried the setting; a stored choice is
  never overwritten.
- **AREA BANNER is redrawn.** Upstream's banner is the dialogue box's exact
  geometry — twenty tiles wide, four tall, flush with the bottom of the screen
  — with one line of text in it. It is now a plaque sized to the name it
  carries, anchored top-left by default, sliding in and out from its edge.
  `POSITION` moves it; `BOTTOM` restores upstream's placement.
- **The XP bar stops drawing when your Pokémon faints.** Upstream's keeps
  going: the engine clears the player HUD the moment the mon goes down, but
  the bar's guards (`safari`, `demo`, `showPlayerBack`, the intro slide) are
  all still false, so it carries on painting a blue stripe over the empty
  space the HUD was cleared from. The caught-indicator feature in the same mod
  already guards its own side with `not battle.enemy.fainted`; this is the
  matching predicate for the player side, applied without editing the vendored
  file.
- **The four Quality of Life features are separate rows** rather than one
  submenu, because wanting easy HM use is no reason to want an XP bar.
- **EXP SHARE is configured in the bundle menu**, not on the engine's own
  OPTIONS screen, so every feature in this bundle has one home.
