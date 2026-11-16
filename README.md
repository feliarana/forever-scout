<p align="center">
  <img src="assets/logo.png" alt="TrailScout logo: a folded map with a numbered route and a guide arrow" width="160">
</p>

# TrailScout

**An addon for World of Warcraft: Forever that lets an AI help you level.**

You know the moment: thirty quests in the log, bags half full, a talent point you forgot, and
no idea where to go next. TrailScout packs your whole character into a summary an AI
assistant can read (quests, gear, bags, talents, professions, who is online), so you can
simply ask *"what should I do next?"* and get an answer about **your** character.

It also helps on its own while you play: arrows to NPCs, routes with waypoints, loot advice
and reminders. Any class, Horde or Alliance. English and Spanish.

> CurseForge page: coming soon. Until then, install it from this page (two minutes, below).

## What it does for you

- **Ask an AI about your character.** Click the minimap button, pick a question (*What should
  I do next?*), press Ctrl+C and paste into ChatGPT, Claude or any AI chat. No commands, no
  setup, nothing to install besides the addon. `/scout` does the same from chat.
- **Find any NPC or object.** `/whereis Lydon` puts an arrow on the nearest one, tells you
  how far it is and gives you a **[Show on map]** link to click when it is far away. It works
  for things in the world too (`/whereis mudsnout blossom`) and follows a party member:
  `/whereis Mauro`.
- **Follow a route.** `/scout route` walks you stop by stop with waypoints: objectives first,
  turn-ins last.
- **Know what to roll.** NEED or GREED in chat on every loot roll, and a line on every gear
  tooltip saying how much better or worse it is than what you wear.
- **Stop forgetting things.** A warning when your bags are almost full, your gear is about to
  break or you have a talent point to spend. Hunters also get low ammo and pet warnings.
- **Trim your addon list.** `/scout addons` shows which of your addons do the same job twice.

## Install

1. Download this page: green **Code** button → **Download ZIP**, then unzip it.
2. Copy the `addon/TrailScout` folder into your game's `_forever_/Interface/AddOns/` folder.
   You should end up with `Interface/AddOns/TrailScout/TrailScout.toc`.
3. Start the game, tick **TrailScout** in the AddOns list on the character screen, and log
   in. Chat says `TrailScout: loaded. Type /scout help`.

Optional but recommended: **Questie** (Forever version) and **TomTom**. `/whereis` and
`/scout route` need them; everything else works without. For the offline tools, **Syndicator**
adds your bank, mail and other characters, and **Auctionator** adds auction prices. The game never installs one addon
for another, so get those two yourself.

## Your first five minutes

| Type this | What happens |
|---|---|
| Click the **TrailScout button** (on the minimap, or the floating one you can drag anywhere) | The TrailScout window: ready-made questions to copy into an AI chat, a search box for NPCs and objects, a switch for every feature and a Help page. It opens by itself the first time, so nothing has to be typed. |
| `/scout help` | The list of commands in chat, in your game's language. |
| `/scout` | A box with a summary of your character, already selected. Ctrl+C, then paste it into an AI chat with your question. |
| `/scout is this ring good for me?` | Same, with your question included in the summary. |
| `/whereis <npc or object name>` | Where it is, an arrow to it and a **[Show on map]** link. `/whereis off` removes the arrow. |
| Shift-click an item after typing `/scout ` | NEED or GREED for that item against what you wear. |

## Commands

| Command | What it does |
|---|---|
| `/scout [question]` | Summary of your character to copy into an AI chat. |
| `/scout config` | The settings and help window (same as the minimap button). |
| `/scout help` | Every command, explained in chat. |
| `/whereis <npc \| object \| party member>` | Finds it: distance, arrow and a link to see it on the world map. `/whereis` alone uses your target, `/whereis map` opens the map again. |
| `/scout route` | Start (or resume) the loaded route. `/scout route next` moves on, `/scout route clear` removes it. |
| `/scout <item link>` | NEED or GREED for that item. |
| `/scout weights` | Show or set the stat weights behind the loot advice. |
| `/scout alerts on` / `off` | Turn the reminders on or off. |
| `/scout addons` | Lists addons you have that do the same job twice. |
| `/reload` | Saves the full snapshot to disk (only needed for the offline tools below). |

Full reference, with every detail: [addon README](addon/TrailScout/README.md).

## What works for each class

| Feature | Hunter | Other classes |
|---|---|---|
| Summary for an AI (`/scout`) and full snapshot | yes | yes |
| `/whereis` for NPCs, objects and party members, `/scout route` | yes | yes |
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
Everything follows your game client: Spanish on esMX and esES, English everywhere else. Quest,
item and NPC names always come from the game itself, in your language. The offline tools do the
same, and on a Spanish client show names as `English / Spanish`.

**Something is wrong or I have an idea.**
Open an issue on this page (the **Issues** tab).

---

## Going further: let the AI read everything

The copy box is a summary. The **offline tools** give an AI assistant the full picture: they
read the complete snapshot together with your installed Questie database and answer things
like *where is every objective and turn-in*, *which quests are on my way*, *what should I
sell*, *how fast am I leveling* and *what route should I take*. This part is optional and needs Python.

### Play with an AI at your side (how the author uses it)

There are two ways to bring an AI in, and they need different kinds of AI:

| | Any chat AI (ChatGPT, Claude, Gemini… in the browser) | An AI agent working in this folder |
|---|---|---|
| What you do | `/scout` in game, paste the summary, ask | `/reload` in game, tell the agent **"read"** |
| What the AI sees | The one-line summary | Everything: full snapshot, quest database, auction prices |
| What it can do | Advise from the summary | Run the tools, check your route, write a route for `/scout route` |
| Setup | None | Once, about ten minutes, guided by the AI itself |

The second way is the one this project was built for. It works with any agent that can read
files and run commands on your computer: Claude Code, Codex, Cursor, Gemini CLI, Copilot's
agent mode and similar. A chat window in the browser cannot do it, because it cannot run the
tools.

1. **Open this folder as the project** in your agent (the folder you unzipped or cloned, the
   one that holds `AGENTS.md`).
2. **First time**, say: *"Read AGENTS.md and set me up."* It asks about your character,
   professions and game folder, installs what is missing and saves your answers to a private
   `PLAYER.md` that never leaves your computer.
3. **While you play**, keep the agent open next to the game. When you want advice: `/reload`
   in game, then tell the agent **"read"**. It reads your fresh snapshot and answers with what
   to turn in, where to go next, what to sell and what you forgot (talent points, repairs,
   full bags).
4. **Ask for the route**: it writes the stops into the addon; `/reload` and `/scout route`
   put them on your map.

`AGENTS.md` is the instruction file for the AI, the same for every agent. Most agents load it
by themselves when they open the folder; if yours does not seem to know the project, tell it
to read `AGENTS.md` first. Talk to it in your own language: it answers in yours and names
quests and NPCs the way your game client shows them.

| Script | What it gives |
|---|---|
| `analyze.py` | Character summary (XP, rested XP, location, hearthstone, gold, bags, durability, pet, unspent talent points and where they can go, XP pace, PvP flag, party with distance, online friends, deaths at this level, flight paths), gear and consumables (ranged weapon, ammo, food, bag upgrades by stat weights), where talent and perk (legacy) points can go with the game's descriptions, professions (cap warnings, skill-up recipes, skinning reach), bank and mail of every character (with mail about to expire) and quest items already owned outside the bags, quest log size against its cap, quests ready to turn in with NPC and location (from the game's own waypoint and your accept history when the quest database has no place for it), quests in progress with objectives, quests unlocked by turning in, and quests available in the current and neighboring zones |
| `guide.py` | Per quest: start and turn-in NPCs, quest text, objectives with mob levels, elite flags and spawn clusters |
| `route_check.py` | Distance from every logged quest's objectives and turn-in to a planned route (on route / short detour / off route) and real XP at the current level |
| `quest_value.py` | Every logged quest ranked by estimated XP per minute: minutes to finish it from where the character stands, quest XP plus the XP of the kills it needs. Quests of the current zone first, other zones timed from arriving there. A model for ranking and for spotting quests not worth doing, not a schedule |
| `map_route.py` | A numbered route for the in-game world map. With no arguments it plans the whole zone and follows quest chains: logged quests, the quests their turn-ins unlock, and new quests worth picking up, each stop after what it needs and within the room left in the quest log. With quest IDs or waypoints it routes just those, one pin per spot. Writes it into the addon for `/scout route` (`--addon`), as a [wow-ai](https://github.com/chelinho139/wow-ai) map layer, or as TomTom `/way` lines (`--tomtom`) |
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
`CLAUDE.md` only points Claude Code at `AGENTS.md` and your `PLAYER.md`.

### Configuration

Paths live in `config.py` and can be overridden with environment variables:

| Variable | Default |
|---|---|
| `WOW_DIR` | game folder holding `Interface/` and `WTF/` |
| `WOW_ACCOUNT` | auto-detected (the only, or most recently used, `WTF/Account/<name>`) |
| `WOW_CHAR` | highest-level character with a TrailScout snapshot |
| `TRAILSCOUT_SNAPSHOT` | explicit snapshot file (overrides `WOW_CHAR`) |
| `WOW_AUCTION_REALM` | every Auctionator price database key |

## Characters

Characters are discovered from `WTF/Account/<account>/<realm>/<character>/`, so any number of
mains, alts and bank alts works. Install TrailScout and log in once with each character
(`/scout` or `/reload`) so it gets a snapshot.

- `analyze.py`, `guide.py` and `route_check.py` work on one character: `--char NAME`
  (folder name like `Caza-Peques` or just `Caza`), else `WOW_CHAR`, else the highest level.
  Quest filters use that character's race, class and faction.
- `inventory.py` always covers every character: bags, bank and mail from Syndicator, plus
  snapshot data. `analyze.py` uses the same data to point at quest items that sit in the
  bank, in the mail or on another character. Bank and mail are as of the last time each was
  opened in game; without Syndicator only the bags of characters with a snapshot are known.
- Some quest items are assembled from other items (pages of a manual into a chapter).
  QuestieDB does not record that, so the known cases live in `config.ITEM_PARTS`: the parts
  are kept instead of sold and reported with what is still missing. Items mailed to a bank alt show up under its mail until collected.
- Stat weights for the bag-upgrade check are per class in `config.STAT_WEIGHTS` (hunter only
  for now); `config.KEEP_ITEMS` is the list of items to never sell.

## Usage

```bash
.venv/bin/python tools/analyze.py                 # current zone + neighbors
.venv/bin/python tools/analyze.py 17 400          # specific zones
.venv/bin/python tools/analyze.py --char Banca    # another character
.venv/bin/python tools/guide.py 4841 5147
.venv/bin/python tools/route_check.py 17:52,30 17:45,57 400:46,51 400:38,27
.venv/bin/python tools/quest_value.py          # quests ranked by estimated XP per minute
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
- **TrailScout + TomTom**: `--addon` writes the route into the installed addon
  (`Interface/AddOns/TrailScout/Route.lua`). `/reload`, then `/scout route` adds every stop
  as a TomTom waypoint and points the arrow at the first; `/scout route next` moves on. No
  pasting, and a `/reload` resumes where you were.
- **TomTom alone**: `--tomtom` prints one `/way` line per stop to paste into the game chat.

With no stops, the route is the whole zone with its chains. Take *Battle of Hillsbrad*: the
route kills the farmers, turns the quest in, accepts the next part on the spot, goes back
out for it, and so on through the chain. A turn-in that unlocks nothing waits for a later
pass by town; one that opens the next quest does not. New quests are picked up only when
they can be finished in the zone, still pay most of their XP and the log has a free slot
(turn-ins free slots as the route goes). Stops where every source is elite are marked
`(elite)`. `--skip 547,567` leaves quests out together with whatever only they unlock;
`--no-chains` and `--no-accept` switch the two additions off.

Without `WOW_AI_MAP_FILE` or `--out FILE`, the map command is printed. Stops can be quest IDs
(unfinished objectives plus the turn-in), `turnin:QUESTID`, or `ZONE:X,Y=label` waypoints.
Each objective is placed at the centre of its biggest spawn cluster in the zone.

### What a quest is worth

`quest_value.py` (and the *Quest value here* section of `analyze.py`) estimates each quest on
its own:

- **Quest XP** is the game client's number when the snapshot has it.
- **Travel** is straight lines on foot, using zone sizes in yards that the addon measures from
  the client (`mapSizes` in the snapshot; a default size until then).
- **Kills** are the remaining count divided by the drop rate, with a time per kill that grows
  with the mob's level (elites take three times as long) and Classic's mob XP formula. Gray
  mobs give nothing, which is what makes an old kill quest poor value.
- Quests in another zone are timed from arriving at their first stop; the trip is not guessed.

Quests that share an area are cheaper together than their separate numbers suggest, and the
constants (seconds per kill, running speed) sit at the top of the script.

Distances are in map units (percent of the zone map). Route check thresholds: ≤10 on route,
≤20 short detour, otherwise off route. XP uses QuestieDB's real Forever XP traces
(`~classic` marks a fallback to Classic values) with the Classic gray-quest penalty.

## Data sources (read live from the game folder)

- `QuestieDB/QuestieDB_Forever.toc` — quests, NPCs, objects, items, esMX translations.
- `QuestieDB/support/Forever/QuestXP/xpDB-traces.lua` — real quest XP on Forever.
- `QuestieDB/support/Forever/Zones/uiMapIdToAreaId.lua` — map ID → zone.
- `QuestieDB/support/Forever/DropTables/classicItemDrops.lua` — drop rates.
- `WTF/.../SavedVariables/TrailScout.lua` and `ShortestPathForever.lua` — snapshot and known flight paths.
- `WTF/<account>/SavedVariables/Syndicator.lua` — bags, bank and mail of every character.
- `WTF/<account>/SavedVariables/Auctionator.lua` — AH price database (run a full scan to refresh) and vendor price cache.

## What is in this repository

- `addon/TrailScout/` — the in-game addon ([addon README](addon/TrailScout/README.md)).
- `tools/` — Python scripts that cross the live snapshot with the installed QuestieDB.
- `tests/` — tests for the addon and the tools that run outside the game.
- `guide/` — the author's troll hunter leveling guide (work in progress).
- `CHANGELOG.md` — what each release brings.
- `docs/curseforge.md`, `docs/curseforge-description.md`, `assets/` — texts and logo for the
  CurseForge page.
- `LICENSE` — MIT.
- `AGENTS.md` — guide for any AI assistant helping a player set up and use the toolkit.
- `CLAUDE.md` — pointer for Claude Code to `AGENTS.md` and the player's private `PLAYER.md`.

To pick up updates automatically, link the addon folder instead of copying it:

- Windows (Command Prompt as admin):
  `mklink /D "C:\...\_forever_\Interface\AddOns\TrailScout" "C:\...\trail-scout-wow\addon\TrailScout"`
- Linux / macOS: `ln -s /path/to/trail-scout-wow/addon/TrailScout /path/to/_forever_/Interface/AddOns/TrailScout`

## Development

The addon has a test suite that runs outside the game: `tests/addon_test.js` loads
`TrailScout.lua` in a Lua VM ([fengari](https://github.com/fengari-lua/fengari)) against
`tests/wow_stub.lua`, a small stand-in for the WoW client, and checks the snapshot, the loot
advisor, the alerts, the slash commands and the Spanish translations. It also parses the file
as Lua 5.1, the version the game runs.

```bash
npm install   # once; needs Node.js 22+
npm test
.venv/bin/python -m unittest discover -s tests -p "test_*.py"   # offline tools
```

`addon/TrailScout/Route.lua` is tracked as an empty placeholder (the client only finds addon
files that exist at launch) and `map_route.py --addon` rewrites it. To keep your own routes
out of `git status`: `git update-index --skip-worktree addon/TrailScout/Route.lua`.

Run it before every `/reload` on a change to the addon; CI runs it on every push
(`.github/workflows/test.yml`). When the addon calls a client API the stub does not model
yet, add it to `tests/wow_stub.lua`.

## Releasing

```bash
.venv/bin/python tools/build_release.py   # writes dist/TrailScout-<version>.zip
```

The zip has the `TrailScout/` folder at its root, ready for `Interface/AddOns/` and for a
CurseForge upload. The version comes from `## Version:` in the TOC: bump it there (and in
`package.json`) before building. `Route.lua` always ships empty. The steps on the CurseForge
side are in [docs/curseforge.md](docs/curseforge.md).

## License

[MIT](LICENSE).

## Other data sources

Quest XP comes from the game client first (the snapshot has what each logged quest pays at
your level), then from QuestieDB. Two open projects are worth knowing as they grow:

- [opendata](https://github.com/wowlayerup-forever/opendata) (data CC BY 4.0, with an MCP
  server for AI agents): game data keyed by Blizzard IDs with provenance on every row. As of
  November 2026 it holds 46 quests and no world data, so the tools do not read it yet.
- [forever-xp](https://github.com/Jweyant/forever-xp) (GPL-3.0): hand-written leveling routes
  with skip reasons, quest XP-per-minute scores, talent builds and Blizzard's change notes.
  A good reference for an AI assistant; its code and data files are not copied here because
  of the license difference.

## Credits

- [chelinho139/wow-ai](https://github.com/chelinho139/wow-ai) — the idea of testing a WoW addon
  in a Lua VM with a client stub comes from its test suite, and `map_route.py` writes its map
  layer format.
- [Questie](https://github.com/Questie/Questie) and [QuestieDB](https://github.com/Questie/QuestieDB)
  — quest, NPC and spawn data, read live from the installed addon.
