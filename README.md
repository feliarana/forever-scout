# forever-claude

Leveling toolkit for **World of Warcraft: Forever** (Classic+, level cap 60), for a troll hunter.

- `addon/FeliExport/` — in-game addon that saves a character snapshot (quests, location, gear, bags, talents, pet, buffs…) to SavedVariables on `/wow` or `/reload`. The game's `Interface/AddOns/FeliExport` is a symlink to this folder.
- `tools/` — Python scripts that cross the live snapshot with the installed QuestieDB.
- `guide/` — leveling guide.
- `CLAUDE.md` — rules for Claude when working in this repo.

Nothing from the game is copied here: tools always read the live files under `WOW_DIR`.

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python tools/build_q.py
```

Paths live in `config.py` and can be overridden with environment variables:

| Variable | Default |
|---|---|
| `WOW_DIR` | game folder holding `Interface/` and `WTF/` |
| `WOW_ACCOUNT` | auto-detected (the only, or most recently used, `WTF/Account/<name>`) |
| `WOW_CHAR` | highest-level character with a FeliExport snapshot |
| `FELIEXPORT_SNAPSHOT` | explicit snapshot file (overrides `WOW_CHAR`) |
| `WOW_AUCTION_REALM` | every Auctionator price database key |

## Characters

Characters are discovered from `WTF/Account/<account>/<realm>/<character>/`, so any number of
mains, alts and bank alts works. Install FeliExport and log in once with each character
(`/wow` or `/reload`) so it gets a snapshot.

- `analyze.py`, `guide.py` and `route_check.py` work on one character: `--char NAME`
  (folder name like `Caza-Peques` or just `Caza`), else `WOW_CHAR`, else the highest level.
  Quest filters use that character's race, class and faction.
- `inventory.py` always covers every character: bags, bank and mail from Syndicator, plus
  snapshot data. Items mailed to a bank alt show up under its mail until collected.
- Stat weights for the bag-upgrade check are per class in `config.STAT_WEIGHTS` (hunter only
  for now); `config.KEEP_ITEMS` is the list of items to never sell.

## Usage

```bash
.venv/bin/python tools/analyze.py                 # current zone + neighbors
.venv/bin/python tools/analyze.py 17 400          # specific zones
.venv/bin/python tools/analyze.py --char Banca    # another character
.venv/bin/python tools/guide.py 4841 5147
.venv/bin/python tools/route_check.py 17:52,30 17:45,57 400:46,51 400:38,27
.venv/bin/python tools/inventory.py            # what to vendor / auction / keep
```

Distances are in map units (percent of the zone map). Route check thresholds: ≤10 on route,
≤20 short detour, otherwise off route. XP uses QuestieDB's real Forever XP traces
(`~classic` marks a fallback to Classic values) with the Classic gray-quest penalty.

## Data sources (read live from the game folder)

- `QuestieDB/QuestieDB_Forever.toc` — quests, NPCs, objects, items, esMX translations.
- `QuestieDB/support/Forever/QuestXP/xpDB-traces.lua` — real quest XP on Forever.
- `QuestieDB/support/Forever/Zones/uiMapIdToAreaId.lua` — map ID → zone.
- `QuestieDB/support/Forever/DropTables/classicItemDrops.lua` — drop rates.
- `WTF/.../SavedVariables/FeliExport.lua` and `ShortestPathForever.lua` — snapshot and known flight paths.
- `WTF/<account>/SavedVariables/Syndicator.lua` — bags, bank and mail of every character.
- `WTF/<account>/SavedVariables/Auctionator.lua` — AH price database (run a full scan to refresh) and vendor price cache.
