# TrailScout

In-game addon for WoW Forever (Interface 16001), for any class and faction.

TrailScout takes a snapshot of your character (quests, gear, bags, talents, professions,
party and online friends) so an AI assistant can read it and plan your next steps with you.
On its own it also points an arrow at NPCs and party members, warns you about full bags, low
durability and unspent talent points, and scores gear against what you wear.

## Quick start

1. Copy the `TrailScout` folder into the game's `_forever_/Interface/AddOns/`, enable it in
   the AddOns list and log in. Chat shows `TrailScout: loaded. Type /scout help...` the first
   time.
2. The TrailScout window opens by itself the first time. Later, click the **TrailScout button
   on the minimap**: ready-made questions for an AI, a search box, a switch for every feature
   and a Help page that explains each one. `/scout help` prints the
   list of commands in chat. Both follow your client's language, English or Spanish.
3. To ask an AI about your character, pick one:
   - **Quick, no setup:** type `/scout`, press Ctrl+C in the box that opens and paste the line
     into any AI chat with your question.
   - **Full detail:** type `/reload` so the game writes the whole snapshot to disk, then let
     an AI assistant read it with the offline tools from the
     [trail-scout-wow repository](https://github.com/feliarana/trail-scout-wow) (needs Python).

The game only writes addon data to disk on `/reload`, logout or character switch. That is why
the full snapshot needs a `/reload`.

### What works for your class

| Feature | Hunter | Other classes |
|---|---|---|
| Snapshot, copy box, session history, XP pace | yes | yes |
| `/whereis` for NPCs, objects and party members | yes | yes |
| `/scout route` waypoints (route from an AI chat or the offline tools) | yes | yes |
| Alerts: bags, durability, unspent talent points | yes | yes |
| Alerts: ammo and pet | yes | — |
| Loot NEED / GREED advice and tooltip score | yes | yes, with a set of weights per role |

### Privacy

The snapshot and the copy box include the names of your party members, online friends, guild
and communities. Everything stays in your game folder until you paste or share it yourself;
the addon sends nothing anywhere.

## Requirements

- Required: none. The snapshot, the copy box, the alerts and the loot advice work alone.
- Optional: **Questie** (spawn data for `/whereis`) and **TomTom** (arrow and live distance for
  `/whereis`, waypoints for `/scout route`). With Questie alone, `/whereis` still finds the
  place and shows it on the map, without the arrow.
  `/scout help` shows whether each one is loaded.

The game never installs one addon for another: install Questie (Forever version) and TomTom
yourself if you want `/whereis`. They are declared as optional (`## OptionalDeps`) on purpose: a
required dependency would stop TrailScout from loading at all without them.

## Slash commands

| Command | What it does |
|---|---|
| `/scout [question]` (older aliases `/wow`, `/feli`) | Builds the snapshot now and opens a copy box with a one-line summary to paste into a chat. The optional question is stored in the snapshot. Type `/reload` afterwards to write the full snapshot to disk. |
| `/scout addons` | Lists loaded addons that do the same job (bags, damage meters, action bars, quest auto-accept, map coordinates, fast loot, vendor prices…). Leatrix Plus and ElvUI only clash if the matching option is on. |
| `/scout alerts` | Shows the upkeep alert thresholds and runs a check now. |
| `/scout alerts off` / `/scout alerts on` | Mutes or re-enables upkeep alerts (saved per character). |
| `/scout <shift-clicked item link>` | Instant NEED / GREED verdict for that item against what is equipped. |
| `/scout route` (or `ruta`) | Walks the loaded route (imported from an AI chat, or written by `tools/map_route.py --addon`): one TomTom waypoint per stop, arrow on the current one. Carries on from the saved stop after a `/reload`. |
| `/scout import <TSR1 line>` | Loads the route line an AI chat answered with and starts it. Same as the box on the window's Start page; `/scout TSR1; …` works too. |
| `/scout route next` / `/scout route <n>` / `/scout route clear` | Move to the next stop, jump to stop n, or remove the route's waypoints. |
| `/scout help` (or `?`, `ayuda`) | What the addon does and every command. |
| `/scout config` (or `options`, `settings`, `opciones`) | Opens the settings window; `/scout guide` opens it on the Help page. |
| `/scout weights` | Shows the stat weights in use and the stats you can set. |
| `/scout weights agi=2.3 sta=0.7 …` | Sets your own stat weights for this character (merged over the ones in use). `/scout weights reset` goes back to the class default. |
| `/whereis <npc name>` (alias `/where`) | TomTom arrow to the nearest spawn of the NPC, with distance in yards and meters. Partial names work and accents are optional (`jabali` matches `Jabalí`). With several matches the nearest spawn wins and the others are listed with their IDs. |
| `/whereis <object name>` | Same, for things in the world from Questie's object table: chests, plants, quest objects (`/whereis mudsnout`). |
| `/whereis <npc id>` | Same, by NPC ID. |
| `/whereis` | Same, for the NPC currently targeted (`/target jabalí`, then `/whereis`). |
| `/whereis <party member>` | Arrow that follows a party member's live position (refreshed every 2 seconds). |
| `/whereis map` (or `mapa`) | Opens the world map on the zone of the last result. The chat line of every result ends with a clickable **[Show on map]** link that does the same; with TomTom the spot carries its waypoint pin. |
| `/whereis off` (or `clear`) | Clears the arrow. |

Limits of `/whereis`:

- The arrow points at the spawn point from Questie's database, not at the live mob: the
  client does not expose NPC positions.
- Players outside the party cannot be located: the client only gives party member positions.
  For friends outside the party, the snapshot records their zone (see `onlineFriends`).
- A failed search keeps the current arrow.

## Settings window and minimap button

The window opens by itself the first time a character logs in. After that, a left-click on
the minimap button opens it on **Start**, and `/scout config` on **Settings**. Three pages:

Addons that collect minimap buttons (OneForAll's *Collect minimap buttons*, Leatrix Plus's
button bag) take TrailScout's button into their own bar along with every other addon's. The
floating button, the addon list beside the minimap and `/scout config` open the same window.

- **Start**: everything a new player needs without typing a command. The four steps to ask an
  AI, seven ready-made questions (what to do next, which quests to do or skip, talents, what to
  sell, gear in the bags, a route, stat weights for the class) and a box for your own; each one copies
  the summary with the question in it, written in your language and asking for the answer in
  it. Below, a search box for NPCs, objects and party members with **Find**, **Show on map**
  and **Clear arrow**, and a line saying whether Questie and TomTom are loaded.

- **Settings**: a switch for the reminders as a whole and for each one (bags, durability,
  talent points, ammo, pet), for the loot roll advice, for the tooltip score line and for the
  minimap button itself; the stat weights as an editable line with Apply and Reset; and
  buttons for the things you would otherwise type (copy the summary, start or clear the
  route, check your addons).
- **Help**: every feature explained in a few sentences, with its commands.

Two launcher buttons do the same thing, and each has its own switch: one on the minimap and
a **floating** one that can be dragged anywhere on screen (it starts at the left edge), for
players who hide or crowd their minimap. Left-click opens the window on Start, right-click opens the copy box, and it can
be dragged around the minimap. Esc closes the window. Every choice is saved per character
(`settings`, `minimapAngle`, `floatPos` and `introduced` in `TrailScoutHistory`). On clients with an addon compartment,
TrailScout is listed there too.

## Routes

`/scout route` walks a route, one stop at a time. Needs TomTom. A route comes from one of two
places, and the newer one is used:

**From an AI chat (nothing else to install).** On the window's Start page press **Plan a route
for me**, paste the summary into your AI chat, and paste the line it ends its answer with into
the box **Paste a route from your AI chat** (or type `/scout import <line>`). The line looks
like this:

```
TSR1; Hillsbrad run; q514; find Apothecary Lydon; at 1424 61 20 Tarren Mill; t514
```

| Stop | Meaning | Placed from |
|---|---|---|
| `q514` | Go do quest 514 | Questie: one stop per place its open objectives send you to (creatures, objects, and whatever drops or sells an item); objectives close together share a stop. Objectives the log shows as finished are skipped |
| `t514` | Turn in quest 514 | Questie's turn-in NPC; for a quest Questie does not know, where you accepted it (the label says so) |
| `find <name>` | An NPC or object by name | Questie, as `/whereis` does |
| `at <map> <x> <y> [label]` | A place by map number and coordinates | Nothing: used as written. The map number of where you stand is in the summary |

The first part after `TSR1` is the route's name when it is not a stop. Stops that cannot be
placed are listed in chat and left out; the rest of the route still loads. The route is kept
in `TrailScoutHistory.importedRoute`, so it survives a `/reload`. Coordinates an assistant
writes from memory in an `at` stop can be wrong: quest and name stops are the reliable ones.

**From the offline tools.** `tools/map_route.py --addon` (from the
[trail-scout-wow repository](https://github.com/feliarana/trail-scout-wow)) writes the stops
into `Route.lua` in this folder; the game reads that file on every `/reload`, and chat says
`new route loaded` when there is one.

- Every remaining stop is a TomTom waypoint; the arrow points at the current stop.
- A plain waypoint advances by itself when you stand on it. A quest stop (kill, loot, object,
  turn-in) only says you arrived, since the work there takes a while: type `/scout route next`
  when you are done.
- The current stop is saved per character, so a `/reload` resumes the route.

## Snapshot

WoW only writes SavedVariables to disk on `/reload`, logout or character switch. The addon
rebuilds the snapshot 5 seconds after login and every 20 seconds after that, so a plain
`/reload` always writes current data. The periodic rebuild is skipped while in combat, and
the heavy sections (completed quests, spellbook, action bars, addon list) are cached and only
rebuilt after an event that changes them or an explicit `/scout`. A snapshot taken while logging out (unit data already
torn down) never overwrites a good one.

Each section is built on its own: an API that fails only empties its section, and the error
is stored under `errors`.

`TrailScoutDB` (per character, replaced on every snapshot):

| Key | Content |
|---|---|
| `savedAt`, `question`, `locale` | Snapshot time, optional `/scout` question, client locale |
| `name`, `realm`, `class`, `race`, `faction`, `level` | Identity, with non-localized class/race tokens for quest filtering |
| `xp`, `xpMax`, `rested`, `money`, `healthMax` | Progress and gold. Current health is a protected value on this client, so only the maximum is kept |
| `location` | Zone, subzone, map ID, map name and x,y in percent |
| `instance`, `currentRun` | Current instance and the dungeon run in progress (XP so far) |
| `party` | Party members: name, class, level, online flag, map ID, map name and x,y |
| `onlineFriends` | Online friends from the friend list, Battle.net friends playing WoW, the guild and communities: name, level, class, zone, realm and source (`friend`, `bnet`, `guild`, `community`) |
| `guild` | Guild name, own rank and rank index, members and members online; absent when not in a guild |
| `communities` | Every subscribed community except the guild: name, type (`bnet`, `wow`, `other`), member count and online members with level, class and zone |
| `pvpFlagged`, `target` | PvP flag and the current target |
| `quests`, `completedQuests` | Quest log with objectives, and completed quest IDs. Each logged quest also carries what the client itself reports: `xp` (what it pays at your level), `waypoint` (where the game's own marker points next; the Forever 1.60 client does not report it, so it is usually absent) and `giver` (who you took it from and where, recorded when you accepted it). These cover Forever's new quests, which the quest databases do not have yet |
| `questLog` | Quests in the log (`count`) and the log cap (`max`, absent when the client does not report it) |
| `pace` | XP pacing: session start, seconds and XP, `xpPerHour` for the session and `recentXPPerHour` over about the last hour. A session survives `/reload` and ends after 30 minutes without a snapshot; rates appear after 5 minutes |
| `equipment`, `bags` | Equipped items and bag contents, with stats |
| `skills`, `recipes` | Professions and the recipes seen in each profession window, each recipe filed under the profession it belongs to |
| `talents`, `unspentTalentPoints` | Full talent trees (trait system, classic API as fallback). Trait nodes carry `desc` (the game's description), `open` (prerequisites met) and `canBuy` (a point can be spent on it now) |
| `traitSystems`, `traitApi` | Every other trait system the client exposes, such as the Legacy perk trees, in the same shape as `talents`. While none is found, `traitApi` lists the client's trait-related API names so the gap can be diagnosed |
| `spellbook`, `actionBars` | Known spells with rank, and what sits in each action slot |
| `pet` | Name, family, level, XP, happiness (1 unhappy, 2 content, 3 happy) with its damage percentage, loyalty and the food types it eats |
| `hearth` | Hearthstone bind location and cooldown left |
| `mapSizes` | Width and height in yards of every zone map the client knows, so the offline tools can turn map percent into walking time |
| `upkeep` | Free bag slots and durability |
| `flights` | Known flight paths (recorded whenever the flight map opens) |
| `buffs`, `debuffs` | Active auras with stacks and time left |
| `lastQuestWindow`, `lastTrainer`, `lastMerchant` | Last quest reward window, trainer and vendor opened, with items and costs |
| `lastRolls` | Last 10 loot roll verdicts |
| `addons` | Loaded addon names, installed count and overlapping groups |
| `apiDiagnostics` | Which APIs exist on the client; only collected while talents or skills come back empty |
| `errors` | Error message per failed section |

`TrailScoutHistory` (per character, kept across sessions): running XP total, level-ups with
date and zone, deaths with place and level (killer taken from a hostile target, best effort; left empty when unknown),
dungeon runs with XP gained, flight paths, recipes, the XP pacing session (`pace`), where each
quest was accepted (`questGivers`), your own stat weights (`weights`) and the upkeep alert
setting (`alerts`).

Values from roster APIs can be restricted ("secret") on this client. Storing one in
SavedVariables triggers the blocked-action dialog, so the addon drops any value that fails a
comparison inside `pcall`.

## Upkeep alerts

A warning in the middle of the screen, the raid warning sound and a chat line when something
needs attention. Each alert fires when its condition starts and repeats every 5 minutes while
it lasts. Checks run a second after bag, pet, durability, combat-end, resting, level-up and
talent changes, and every 20 seconds.

| Alert | Condition | Message hint |
|---|---|---|
| Low ammo (hunter) | Equipped ammo below 400 | Equip the bigger stack of other ammo if there is one, else buy more |
| No ammo (hunter) | No ammo equipped | Drag arrows to the ammo slot, or buy them |
| Pet dead (hunter) | Pet is dead, out of combat | Revive Pet |
| Pet unhappy (hunter) | Happiness 1 (75% damage, may run away) | Feed Pet now |
| Pet content (hunter) | Happiness 2, out of combat | Feed Pet for +25% damage |
| No pet (hunter, level 10+) | No pet out, out of combat, not resting, mounted or flying | Call Pet |
| Unspent talent points | One or more points free, out of combat | Open the talent window |
| Bags almost full | 2 free bag slots or fewer | — |
| Low durability | Any equipped item below 25% | Repair |

Ammo is counted from the bag stacks (quiver included), since the ammo slot only references
them. Thresholds live in `ALERT_LIMITS` in `TrailScout.lua`.

## Loot advisor and tooltip score

Items are scored with stat weights: each stat on the item is multiplied by its weight and the
total is compared to the equipped item in the same slot.

Every class has built-in weights, one set per role. The first role is the default; pick
another with the buttons on the Settings page or `/scout weights <role>`:

| Class | Roles (`/scout weights …`) |
|---|---|
| Warrior | `melee`, `tank` |
| Paladin | `melee`, `healer`, `tank` |
| Hunter | `ranged` |
| Rogue | `melee` |
| Priest | `caster`, `healer` |
| Shaman | `melee`, `caster`, `healer` |
| Mage, Warlock | `caster` |
| Druid | `melee` (feral), `caster`, `healer` |

- **Where the numbers come from.** The hunter set is RestedXP's for levels 20-29 (ranged DPS
  14, agility 2.33, spirit 1.12, attack power 0.8, stamina 0.75, intellect 0.55, strength 0.2,
  armor 0.035). Every other set is TrailScout's own estimate for leveling, worked out from
  Classic's rules (attack power per strength or agility, Spirit Tap, Life Tap and so on). They
  have not been checked against Forever's changes: a starting point, not a verdict.
- **Your own numbers** always win: `/scout weights int=1 sp=0.8 sta=0.5` changes those stats
  and keeps the rest of the set, saved per character. `/scout weights reset` goes back to the
  role's set. Stats: `agi str sta int spi armor ap rap crit hit sp heal mp5 spellcrit
  spellhit dps rdps` (`dps` is melee weapon DPS, `rdps` ranged weapon DPS including wands;
  crit and hit are per 1%).
- The weights in use are saved in the snapshot (`weights`), so `tools/analyze.py` checks bag
  upgrades with the same numbers.

Gear your class cannot wear is flagged instead of scored: armor heavier than your class uses
(Classic rules, with the level 40 upgrade for warriors, paladins, hunters and shamans), shields
for classes without them, and for hunters weapons they cannot wield. Other classes have no
weapon list yet, so their weapons are always scored. For rings and trinkets the weaker equipped one
is the comparison; a two-hander is compared to main hand plus off hand.

- **Loot rolls**: when a roll starts (or on `/scout <item link>`), the verdict (NEED or GREED,
  a reason and the score difference) is printed in chat and stored in `lastRolls`.
- **Tooltips**: every gear tooltip (bags, quest rewards, vendors, chat links) gets one line:
  - `TrailScout: +12.3 vs equipped (score 45.1)`: green above +0.5, red below -0.5, gray in
    between; adds `needs level N` when the item requires a higher level.
  - `TrailScout: equipped, score N` on the item you are wearing.
  - `TrailScout: not for you (...)` on gear your class cannot use.
  - No line on non-gear items (materials, ammo, bags, shirts). Comparison tooltips are left
    alone.

## Copy box

`/scout` shows a one-line summary: level, XP, rested XP, gold, location, hearthstone, free bag
slots, durability, buffs, pet, party, online friends, quests with objectives, bags and
equipment. The box is one line wide, so it only shows the start of the text; a line above it
says what it is and how long. The text is already selected: press Ctrl+C to copy it (the box
closes) or Esc to close it. The summary is always
in English, whatever the client language, since it is meant for an AI chat.

## Languages

Everything the addon shows follows the game client: chat messages, alerts, tooltip lines,
the settings and help window and the addon list note are in Spanish on esMX and esES, and in
English everywhere else. The Spanish is neutral Latin American. Names of quests, items, NPCs
and zones are never translated by the addon: they come from the client, so they are already
in your language. Translations live in the `L` table at the top of `TrailScout.lua`; the
TOC carries `Notes-esMX` and `Notes-esES`.

The offline tools follow the same client language, read from the snapshot: on a Spanish
client they show names as `English / Spanish` (you see the Spanish one in game, most guides
use the English one), and on any other client the English name alone. They support English
and Spanish clients; another language would show English names and miss objective progress.

## For developers

In the author's setup the game's `Interface/AddOns/TrailScout` folder is a symlink to this
directory.

Formerly called **FeliExport**, then **ForeverScout** (renamed because another addon on
CurseForge already has that name). The game keeps addon data in a file named after the addon,
so after each rename every character starts a new `SavedVariables/TrailScout.lua`, and
in-game settings such as your stat weights start fresh. The offline tools still read the older
`ForeverScout.lua` and `FeliExport.lua` and merge their history (deaths, dungeon runs,
level-ups, flight paths, recipes) with the new one, so nothing recorded before is lost. A
`ForeverScout.lua` written by the other addon of that name is recognised and ignored.
