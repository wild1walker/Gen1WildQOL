# Changelog

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
