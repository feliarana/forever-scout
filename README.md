# forever-scout

Leveling toolkit for **World of Warcraft: Forever** (Classic+, level cap 60), for any class and
faction: an in-game addon takes a snapshot of your character and offline tools let an AI
assistant read it to plan your next steps. It started as the author's troll hunter setup, so
hunters get the most out of the box.

New here? Install the addon ([step 1](#1-the-addon-any-class)), type `/scout help` in game, and
read the [addon README](addon/ForeverScout/README.md).

- `addon/ForeverScout/` — in-game addon: character snapshot, loot advisor, tooltip score, upkeep alerts and NPC arrow
  ([addon README](addon/ForeverScout/README.md)). The game's `Interface/AddOns/ForeverScout` is a
  symlink to this folder.
- `tools/` — Python scripts that cross the live snapshot with the installed QuestieDB.
- `guide/` — the author's troll hunter leveling guide (work in progress).
- `tests/` — addon tests that run outside the game (`npm test`).
- `AGENTS.md` — guide for any AI assistant helping a player set up and use the toolkit.
- `CLAUDE.md` — the author's personal rules for Claude.

## Features

### In game (ForeverScout)

- **Snapshot** — quests, location, gear, bags, talents, spellbook, action bars, pet,
  professions, buffs, hearthstone, durability, party and online friends, refreshed every 20
  seconds and written to disk on `/reload`. `/scout [question]` also opens a copy box with a
  one-line summary to paste into a chat.
- **Online friends** — friend list, Battle.net friends playing WoW, guild and community
  members, with level and zone; guild name and rank, communities; party members with map
  position.
- **Session history** — XP total, level-ups, deaths (with place), dungeon runs with XP gained,
  known flight paths and recipes.
- **Window capture** — last quest reward window, trainer and vendor opened, with stats and
  costs.
- **Loot advisor** — NEED / GREED verdict on every loot roll, or with
  `/scout <item link>`, using stat weights against the equipped item. Hunters have built-in
  weights; other classes set their own with `/scout weights`.
- **Tooltip score** — every gear tooltip shows the weighted score difference against what is
  equipped (green upgrade, red downgrade), or why your class cannot use the item.
- **Addon overlap check** — `/scout addons` lists loaded addons that do the same job, to trim
  long addon lists.
- **Upkeep alerts** — on-screen warning and sound for low ammo (with a hint to equip another
  stack), dead / unhappy / content / missing pet, nearly full bags, low durability and unspent
  talent points. `/scout alerts on|off`.
- **In-game help and languages** — `/scout help` explains every command; messages are in
  Spanish on esMX / esES clients and English elsewhere.
- **NPC arrow** — `/donde <npc name | id | party member>` puts a TomTom arrow on the nearest
  spawn (Questie database) and prints the distance in yards and meters; with no argument it
  uses the NPC target, and it follows party members live. `/donde off` clears it.

### Offline tools

| Script | What it gives |
|---|---|
| `analyze.py` | Character summary (XP, rested XP, location, hearthstone, gold, bags, durability, pet, unspent talent points and where they can go, XP pace, PvP flag, party with distance, online friends, deaths at this level, flight paths), gear and consumables (ranged weapon, ammo, food, bag upgrades by stat weights), quest log size against its cap, quests ready to turn in with NPC and location, quests in progress with objectives, quests unlocked by turning in, and quests available in the current and neighboring zones |
| `guide.py` | Per quest: start and turn-in NPCs, quest text, objectives with mob levels, elite flags and spawn clusters |
| `route_check.py` | Distance from every logged quest's objectives and turn-in to a planned route (on route / short detour / off route) and real XP at the current level |
| `map_route.py` | A numbered route for the in-game world map from quests and waypoints: objectives first (nearest-neighbour order), turn-ins last, one pin per spot. Writes it into the addon for `/scout route` (`--addon`), as a [wow-ai](https://github.com/chelinho139/wow-ai) map layer, or as TomTom `/way` lines (`--tomtom`) |
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
       `mklink /D "C:\...\_forever_\Interface\AddOns\ForeverScout" "C:\...\forever-scout\addon\ForeverScout"`
     - Linux / macOS: `ln -s /path/to/forever-scout/addon/ForeverScout /path/to/_forever_/Interface/AddOns/ForeverScout`
3. Optional, recommended: install **Questie** (Forever version, with QuestieDB) and **TomTom**.
   `/donde` needs both.
4. In game, enable ForeverScout in the AddOns list and `/reload`. Type `/scout help`.

What works for each class:

| Feature | Hunter | Other classes |
|---|---|---|
| Snapshot (`/scout`, `/reload`), copy box, session history | yes | yes |
| `/donde` NPC and party arrow | yes | yes |
| Online friends, guild and communities | yes | yes |
| Alerts: bags almost full, low durability, unspent talent points | yes | yes |
| Alerts: ammo and pet | yes | — |
| Loot roll NEED / GREED advice and tooltip score | yes, built-in weights | after setting your own with `/scout weights` |

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
(`/scout` or `/reload`) so it gets a snapshot.

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
.venv/bin/python tools/map_route.py            # route for every quest in the current zone
.venv/bin/python tools/map_route.py --addon    # same, loaded by /scout route after a /reload
.venv/bin/python tools/map_route.py 509 567 501 --tomtom   # chosen quests, as /way lines
```

### Routes on the world map

`map_route.py` needs something in game to draw the route:

- **wow-ai** (chat with an AI agent inside the game): when a wow-ai chat works in this folder,
  the bridge sets `WOW_AI_MAP_FILE` and `map_route.py` appends the route to it. The route shows
  as numbered pins joined by lines, with wow-ai's navigator arrow walking from stop to stop.
  `map_route.py --clear` removes it.
- **ForeverScout + TomTom**: `--addon` writes the route into the installed addon
  (`Interface/AddOns/ForeverScout/Route.lua`). `/reload`, then `/scout route` adds every stop
  as a TomTom waypoint and points the arrow at the first; `/scout route next` moves on. No
  pasting, and a `/reload` resumes where you were.
- **TomTom alone**: `--tomtom` prints one `/way` line per stop to paste into the game chat.

Without `WOW_AI_MAP_FILE` or `--out FILE`, the map command is printed. Stops can be quest IDs
(unfinished objectives plus the turn-in), `turnin:QUESTID`, or `ZONE:X,Y=label` waypoints.
Each objective is placed at the centre of its biggest spawn cluster in the zone.

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

## Development

The addon has a test suite that runs outside the game: `tests/addon_test.js` loads
`ForeverScout.lua` in a Lua VM ([fengari](https://github.com/fengari-lua/fengari)) against
`tests/wow_stub.lua`, a small stand-in for the WoW client, and checks the snapshot, the loot
advisor, the alerts, the slash commands and the Spanish translations. It also parses the file
as Lua 5.1, the version the game runs.

```bash
npm install   # once; needs Node.js 22+
npm test
.venv/bin/python -m unittest discover -s tests -p "test_*.py"   # offline tools
```

`addon/ForeverScout/Route.lua` is tracked as an empty placeholder (the client only finds addon
files that exist at launch) and `map_route.py --addon` rewrites it. To keep your own routes
out of `git status`: `git update-index --skip-worktree addon/ForeverScout/Route.lua`.

Run it before every `/reload` on a change to the addon; CI runs it on every push
(`.github/workflows/test.yml`). When the addon calls a client API the stub does not model
yet, add it to `tests/wow_stub.lua`.

## Credits

- [chelinho139/wow-ai](https://github.com/chelinho139/wow-ai) — the idea of testing a WoW addon
  in a Lua VM with a client stub comes from its test suite, and `map_route.py` writes its map
  layer format.
- [Questie](https://github.com/Questie/Questie) and [QuestieDB](https://github.com/Questie/QuestieDB)
  — quest, NPC and spawn data, read live from the installed addon.
