# ForeverScout

In-game addon for WoW Forever (Interface 16001), for any class and faction.

ForeverScout takes a snapshot of your character (quests, gear, bags, talents, professions,
party and online friends) so an AI assistant can read it and plan your next steps with you.
On its own it also points an arrow at NPCs and party members, warns you about full bags, low
durability and unspent talent points, and scores gear against what you wear.

## Quick start

1. Copy the `ForeverScout` folder into the game's `_forever_/Interface/AddOns/`, enable it in
   the AddOns list and log in. Chat shows `ForeverScout: loaded. Type /scout help...` the first
   time.
2. Type `/scout help` for the list of commands, in English or Spanish to match your client.
3. To ask an AI about your character, pick one:
   - **Quick, no setup:** type `/scout`, press Ctrl+C in the box that opens and paste the line
     into any AI chat with your question.
   - **Full detail:** type `/reload` so the game writes the whole snapshot to disk, then let
     an AI assistant read it with the offline tools from the
     [forever-scout repository](https://github.com/feliarana/forever-scout) (needs Python).

The game only writes addon data to disk on `/reload`, logout or character switch. That is why
the full snapshot needs a `/reload`.

### What works for your class

| Feature | Hunter | Other classes |
|---|---|---|
| Snapshot, copy box, session history, XP pace | yes | yes |
| `/whereis` for NPCs, objects and party members | yes | yes |
| `/scout route` waypoints from the offline tools | yes | yes |
| Alerts: bags, durability, unspent talent points | yes | yes |
| Alerts: ammo and pet | yes | — |
| Loot NEED / GREED advice and tooltip score | yes, built-in weights | after you set your stat weights with `/scout weights` |

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
required dependency would stop ForeverScout from loading at all without them.

## Slash commands

| Command | What it does |
|---|---|
| `/scout [question]` (older aliases `/wow`, `/feli`) | Builds the snapshot now and opens a copy box with a one-line summary to paste into a chat. The optional question is stored in the snapshot. Type `/reload` afterwards to write the full snapshot to disk. |
| `/scout addons` | Lists loaded addons that do the same job (bags, damage meters, action bars, quest auto-accept, map coordinates, fast loot, vendor prices…). Leatrix Plus and ElvUI only clash if the matching option is on. |
| `/scout alerts` | Shows the upkeep alert thresholds and runs a check now. |
| `/scout alerts off` / `/scout alerts on` | Mutes or re-enables upkeep alerts (saved per character). |
| `/scout <shift-clicked item link>` | Instant NEED / GREED verdict for that item against what is equipped. |
| `/scout route` (or `ruta`) | Walks the route written by `tools/map_route.py --addon`: one TomTom waypoint per stop, arrow on the current one. Carries on from the saved stop after a `/reload`. |
| `/scout route next` / `/scout route <n>` / `/scout route clear` | Move to the next stop, jump to stop n, or remove the route's waypoints. |
| `/scout help` (or `?`, `ayuda`) | What the addon does and every command. |
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

## Routes

`/scout route` walks a route made outside the game by `tools/map_route.py --addon` (from the
[forever-scout repository](https://github.com/feliarana/forever-scout)). The tool writes the
stops into `Route.lua` in this folder; the game reads that file on every `/reload`, and chat
says `new route loaded` when there is one. Needs TomTom.

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

`ForeverScoutDB` (per character, replaced on every snapshot):

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
| `quests`, `completedQuests` | Quest log with objectives, and completed quest IDs |
| `questLog` | Quests in the log (`count`) and the log cap (`max`, absent when the client does not report it) |
| `pace` | XP pacing: session start, seconds and XP, `xpPerHour` for the session and `recentXPPerHour` over about the last hour. A session survives `/reload` and ends after 30 minutes without a snapshot; rates appear after 5 minutes |
| `equipment`, `bags` | Equipped items and bag contents, with stats |
| `skills`, `recipes` | Professions and the recipes seen in each profession window, each recipe filed under the profession it belongs to |
| `talents`, `unspentTalentPoints` | Full talent trees (trait system, classic API as fallback). Trait nodes carry `desc` (the game's description), `open` (prerequisites met) and `canBuy` (a point can be spent on it now) |
| `traitSystems`, `traitApi` | Every other trait system the client exposes, such as the Legacy perk trees, in the same shape as `talents`. While none is found, `traitApi` lists the client's trait-related API names so the gap can be diagnosed |
| `spellbook`, `actionBars` | Known spells with rank, and what sits in each action slot |
| `pet` | Name, family, level, XP, happiness (1 unhappy, 2 content, 3 happy) with its damage percentage, loyalty and the food types it eats |
| `hearth` | Hearthstone bind location and cooldown left |
| `upkeep` | Free bag slots and durability |
| `flights` | Known flight paths (recorded whenever the flight map opens) |
| `buffs`, `debuffs` | Active auras with stacks and time left |
| `lastQuestWindow`, `lastTrainer`, `lastMerchant` | Last quest reward window, trainer and vendor opened, with items and costs |
| `lastRolls` | Last 10 loot roll verdicts |
| `addons` | Loaded addon names, installed count and overlapping groups |
| `apiDiagnostics` | Which APIs exist on the client; only collected while talents or skills come back empty |
| `errors` | Error message per failed section |

`ForeverScoutHistory` (per character, kept across sessions): running XP total, level-ups with
date and zone, deaths with place and level (killer taken from a hostile target, best effort; left empty when unknown),
dungeon runs with XP gained, flight paths, recipes, the XP pacing session (`pace`), your own
stat weights (`weights`) and the upkeep alert setting (`alerts`).

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
them. Thresholds live in `ALERT_LIMITS` in `ForeverScout.lua`.

## Loot advisor and tooltip score

Items are scored with stat weights: each stat on the item is multiplied by its weight and the
total is compared to the equipped item in the same slot.

- **Hunters** get built-in weights (RestedXP, levels 20-29: ranged DPS 14, agility 2.33, spirit
  1.12, attack power 0.8, stamina 0.75, intellect 0.55, strength 0.2, armor 0.035).
- **Every other class** has no built-in weights yet, so there is no roll advice and no tooltip
  line until you set your own, for example `/scout weights int=1 sp=0.8 sta=0.5 spi=0.4`.
  Stats: `agi str sta int spi armor ap rap crit hit sp heal mp5 dps rdps` (`dps` is melee
  weapon DPS, `rdps` ranged weapon DPS). Weights are saved per character.

Gear your class cannot wear is flagged instead of scored: armor heavier than your class uses
(Classic rules, with the level 40 upgrade for warriors, paladins, hunters and shamans), shields
for classes without them, and for hunters weapons they cannot wield. Other classes have no
weapon list yet, so their weapons are always scored. For rings and trinkets the weaker equipped one
is the comparison; a two-hander is compared to main hand plus off hand.

- **Loot rolls**: when a roll starts (or on `/scout <item link>`), the verdict (NEED or GREED,
  a reason and the score difference) is printed in chat and stored in `lastRolls`.
- **Tooltips**: every gear tooltip (bags, quest rewards, vendors, chat links) gets one line:
  - `ForeverScout: +12.3 vs equipped (score 45.1)`: green above +0.5, red below -0.5, gray in
    between; adds `needs level N` when the item requires a higher level.
  - `ForeverScout: equipped, score N` on the item you are wearing.
  - `ForeverScout: not for you (...)` on gear your class cannot use.
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

Chat messages, alerts and tooltip lines follow the game client: Spanish on esMX and esES,
English everywhere else. Translations live in the `L` table at the top of `ForeverScout.lua`.

## For developers

In the author's setup the game's `Interface/AddOns/ForeverScout` folder is a symlink to this
directory.

Formerly called **FeliExport**. The game keeps addon data in a file named after the addon, so
after the rename each character starts a new `SavedVariables/ForeverScout.lua`. The offline
tools still read the old `FeliExport.lua` and merge its history (deaths, dungeon runs,
level-ups, flight paths, recipes) with the new one, so nothing recorded before is lost.
