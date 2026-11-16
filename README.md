<p align="center">
  <img src="assets/logo.png" alt="ForeverScout logo: a folded map with a numbered route and a guide arrow" width="160">
</p>

# ForeverScout

**An addon for World of Warcraft: Forever that lets an AI help you level.**

You know the moment: thirty quests in the log, bags half full, a talent point you forgot, and
no idea where to go next. ForeverScout packs your whole character into a summary an AI
assistant can read (quests, gear, bags, talents, professions, who is online), so you can
simply ask *"what should I do next?"* and get an answer about **your** character.

It also helps on its own while you play: arrows to NPCs, routes with waypoints, loot advice
and reminders. Any class, Horde or Alliance. English and Spanish.

> CurseForge page: coming soon. Until then, install it from this page (two minutes, below).

## What it does for you

- **Ask an AI about your character.** Type `/scout`, press Ctrl+C, paste into ChatGPT, Claude
  or any AI chat and ask your question. No setup, nothing to install besides the addon.
- **Find any NPC.** `/whereis Lydon` puts an arrow on the nearest one and tells you how far
  it is. It also follows a party member: `/whereis Mauro`.
- **Follow a route.** `/scout route` walks you stop by stop with waypoints: objectives first,
  turn-ins last.
- **Know what to roll.** NEED or GREED in chat on every loot roll, and a line on every gear
  tooltip saying how much better or worse it is than what you wear.
- **Stop forgetting things.** A warning when your bags are almost full, your gear is about to
  break or you have a talent point to spend. Hunters also get low ammo and pet warnings.
- **Trim your addon list.** `/scout addons` shows which of your addons do the same job twice.

## Install

1. Download this page: green **Code** button → **Download ZIP**, then unzip it.
2. Copy the `addon/ForeverScout` folder into your game's `_forever_/Interface/AddOns/` folder.
   You should end up with `Interface/AddOns/ForeverScout/ForeverScout.toc`.
3. Start the game, tick **ForeverScout** in the AddOns list on the character screen, and log
   in. Chat says `ForeverScout: loaded. Type /scout help`.

Optional but recommended: **Questie** (Forever version) and **TomTom**. `/whereis` and
`/scout route` need them; everything else works without. The game never installs one addon
for another, so get those two yourself.

## Your first five minutes

| Type this | What happens |
|---|---|
| `/scout help` | The list of commands, in your game's language. |
| `/scout` | A box with a summary of your character, already selected. Ctrl+C, then paste it into an AI chat with your question. |
| `/scout is this ring good for me?` | Same, with your question included in the summary. |
| `/whereis <npc name>` | An arrow to that NPC. `/whereis off` removes it. |
| Shift-click an item after typing `/scout ` | NEED or GREED for that item against what you wear. |

## Commands

| Command | What it does |
|---|---|
| `/scout [question]` | Summary of your character to copy into an AI chat. |
| `/scout help` | Every command, explained. |
| `/whereis <npc \| party member>` | Arrow to an NPC or a party member. `/whereis` alone uses your target. |
| `/scout route` | Start (or resume) the loaded route. `/scout route next` moves on, `/scout route clear` removes it. |
| `/scout <item link>` | NEED or GREED for that item. |
| `/scout weights` | Show or set the stat weights behind the loot advice. |
| `/scout alerts on` / `off` | Turn the reminders on or off. |
| `/scout addons` | Lists addons you have that do the same job twice. |
| `/reload` | Saves the full snapshot to disk (only needed for the offline tools below). |

Full reference, with every detail: [addon README](addon/ForeverScout/README.md).

## What works for each class

| Feature | Hunter | Other classes |
|---|---|---|
| Summary for an AI (`/scout`) and full snapshot | yes | yes |
| `/whereis` NPC and party arrow, `/scout route` | yes | yes |
| Online friends, guild and communities in the summary | yes | yes |
| Alerts: bags almost full, low durability, unspent talent points | yes | yes |
| Alerts: ammo and pet | yes | — |
| Loot NEED / GREED advice and tooltip score | yes, ready to use | after one line: `/scout weights int=1 sta=0.5 …` |

The addon started as a troll hunter's setup, so hunters have stat weights built in. Any other
class sets its own once: ask your AI *"what are good leveling stat weights for my class?"* and
type them with `/scout weights`.

## Questions

**Do I need to know programming or install Python?**
No. The addon alone gives you everything above. Python is only for the optional offline tools.

**Does it play for me, or break the rules?**
No. It only reads what any addon can read and shows you information. It never moves, targets
or casts for you.

**Is my data sent anywhere?**
No. The addon cannot use the internet. The summary stays on your computer until you paste it
somewhere yourself. Note that it includes the names of your party, friends, guild and
communities.

**Why do I sometimes need `/reload`?**
The game only writes addon data to disk on `/reload` or logout. `/scout` and the copy box do
not need it; the offline tools do.

**It is in Spanish / English and I want the other one.**
Messages follow your game client: Spanish on esMX and esES, English everywhere else.

**Something is wrong or I have an idea.**
Open an issue on this page (the **Issues** tab).

---

## Going further: let the AI read everything

The copy box is a summary. The **offline tools** give an AI assistant the full picture: they
read the complete snapshot together with your installed Questie database and answer things
like *where is every objective and turn-in*, *which quests are on my way*, *what should I
sell*, *how fast am I leveling* and *what route should I take*. This part is optional and needs Python.

The easiest way to use them is with a coding assistant (Claude Code, Codex, Cursor…): open
this folder with it and ask it to read `AGENTS.md`. It walks you through setup, asks about
your character and keeps your profile in a private `PLAYER.md`.

| Script | What it gives |
|---|---|
| `analyze.py` | Character summary (XP, rested XP, location, hearthstone, gold, bags, durability, pet, unspent talent points and where they can go, XP pace, PvP flag, party with distance, online friends, deaths at this level, flight paths), gear and consumables (ranged weapon, ammo, food, bag upgrades by stat weights), quest log size against its cap, quests ready to turn in with NPC and location, quests in progress with objectives, quests unlocked by turning in, and quests available in the current and neighboring zones |
| `guide.py` | Per quest: start and turn-in NPCs, quest text, objectives with mob levels, elite flags and spawn clusters |
| `route_check.py` | Distance from every logged quest's objectives and turn-in to a planned route (on route / short detour / off route) and real XP at the current level |
| `map_route.py` | A numbered route for the in-game world map from quests and waypoints: objectives first (nearest-neighbour order), turn-ins last, one pin per spot. Writes it into the addon for `/scout route` (`--addon`), as a [wow-ai](https://github.com/chelinho139/wow-ai) map layer, or as TomTom `/way` lines (`--tomtom`) |
| `inventory.py` | Vendor / auction / use / keep / turn-in for every character's bags, bank and mail, with Auctionator prices |
| `build_q.py` | Builds the `data/Q.pkl` cache from QuestieDB plus real Forever quest XP (the other tools rebuild it when stale) |

Nothing from the game is copied here: tools always read the live files under `WOW_DIR`.

Nothing from the game is copied here: tools always read the live files under `WOW_DIR`.

### Install the offline tools

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

## What is in this repository

- `addon/ForeverScout/` — the in-game addon ([addon README](addon/ForeverScout/README.md)).
- `tools/` — Python scripts that cross the live snapshot with the installed QuestieDB.
- `tests/` — tests for the addon and the tools that run outside the game.
- `guide/` — the author's troll hunter leveling guide (work in progress).
- `docs/curseforge.md`, `assets/` — texts and logo for the CurseForge page.
- `AGENTS.md` — guide for any AI assistant helping a player set up and use the toolkit.
- `CLAUDE.md` — the author's personal rules for Claude.

To pick up updates automatically, link the addon folder instead of copying it:

- Windows (Command Prompt as admin):
  `mklink /D "C:\...\_forever_\Interface\AddOns\ForeverScout" "C:\...\forever-scout\addon\ForeverScout"`
- Linux / macOS: `ln -s /path/to/forever-scout/addon/ForeverScout /path/to/_forever_/Interface/AddOns/ForeverScout`

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
