# Changelog

## 1.11.0

**FOLLOWERS now covers the Pokémon standing on the maps**, following
[Gen1Follower](https://github.com/wild1walker/Gen1Follower) to 1.3.1.

Gen 1 draws every Pokémon that is part of a map from one of five shared
sheets — a "monster", a "bird", a "fairy", a "seel" and the one Snorlax. A
single monster is Mewtwo, a Meowth, a Machop and a Kangaskhan at once, and one
fairy is the Pokémon Fan Club's Pikachu as readily as it is a Clefairy. So the
follower walking behind you came from a set of 251 sheets while every Pokémon
you walked past did not, and the two never matched.

Fifty map objects across Red, Blue and Yellow now draw from the same sheet the
follower would use for that species, at the same Pokédex-proportional size:
the Fan Club's Pikachu and Seel, both sleeping Snorlax, Mewtwo, Articuno,
Zapdos and Moltres, Bill's fused form, Melanie's three, every Pokémon Center's
Chansey, and the rest. Each is picked by the map object's own name rather than
by its sprite id, so a Pidgey stays a Pidgey and a Pidgeot a Pidgeot.

Three are deliberately untouched: the monster, bird and fairy in the Copycat's
room are dolls and her joke is that they are, and the Power Plant's Voltorb and
Electrode wear the item-ball sprite because they are pretending to be item
balls. Bill is the one entry no game data settles — he only says he "got
combined with a #MON" — and he is drawn as a Kabuto by choice.

- A new row, `MAP POKEMON`, appears under FOLLOWERS in the bundle menu on its
  own; it is on by default and turning it off puts the cart's sprites back
  without a map reload. No existing option key moved, and no save key moved.
- FOLLOWERS' menu description says what the feature covers now.

Nothing else in the bundle changed: the other eight tracked mods are pinned
where 1.10.1 left them, and the four features maintained here are untouched.

## 1.10.1

**ALL 151 was switching itself off on every install.** The whole feature: no
substituted encounters, no version exclusives, no gift or fossil mons, no MEW
event -- and no LINK CABLE on the Celadon Dept. Store 4F shelf, which is the
symptom that got it noticed.

The cause was in this repository's build, not in Gen151. `tools/build.py`
dropped `build.lua` on the way in, along with the rest of what it reads as
repository furniture. `build.lua` is not furniture: Gen151 loads it at install
through `mod:read`, and gives up on the feature when it is not there --

```lua
if not (Rarity and Roll and Build and Placements and Hints) then return end
```

-- so every copy of the bundle ever built shipped a Gen151 that logged one
line and returned, while its options row still said ALL 151 was on. Standalone
[Gen151](https://github.com/wild1walker/Gen151) was never affected; it ships
its own files.

- `build.lua` and `bench.lua` are no longer excluded, in both bundles. A `.lua`
  file in a mod's root is mod code. A real build script in these repositories
  is Python under `tools/`, which the directory and suffix rules already drop.
- `modules/Gen151/` carries both files again, so ALL 151 installs and the BENCH
  option has something to switch on.
- `tools/check.py` grew the check that would have caught it: every Lua file a
  module names in its own code has to exist in `modules/`. It fails the build
  rather than leaving a feature to log its way out.

Nothing else changed. No option moved, no save key moved, and no other feature
is touched.

## 1.10.0

**STATUS COLOURS is removed**, at the author's request -- every part of it.

- The feature and its source are gone: no overworld tint, no colour on a
  POKéMON's picture anywhere, and thirteen rows fewer in this bundle's menu.
- `mod.exports.statusColours` is gone with it. It existed only to serve this,
  and nothing else read it.
- `mod.publish` is gone from the bundle runtime for the same reason. It was
  added so this feature could hand its table to the party and the box, it never
  had another caller, and a mechanism with no user is the one that quietly
  stops working.

Settings a player saved under `STATUS COLOURS` stay in the save as dead keys,
the way any removed mod's do. Nothing reads them and nothing writes them.

[Gen1Party](https://github.com/wild1walker/Gen1Party) 1.7.0 and
[Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) 1.5.0 drop their
half in the same pass; both are byte-identical to the releases before the tint
went in.

Nothing else in this bundle changed. Every other feature is untouched, and the
runtime is back to exactly what it was before this feature existed.

## 1.9.0

**The world tint is a colour filter over the finished frame now, which is what
it should have been from the start.**

Three mechanisms have been tried and the first two were invisible in the game
while being correct against the seam they used:

1. **SGB palette zones.** A map drawn from a full-colour GBC atlas has no
   four-colour palette to shift -- `sgbWorldZones` returns an empty list
   outright under RED++ -- so there was nothing to tint.
2. **A rectangle inside the overworld's own draw.** The overworld draws into a
   canvas of its own and the multiply did not survive the composite.

Both went *through* the rendering. This goes **over** it. `render.hud` is the
engine's own hook for "draw over the completed render pipeline"
(`src/core/Game.lua:699`): it runs after every pass, in screen space, and is
handed the playfield's exact geometry. So there is no canvas to guess at, no
blend mode to match, and no colour mode that can opt out of it -- a coloured
lens over the picture rather than a change to how the picture is made.

It covers the playfield only. The margins and the on-screen pad are untouched,
because the viewport says where the game actually is.

Unchanged: it is still off in battles and under a full-screen menu, still
swallows the poison tick's black flash and deepens instead, and still tops out
near the 0.45 alpha the vanilla flash used, so the strongest it gets is about
as strong as the thing it replaced.

### Still true, and still the one gap

A POKéMON's own picture on the **stats page** tints through the picture's
palette, which a full-colour sprite pack sits out by design. Painting a
rectangle there was tried in 1.8.1 and reverted: the zone covers the picture
*well*, so it turned the white square behind the POKéMON into a lavender block.
The party list and the box do not have this problem -- they tint the icon at
draw time, through
[Gen1Party](https://github.com/wild1walker/Gen1Party) 1.6.0 and
[Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) 1.4.0, which need
**Gen1WildUI 1.8.1 or later** installed.

## 1.8.2

Two fixes, and the second undoes something 1.8.1 got wrong.

### The world tint is alpha-blended, and now actually appears

It was multiplied. That worked on an opaque menu and did **nothing** on the map
-- the overworld draws into a canvas of its own, and a multiply against it does
not survive the composite the way a straight alpha blend does. The screenshots
showed exactly that split: the stats page changed, the overworld did not.

The thing being replaced was never multiplied either. The engine's own poison
flash is `setColor(0, 0, 0, 0.45)` and a rectangle in the **default** blend
mode, which is the one blend proven to land where this paints. So this is that
rectangle in a colour, held instead of pulsed, with its alpha scaled off the
tint depth and topping out near the same 0.45 -- the strongest it ever gets is
about as strong as the thing it took away, in colour, and never a blackout.

### The stats page goes back to shifting the picture's palette

1.8.1 painted a rectangle over the picture and that was wrong: the zone covers
the picture **well**, background included, so the white square behind the
POKéMON became a lavender block. It shifts the four colours the picture is
drawn through again -- the well's background is colour 0 of the species
palette, an off-white, so it stays an off-white.

The cost of that is honest and unchanged: a picture drawn from full-colour art
sits the shade-remap pass out by design, so this tints nothing for such a pack.
A lavender box for everyone is worse than no tint for some. Tinting the sprite
and not its background needs a seam to set a colour around the sprite's own
draw, and the engine does not offer one on that screen.

## 1.8.1

The stats page picture is **painted** rather than palette-shifted, which closes
the last surface that only tinted for four-colour art. Every place STATUS
COLOURS colours something now works the same way, and works whatever your
`COLORS` mode and whatever art you have installed.

The rect is not hard-coded. `SummaryMenu:sgbPalettes` already answers with an
HP-bar palette over the whole screen plus one zone over the picture, so the
picture's rect is the one zone that is *not* the whole screen. Reading it back
from the screen itself means the engine can move the picture without this
having an opinion about where it went -- and it is also why the HP bar is left
alone: that is the whole-screen entry, and it is skipped.

The engine's own draw still runs first and in full; this only paints over the
rect afterwards.

## 1.8.0

Publishes the condition as a **draw colour**, so the party list and the box can
tint a POKéMON whose art is full-colour.

The tint on a POKéMON's picture rode a palette zone, and a palette zone reaches
only art that goes through the shade-remap pass. A full-colour icon or sprite
pack sits that pass out **by design** -- Gen1Party marks its rect trueColor
precisely so the pass does not repaint it off its red channel -- so the tint
found nothing to colour for anyone running one. Same shape of mistake as the
world tint in 1.7.2, one layer up.

`mod.exports.statusColours.drawColour(mon)` answers with the colour to set
before drawing, or nil for "draw it as it is". Multiplied by the art, so white
is untouched and the colour shifts the hue while keeping the art's own light and
dark. [Gen1Party](https://github.com/wild1walker/Gen1Party) 1.6.0 and
[Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) 1.4.0 use it.

It lives here rather than in each screen so the three surfaces keep agreeing --
and so the arithmetic is under test in one place instead of copied twice.

The stats page still tints through its palette zone. That screen's picture is
the engine's own draw and there is no seam to set a colour around just the
picture, so under a full-colour sprite pack it stays untinted.

## 1.7.2

**The world tint now works in every colour mode.** 1.7.0 and 1.7.1 both built it
on SGB palette zones, and that could never work for anyone running full-colour
art: `OverworldState:sgbWorldZones` returns an **empty list** outright when
`PaletteFX.usesGbcPack()` and the map has a `gbcAtlas`, so under RED++ there was
no four-colour palette to shift and the tint had nothing to bite on. The screen
stayed exactly as it was.

The thing being replaced was never a palette change either. The engine's own
poison flash is a rectangle drawn over the world:

```lua
love.graphics.setColor(0, 0, 0, 0.45)
love.graphics.rectangle("fill", 0, 0, 160, 144)
```

So this is that rectangle in a colour, held instead of pulsed. It is painted on
the end of the overworld's own draw, which puts it over the map and **under**
everything drawn after it -- text boxes, the START menu, every full-screen menu
-- because those are later states in the stack. That is why the menu keeps its
own colour without a single check for one.

It multiplies rather than washing: the rectangle's colour is lerped from white
toward the tint, so bright grass stays bright, dark tiles stay dark, and the
hue shifts across all of it. A tint of zero multiplies by white, which is the
untouched frame.

### Why it shipped twice

Every test drove the feature file directly, so a feature that installs
correctly and reaches the player doing nothing looked green. There is now a
test that starts where the game does -- the real `features.lua`, the real
`runtime/bundle.lua` -- and asserts a poisoned party ends with a rectangle
painted over the world. Both of the previous mechanisms fail it.

### Still palette-based, and worth knowing

The tint on a POKéMON's own picture -- party list, box, stats page -- still
rides the per-POKéMON palette zone those screens build. A **full-colour icon or
sprite pack sits that pass out by design**, so if your art is full-colour those
will not tint either. Same root cause, same fix available; say the word.

## 1.7.1

**The tint was on the wrong surface.** 1.7.0 turned the START menu purple and
left the map exactly as it was -- the opposite of the feature. Fixed.

The engine keeps two zone lists and they are not interchangeable. The
`render.zones` hook hands a mod the **UI pass**: 160x144 space, the menus and
text boxes. The map is drawn through a **different** list, in world-canvas
pixels, which the engine asks the overworld for a few lines after that hook
runs:

```lua
if worldDrawn and self.overworld.sgbWorldZones then
  worldZones = self.overworld:sgbWorldZones()
end
```

So tinting what the hook handed over could only ever colour the menu. The map
is `sgbWorldZones`, and that is what the feature wraps now. The hook is kept
because it runs once a frame with the game in hand, immediately before that
call, which makes it the right place to work out what colour the frame wants
and to swallow the poison tick -- but the list it hands over goes back
untouched. A tinted menu is not a subtler flash; it is a menu that has gone the
wrong colour.

The tests agreed with the bug, which is why it shipped: they asserted the hook's
list came back tinted, which was exactly the wrong thing to want. They now
assert both halves -- the UI list comes back *identical*, and the map's list
carries the colour -- so this cannot come back quietly.

Nothing else moved. The party list, the box and the stats page were always
right: those screens are drawn in the UI pass, which is the list their own
zones belong to.

### Known limits of the world tint

- A map whose own zone list is empty or absent gets no tint. That happens under
  the GBC pack with a full-colour atlas, where there is no four-colour palette
  to move, and on a map with no palette at all. Nothing is invented in
  world-canvas space to cover it.

## 1.7.0

STATUS COLOURS reaches the POKéMON themselves, and the world now reacts to
everything that takes HP rather than to poison alone.

- **`WORLD REACTS TO` defaults to `DAMAGING`** -- poison, bad poison and burn.
  Gen 1 runs the three of them through one routine,
  `HandlePoisonBurnLeechSeed`, and taking HP is the honest line to draw: a
  colour that means "this is costing you" is worth wearing, and one that means
  "this will be awkward in your next battle" is not. Only poison ticks in the
  field, so only poison deepens; a burn shows its colour while you walk and
  does its damage in battle. `POISON` narrows it back to the old default and
  `ANY STATUS` opens it to all five.
- **A POKéMON's own picture wears its condition** on the stats page -- the one
  screen that shows the full picture with the status printed beside it. Only
  the picture is tinted, not the page: the screen's full-screen HP-bar palette
  is left alone, or the bar would stop meaning what it means.
- **The party list and the box** tint too, through
  [Gen1Party](https://github.com/wild1walker/Gen1Party) 1.5.0 and
  [Gen1BillsBox](https://github.com/wild1walker/Gen1BillsBox) 1.3.0, which ask
  this mod rather than carrying their own copy of the colours. The tint rides
  the per-POKéMON zone each already builds, over the species colours, so a
  poisoned CHARMANDER still reads as a CHARMANDER.

### The Pokédex is not in that list, on purpose

A dex entry is a page about a *species*. Gen1Dex never touches a POKéMON
instance and never reads the party, so there is no condition there to show:
RATTATA is not poisoned, your RATTATA is. Tinting it would have meant inventing
a status for a catalogue.

### Fixed

- **`LOW HP` could never have fired in a real game.** It read `mon.maxHP`;
  this engine keeps maximum HP in `mon.stats.hp` (`src/pokemon/Pokemon.lua`).
  The stub POKéMON in 1.6.0's tests carried the field the code was looking for,
  so the tests agreed with the bug. They now use the real shape, and the other
  two spellings are still accepted for a battler or a serialized POKéMON.

### For mod authors

A bundled feature can now publish an API on the bundle's own exports with
`mod.publish(name, value)`, which is how the party and the box reach this one:

```lua
local qol = mod.find("gen1_wild_qol")
local api = qol and qol.exports and qol.exports.statusColours
```

Two features cannot publish the same name -- the second is refused rather than
silently winning, which would make the answer depend on feature order.

## 1.6.0

New feature: **STATUS COLOURS**, on by default.

**The overworld stops flashing black when a POKéMON is poisoned.** It wears
purple instead, for as long as the poison lasts, and the tick that takes the HP
deepens the colour for a moment rather than blacking the screen out. Gen 1's
flash fires twice every fourth step, for as long as you stay poisoned, and what
it communicates -- "someone lost a point" -- fits in a colour. The state is now
visible the whole time instead of announced twice a second, which is gentler to
look at and strictly more information.

It is a palette change, not an overlay. The feature answers `render.zones`, the
hook the engine offers for "custom colorization", so the four colours the frame
is blitted through are what move -- the same thing a Super Game Boy palette
swap does. Nothing is layered over the picture and nothing is dimmed: the
screen keeps its full range of light and dark and simply changes hue, so text
over the map stays exactly as readable as it was.

- **`WORLD REACTS TO`** is `POISON` by default, meaning poison and bad poison.
  Poison is the condition that is doing something to you while you walk, which
  is why it is the one the game already interrupts for. `ANY STATUS` opens it
  to the rest -- worth knowing that paralysis lasts until a town, so that
  setting will paint the world yellow for a long time to say something no step
  changes.
- **`DEPTH`** is `SUBTLE`, `NORMAL` or `STRONG`. Even `STRONG` at the peak of a
  tick stays well short of opaque; going all the way would be the blackout
  again in a different colour.
- **`REPLACE FLASH`** off keeps the resting tint and hands the vanilla flash
  back, for anyone who wants the colour and still wants to be told.
- **A row for each state**, all on: `POISON`, `BAD POISON` (deeper purple --
  Gen 1 keeps Toxic as poison plus a counter, so the colour is what tells them
  apart), `BURN`, `FREEZE`, `PARALYSIS`, `SLEEP`, `FAINTED GREY` and `LOW HP`.
  A party carrying several wears the one that matters most: fainted outranks
  poison, poison outranks the rest, and low HP ranks under every status because
  a poisoned mon at low HP is poisoned first.
- `LOW HP` uses a fifth of max HP, the same threshold as the engine's own
  low-health alarm, so the colour and the sound agree.

### Not in this release

The tint is the **world** only. Colouring a POKéMON's own picture in the dex,
party and box -- purple when poisoned, grey when fainted -- needs each of those
screens to say where it drew that POKéMON, and the three that draw them here
are `Gen1Dex`, `Gen1Party` and `Gen1BillsBox` in the other bundle. The engine's
two sprite hooks only swap which file is loaded; they cannot tint one. So that
half is a change to those three mods and it is next, not forgotten. This
release publishes what the world is wearing through `mod.exports.statusColours`
so they have one answer to read rather than three copies of this table.

## 1.5.0

**This bundle no longer puts a row on the game's OPTION screen.** Its settings
live where a mod's settings live: `MODS` > `Gen1WildQOL` > `OPTIONS`, which lands
on the same nested screens it always did -- every feature, each with its own
page. Nothing was removed from the menu and nothing moved inside it; only the
way in changed, and there is now one of them instead of two.

The OPTION screen is the game's own, and a bundle of a dozen mods was spending
a line of it on something the mod manager already lists.

Also follows both shared menu features:

- **MENU LAYOUT** ->
  [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) 0.2.8. Its
  `MENU MANAGER` row now sits at the **top** of the OPTION screen, above
  `SPEED`.
- **MOD MANAGER** -> [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu)
  0.9.0, which is what makes that possible. Since the engine grouped the OPTION
  screen it lays out the rows its own order names first and appends everything
  else behind them, so no mod could reach the front however it anchored itself.
  A row may now ask by carrying `top`, and rows that ask are lifted. It
  reorders what is drawn, never the flat list the hook built, and it runs
  whatever `STYLE` and `HIDE CANCEL` are set to.

The OPTION screen now reads `MENU MANAGER`, `SPEED`, `VIDEO`, `GRAPHICS`,
`AUDIO`, `PERFORMANCE`, `RULESET`, `BATTLE OPTIONS`, `EXTRAS`, `MODS`, then the
platform rows.

## 1.4.3

Fixes the OPTION screen. Both of the shared menu features moved.

- **MOD MANAGER** -> [Gen1ModMenu](https://github.com/wild1walker/Gen1ModMenu)
  0.8.2. **The screen was showing the wrong rows.** With `STYLE = MODERN` and
  `HIDE CANCEL` on -- both defaults, so this was everyone -- the arrow sat on
  one row while the press edited another, and `MODS` looked like it had been
  taken off the screen entirely. The engine grouped that screen and now keeps
  two lists: the flat one the `ui.options.rows` hook builds, and the one on
  screen, where a group's members collapse into a single opener. The cursor
  counts the second; this mod's `CANCEL`-hiding decoration drew the first, so
  the two disagreed from the top row down. `MODS` is ninth in the view and
  thirtieth in the flat list, which is where it was being drawn. Both halves
  read the view now.
- **MENU LAYOUT** ->
  [Gen1MenuManager](https://github.com/wild1walker/Gen1MenuManager) 0.2.7. Its
  `MENU MANAGER` row is anchored to `MODS` rather than appended, so it sits
  with the other mod rows instead of last of all, behind `CONTROLS`, `DATE
  FORMAT` and the platform rows. Grouping runs after the hook and appends
  whatever the engine's own order does not name, which is what stranded it.

The top level now reads `SPEED`, `VIDEO`, `GRAPHICS`, `AUDIO`, `PERFORMANCE`,
`RULESET`, `BATTLE OPTIONS`, `EXTRAS`, `MODS`, and then the mod rows together:
`Gen1WildUI`, `Gen1WildQOL`, `MENU MANAGER`.

## 1.4.2

Adds the `LICENSE` this repository never had. Every standalone mod in the suite
ships one and both bundles did not, while the index entry claimed MIT on their
behalf -- so the claim is now in the repository making it, and in the zip.

It is scoped rather than blanket: MIT over the bundling -- the loader, the
feature registry, the runtime, the adapters, the tools, the suites -- and no
claim at all over the mods carried under `modules/`, each of which keeps its
own licence file where the build put it. `EXP SHARE` and the three `QUALITY OF
LIFE` features are maintained here and neither original states any terms, so
the file says that plainly and leaves them to their authors rather than
assigning any.

No code changed.

## 1.4.1

Follows two of its mods; everything else here is already on its newest release.
No option key was added, renamed or removed, so nothing in the menu moves.

- **FOLLOWERS** → [Gen1Follower](https://github.com/wild1walker/Gen1Follower)
  1.2.1. Followers now darken with the rest of an unlit cave instead of walking
  around Rock Tunnel in full colour while everything else is a silhouette.
- **REMEMBER MOVES** → [Gen1Remember](https://github.com/wild1walker/Gen1Remember)
  1.0.1. The popup drops its heading: the row you pressed already said REMEMBER
  and the box opens over it, so the title repeated the word back at you.

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
