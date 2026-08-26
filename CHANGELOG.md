# Changelog

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
| EXP SHARE | [exp_share](https://github.com/ShaneMcGovernIE/exp_share) | on, GEN 5+ |
| BATTLE XP BAR | [Quality of Life](https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol) | off |
| CAUGHT MARKER | Quality of Life | off |
| AREA BANNER | Quality of Life | off |
| EASY HM USE | Quality of Life | off |
| MENU LAYOUT † | [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) | on |
| MOD MANAGER † | [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu) | on |

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
- **The four Quality of Life features are separate rows** rather than one
  submenu, because wanting easy HM use is no reason to want an XP bar.
- **EXP SHARE is configured in the bundle menu**, not on the engine's own
  OPTIONS screen, so every feature in this bundle has one home.
