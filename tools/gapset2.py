#!/usr/bin/env python3
"""Derive the Gen 2 gap set from ground truth, the way gapset.py does for Gen 1.

    python3 tools/gapset2.py --pokegold <dir> --pokecrystal <dir> [--json out]

Nothing here is hand-written content.  Every fact is parsed out of the pret
disassemblies -- the same source the engine's own Gen 2 extractor reads through
a ROM -- so the answer to "what can this cartridge not give you twice?" is the
cartridge's answer and not a recollection of it.

------- what counts as renewable

SPEC 0's bar, unchanged from Gen 1: RENEWABLE, not obtainable.  A species you
can go and find again tomorrow counts; one the game hands you once does not.
So the tables read here are the ones a player can re-roll --

    grass / water        johto_grass, kanto_grass, johto_water, kanto_water
    swarms               swarm_grass, swarm_water
    fishing              fish.asm, all three rods, including the time-of-day
                         sub-rows the TimeFishGroups indirection carries
    headbutt             treemons.asm, but only the sets treemon_maps.asm
                         actually points a map at
    rock smash           the same indirection, rocks half
    bug contest          bug_contest_mons.asm

and the ones deliberately NOT read are statics, gift Pokemon, NPC trades, the
Game Corner, eggs and the roaming beasts.  Those are all "obtainable" and none
of them is renewable, which is exactly the distinction the mod exists for.

------- the evolution closure

A species is also renewable if something renewable evolves into it, so the set
is closed over evos_attacks.asm -- EXCEPT across EVOLVE_TRADE.  A trade
evolution is precisely the thing one save cannot reach, which is why the Gen 1
mod ships a Link Cable item rather than a spawn, and why Gen 2's six
trade-with-a-held-item lines land in the gap set here.

EVOLVE_ITEM is NOT treated as a break: Gen 2 sells Fire, Water, Thunder and
Leaf Stones in Goldenrod and Celadon, and the rest are findable more than once.

------- versions

Gold and Silver are one disassembly under IF DEF(_GOLD) / ELIF DEF(_SILVER),
so both are resolved from pokegold with the matching define.  Crystal is its
own tree.  The three answers differ and are reported separately; the mod itself
never consults this file at runtime -- it asks the live tables the same
question -- so this is the research, not the mechanism.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

VERSIONS = {
    "gold": ("pokegold", {"_GOLD"}),
    "silver": ("pokegold", {"_SILVER"}),
    "crystal": ("pokecrystal", {"_CRYSTAL"}),
}

# The wild tables, by the bar above.  Anything not in here is not renewable.
WILD_FILES = [
    "johto_grass.asm", "kanto_grass.asm",
    "johto_water.asm", "kanto_water.asm",
    "swarm_grass.asm", "swarm_water.asm",
    "fish.asm", "bug_contest_mons.asm",
]


# ------------------------------------------------------- reading the asm

def read_asm(path: Path, defines: set[str]) -> list[str]:
    """Resolve IF DEF / ELIF DEF / ELSE / ENDC the way rgbasm would.

    `stack` holds one entry per open conditional: (taken_here, taken_ever).
    A line survives only when every open conditional is taken.
    """
    out: list[str] = []
    stack: list[list[bool]] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split(";", 1)[0].rstrip()
        s = line.strip()
        m = re.match(r"^(IF|ELIF)\s+DEF\(\s*([A-Z0-9_]+)\s*\)", s, re.I)
        if m:
            hit = m.group(2) in defines
            if m.group(1).upper() == "IF":
                stack.append([hit, hit])
            elif stack:
                frame = stack[-1]
                frame[0] = hit and not frame[1]
                frame[1] = frame[1] or frame[0]
            continue
        if re.match(r"^ELSE\b", s, re.I):
            if stack:
                frame = stack[-1]
                frame[0] = not frame[1]
                frame[1] = True
            continue
        if re.match(r"^ENDC\b", s, re.I):
            if stack:
                stack.pop()
            continue
        if all(frame[0] for frame in stack):
            out.append(line)
    return out


def species_names(root: Path) -> list[str]:
    """The 251, in index order, out of the constants file."""
    text = (root / "constants" / "pokemon_constants.asm").read_text()
    names: list[str] = []
    for line in text.splitlines():
        m = re.match(r"\s*const\s+([A-Z0-9_]+)", line.split(";", 1)[0])
        if m and m.group(1) not in ("EGG", "NUM_POKEMON"):
            names.append(m.group(1))
        if len(names) >= 251:
            break
    return names


# --------------------------------------------------- what the tables hold

def wild_species(lines: list[str], valid: set[str]) -> set[str]:
    """Every species id named by a `db` row in a wild table.

    Deliberately shape-agnostic.  The five table formats put the species in
    three different columns -- `db level, SPECIES` for grass and water,
    `db chance, SPECIES, level` for fishing, headbutt and the contest -- and
    every one of them is a `db` row whose only symbol is the species.  So
    rather than five parsers that can each be wrong, this takes any capitalised
    token on a `db` line that is a real species name, which is exactly the set
    wanted and cannot pick up a level or a percentage.
    """
    found: set[str] = set()
    for line in lines:
        s = line.strip()
        if not s.startswith("db "):
            continue
        for token in re.findall(r"[A-Z][A-Z0-9_]+", s):
            if token in valid:
                found.add(token)
    return found


def reachable_treemon_sets(root: Path, defines: set[str]) -> set[str]:
    """The headbutt/rock-smash sets some map actually points at.

    treemon_maps.asm is the indirection: a map names a TREEMON_SET_*, and a set
    nothing names is dead data.  TreeMonSet_Unused is the case that matters --
    it shares a label with None and City, so reading treemons.asm alone would
    credit the player with Pokemon no tree in the game can produce.
    """
    path = root / "data" / "wild" / "treemon_maps.asm"
    sets = set()
    for line in read_asm(path, defines):
        for token in re.findall(r"TREEMON_SET_[A-Z0-9_]+", line):
            sets.add(token.replace("TREEMON_SET_", ""))
    return sets


def treemon_species(root: Path, defines: set[str], valid: set[str],
                    live: set[str]) -> set[str]:
    """Headbutt and Rock Smash, restricted to the live sets.

    The file is a run of `TreeMonSet_<Name>:` labels, each followed by its
    common and rare rows, so the labels above a row decide whether the row
    counts.  Several labels stack on one body (None/Unused/City share theirs),
    and a body counts if ANY label in the run naming it is live.  The first
    data row closes the run; the next label after data starts a fresh one,
    which is what keeps a live set from crediting the body below it.
    """
    path = root / "data" / "wild" / "treemons.asm"
    found: set[str] = set()
    run: set[str] = set()
    in_body = False
    for line in read_asm(path, defines):
        s = line.strip()
        label = re.match(r"^TreeMonSet_([A-Za-z0-9_]+):", s)
        if label:
            if in_body:
                run = set()
                in_body = False
            run.add(label.group(1).upper())
            continue
        if not s.startswith("db "):
            continue
        in_body = True
        if any(name in live for name in run):
            for token in re.findall(r"[A-Z][A-Z0-9_]+", s):
                if token in valid:
                    found.add(token)
    return found


def evolutions(root: Path, valid: set[str]) -> dict[str, list[tuple[str, str]]]:
    """species -> [(method, into)], straight out of evos_attacks.asm."""
    path = root / "data" / "pokemon" / "evos_attacks.asm"
    evos: dict[str, list[tuple[str, str]]] = {}
    current = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split(";", 1)[0]
        s = line.strip()
        m = re.match(r"^([A-Za-z0-9_]+)EvosAttacks:", s)
        if m:
            name = re.sub(r"(?<!^)(?=[A-Z])", "_", m.group(1)).upper()
            current = name if name in valid else _fuzzy(m.group(1), valid)
            evos.setdefault(current, []) if current else None
            continue
        if current and s.startswith("db EVOLVE_"):
            parts = [p.strip() for p in s[3:].split(",")]
            method = parts[0].replace("EVOLVE_", "")
            into = parts[-1]
            if into in valid:
                evos.setdefault(current, []).append((method, into))
    return evos


def _fuzzy(label: str, valid: set[str]) -> str | None:
    """Match a CamelCase evo label to a species constant.

    Nidoran, Farfetch'd, Mr. Mime, Ho-Oh and Porygon2 do not survive a
    mechanical camel-to-snake split, so the fallback is to compare on letters
    and digits alone -- which is unambiguous across the 251.
    """
    key = re.sub(r"[^A-Z0-9]", "", label.upper())
    for name in valid:
        if re.sub(r"[^A-Z0-9]", "", name) == key:
            return name
    return None


# ---------------------------------------------------------------- breeding

def egg_groups(root: Path, valid: set[str]) -> dict[str, set[str]]:
    """species -> its two egg groups, out of the per-species base stats."""
    out: dict[str, set[str]] = {}
    for path in sorted((root / "data" / "pokemon" / "base_stats").glob("*.asm")):
        text = path.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"dn\s+(EGG_[A-Z0-9_]+)\s*,\s*(EGG_[A-Z0-9_]+)", text)
        if not m:
            continue
        name = _fuzzy(path.stem, valid)
        if name:
            out[name] = {m.group(1), m.group(2)}
    return out


def breedable(species: str, groups: dict[str, set[str]]) -> bool:
    """Whether the Day-Care will ever produce an egg from this species.

    EGG_NONE on both halves is the cartridge's way of saying no: the
    legendaries, Unown and the babies themselves.  Ditto is a parent but never
    the mother, so it cannot be the source of a baby on its own -- it always
    breeds as the OTHER parent's species, which the caller already has.
    """
    own = groups.get(species) or set()
    return bool(own) and own != {"EGG_NONE"} and own != {"EGG_DITTO"}


# ------------------------------------------------------------- the closure

def close_over_evolution(have: set[str],
                         evos: dict[str, list[tuple[str, str]]],
                         groups: dict[str, set[str]]) -> set[str]:
    """Grow the set both ways: evolution up, the Day-Care down.

    UP is Gen 1's rule -- every evolution except EVOLVE_TRADE, because a trade
    evolution is the one thing a single save cannot reach.

    DOWN is new here and is not a nicety: Gen 2 has breeding, and the engine
    implements it (src/core/gen2/Breeding.lua), so a renewable Pikachu makes
    Pichu renewable and the six babies whose adults are in the grass need no
    placement at all.  Leaving this out would have invented work and, worse,
    put spawns in Johto for Pokemon the Day-Care already hands out.

    The step is barred where the cartridge bars it: a parent in no egg group
    lays nothing, so it cannot walk a legendary's pre-evolution into the set,
    and TRADE is skipped in this direction too -- breeding down to a baby whose
    only way back up is a trade would claim a line the save still cannot close.
    """
    have = set(have)
    changed = True
    while changed:
        changed = False
        for species, rows in evos.items():
            for method, into in rows:
                if method == "TRADE":
                    continue
                if species in have and into not in have:
                    have.add(into)
                    changed = True
                elif into in have and species not in have \
                        and breedable(into, groups):
                    have.add(species)
                    changed = True
    return have


def renewable(root: Path, defines: set[str], valid: set[str]) -> set[str]:
    wild = root / "data" / "wild"
    have: set[str] = set()
    for name in WILD_FILES:
        path = wild / name
        if path.is_file():
            have |= wild_species(read_asm(path, defines), valid)
    live = reachable_treemon_sets(root, defines)
    have |= treemon_species(root, defines, valid, live)
    return close_over_evolution(have, evolutions(root, valid),
                                egg_groups(root, valid))


# ------------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pokegold", required=True, type=Path)
    ap.add_argument("--pokecrystal", required=True, type=Path)
    ap.add_argument("--json", type=Path)
    args = ap.parse_args()

    roots = {"pokegold": args.pokegold, "pokecrystal": args.pokecrystal}
    for name, path in roots.items():
        if not (path / "data" / "wild").is_dir():
            return int(bool(sys.stderr.write(
                "%s does not look like %s (no data/wild)\n" % (path, name))))

    order = species_names(args.pokecrystal)
    valid = set(order)
    if len(order) != 251:
        sys.stderr.write("read %d species, expected 251\n" % len(order))
        return 1

    report = {"species": order, "versions": {}}
    for version, (tree, defines) in VERSIONS.items():
        have = renewable(roots[tree], defines, valid)
        gap = [name for name in order if name not in have]
        report["versions"][version] = {"renewable": len(have), "gap": gap}

    every = set(order)
    for entry in report["versions"].values():
        every &= set(entry["gap"])
    report["gap_in_every_version"] = [n for n in order if n in every]
    union: set[str] = set()
    for entry in report["versions"].values():
        union |= set(entry["gap"])
    report["gap_in_any_version"] = [n for n in order if n in union]

    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n")

    for version in ("gold", "silver", "crystal"):
        entry = report["versions"][version]
        print("%-8s %3d renewable, %3d missing"
              % (version, entry["renewable"], len(entry["gap"])))
    print("\nmissing everywhere (%d):" % len(report["gap_in_every_version"]))
    print("  " + " ".join(report["gap_in_every_version"]))
    for version in ("gold", "silver", "crystal"):
        only = [n for n in report["versions"][version]["gap"]
                if n not in report["gap_in_every_version"]]
        print("\nmissing on %s only (%d):" % (version, len(only)))
        print("  " + " ".join(only))
    return 0


if __name__ == "__main__":
    sys.exit(main())
