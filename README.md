# forever-claude

Leveling toolkit for **World of Warcraft: Forever** (Classic+, level cap 60), for a troll hunter.

- `addon/ForeverScout/` — in-game addon: character snapshot, loot advisor, tooltip score, upkeep alerts and NPC arrow
  ([addon README](addon/ForeverScout/README.md)). The game's `Interface/AddOns/ForeverScout` is a
  symlink to this folder.
- `tools/` — Python scripts that cross the live snapshot with the installed QuestieDB.
- `guide/` — leveling guide for the troll hunter.
- `AGENTS.md` — guide for any AI assistant helping a player set up and use the toolkit.
- `CLAUDE.md` — the author's personal rules for Claude.

## Features

### In game (ForeverScout)

- **Snapshot** — quests, location, gear, bags, talents, spellbook, action bars, pet,
  professions, buffs, hearthstone, durability, party and online friends, refreshed every 20
  seconds and written to disk on `/reload`. `/wow [question]` also opens a copy box with a
  one-line summary to paste into a chat.
- **Online friends** — friend list, Battle.net friends playing WoW, guild and community
  members, with level and zone; guild name and rank, communities; party members with map
  position.
- **Session history** — XP total, level-ups, deaths (with place), dungeon runs with XP gained,
  known flight paths and recipes.
- **Window capture** — last quest reward window, trainer and vendor opened, with stats and
  costs.
- **Loot advisor** — NEED / GREED verdict on every loot roll, or with
  `/wow <item link>`, using the hunter stat weights against the equipped item.
- **Tooltip score** — every gear tooltip shows the weighted score difference against what is
  equipped (green upgrade, red downgrade), or why the item is not for a hunter.
- **Addon overlap check** — `/wow addons` lists loaded addons that do the same job, to trim
  long addon lists.
- **Upkeep alerts** — on-screen warning and sound for low ammo (with a hint to equip another
  stack), dead / unhappy / content / missing pet, nearly full bags and low durability.
  `/wow alerts on|off`.
- **NPC arrow** — `/donde <npc name | id | party member>` puts a TomTom arrow on the nearest
  spawn (Questie database) and prints the distance in yards and meters; with no argument it
  uses the NPC target, and it follows party members live. `/donde off` clears it.

### Offline tools

| Script | What it gives |
|---|---|
| `analyze.py` | Character summary (XP, rested XP, location, hearthstone, gold, bags, durability, pet, unspent talent points, PvP flag, party with distance, online friends, deaths at this level, flight paths), gear and consumables (ranged weapon, ammo, food, bag upgrades by stat weights), quests ready to turn in with NPC and location, quests in progress with objectives, quests unlocked by turning in, and quests available in the current and neighboring zones |
| `guide.py` | Per quest: start and turn-in NPCs, quest text, objectives with mob levels, elite flags and spawn clusters |
| `route_check.py` | Distance from every logged quest's objectives and turn-in to a planned route (on route / short detour / off route) and real XP at the current level |
| `inventory.py` | Vendor / auction / use / keep / turn-in for every character's bags, bank and mail, with Auctionator prices |
| `build_q.py` | Builds the `data/Q.pkl` cache from QuestieDB plus real Forever quest XP (the other tools rebuild it when stale) |

Nothing from the game is copied here: tools always read the live files under `WOW_DIR`.

## Install

### 1. The addon (any class)

1. Get the repo (clone it, or *Code → Download ZIP* on GitHub and unzip it).
2. Copy the `addon/ForeverScout` folder into the game's `_forever_/Interface/AddOns/`, so the
   game has `Interface/AddOns/ForeverScout/ForeverScout.toc`.
   - To pick up updates automatically, link it instead of copying:
     - Windows (Command Prompt as admin):
       `mklink /D "C:\...\_forever_\Interface\AddOns\ForeverScout" "C:\...\forever-claude\addon\ForeverScout"`
     - Linux / macOS: `ln -s /path/to/forever-claude/addon/ForeverScout /path/to/_forever_/Interface/AddOns/ForeverScout`
3. Optional, recommended: install **Questie** (Forever version, with QuestieDB) and **TomTom**.
   `/donde` needs both.
4. In game, enable ForeverScout in the AddOns list and `/reload`.

What works for each class:

| Feature | Hunter | Other classes |
|---|---|---|
| Snapshot (`/wow`, `/reload`), copy box, session history | yes | yes |
| `/donde` NPC and party arrow | yes | yes |
| Online friends, guild and communities | yes | yes |
| Alerts: bags almost full, low durability | yes | yes |
| Alerts: ammo and pet | yes | — |
| Loot roll NEED / GREED advice | yes | — (hunter stat weights) |
| Tooltip score | yes | — (hunter stat weights) |

### 2. The offline tools (optional)

Needs Python 3.10+ and the Forever QuestieDB addon installed in the game.

Linux / macOS:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
WOW_DIR="/path/to/_forever_" .venv/bin/python tools/build_q.py
WOW_DIR="/path/to/_forever_" .venv/bin/python tools/analyze.py
```

Windows (PowerShell):

```powershell
py -m venv .venv
.venv\Scripts\pip install -r requirements.txt
$env:WOW_DIR = "C:\Program Files (x86)\World of Warcraft\_forever_"
.venv\Scripts\python tools\build_q.py
.venv\Scripts\python tools\analyze.py
```

`WOW_DIR` must point at the game folder that holds `Interface/` and `WTF/`. The default in
`config.py` is the author's own path, so set it (or edit `config.py`) on any other machine.
Log in once with each character and `/reload` so it gets a snapshot.

Using an AI assistant (Claude Code, Codex, Cursor…)? Ask it to read `AGENTS.md`: it walks you
through setup and daily use, and keeps your personal profile in a git-ignored `PLAYER.md`.
`CLAUDE.md` holds the author's own rules.

### Configuration

Paths live in `config.py` and can be overridden with environment variables:

| Variable | Default |
|---|---|
| `WOW_DIR` | game folder holding `Interface/` and `WTF/` |
| `WOW_ACCOUNT` | auto-detected (the only, or most recently used, `WTF/Account/<name>`) |
| `WOW_CHAR` | highest-level character with a ForeverScout snapshot |
| `FOREVERSCOUT_SNAPSHOT` | explicit snapshot file (overrides `WOW_CHAR`) |
| `WOW_AUCTION_REALM` | every Auctionator price database key |

## Characters

Characters are discovered from `WTF/Account/<account>/<realm>/<character>/`, so any number of
mains, alts and bank alts works. Install ForeverScout and log in once with each character
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
- `WTF/.../SavedVariables/ForeverScout.lua` and `ShortestPathForever.lua` — snapshot and known flight paths.
- `WTF/<account>/SavedVariables/Syndicator.lua` — bags, bank and mail of every character.
- `WTF/<account>/SavedVariables/Auctionator.lua` — AH price database (run a full scan to refresh) and vendor price cache.
