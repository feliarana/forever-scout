# FeliExport

In-game addon for WoW Forever (Interface 16001). It saves a per-character snapshot to
SavedVariables for the offline tools in `tools/`, gives loot advice in chat, and points a
TomTom arrow at NPCs or party members.

The game's `Interface/AddOns/FeliExport` folder is a symlink to this directory.

## Requirements

- Required: none.
- Optional: **Questie** (NPC spawn data for `/donde`) and **TomTom** (arrow and live distance
  for `/donde`). Both are listed in `## OptionalDeps`, so they load first when enabled.

## Slash commands

| Command | What it does |
|---|---|
| `/wow [question]` (alias `/feli`) | Builds the snapshot now and opens a copy box with a one-line summary to paste into a chat. The optional question is stored in the snapshot. Type `/reload` afterwards to write the full snapshot to disk. |
| `/wow <shift-clicked item link>` | Instant NEED / GREED verdict for that item against what is equipped. |
| `/donde <npc name>` (alias `/where`) | TomTom arrow to the nearest spawn of the NPC, with distance in yards and meters. Partial names work and accents are optional (`jabali` matches `Jabalí`). With several matches the nearest spawn wins and the others are listed with their IDs. |
| `/donde <npc id>` | Same, by NPC ID. |
| `/donde` | Same, for the NPC currently targeted (`/target jabalí`, then `/donde`). |
| `/donde <party member>` | Arrow that follows a party member's live position (refreshed every 2 seconds). |
| `/donde off` (or `clear`) | Clears the arrow. |

Limits of `/donde`:

- The arrow points at the spawn point from Questie's database, not at the live mob: the
  client does not expose NPC positions.
- Players outside the party cannot be located: the client only gives party member positions.
  For friends outside the party, the snapshot records their zone (see `onlineFriends`).
- A failed search keeps the current arrow.

## Snapshot

WoW only writes SavedVariables to disk on `/reload`, logout or character switch. The addon
rebuilds the snapshot 5 seconds after login and every 20 seconds after that, so a plain
`/reload` always writes current data. A snapshot taken while logging out (unit data already
torn down) never overwrites a good one.

Each section is built on its own: an API that fails only empties its section, and the error
is stored under `errors`.

`FeliExportDB` (per character, replaced on every snapshot):

| Key | Content |
|---|---|
| `savedAt`, `question`, `locale` | Snapshot time, optional `/wow` question, client locale |
| `name`, `realm`, `class`, `race`, `faction`, `level` | Identity, with non-localized class/race tokens for quest filtering |
| `xp`, `xpMax`, `rested`, `money`, `healthMax` | Progress and gold. Current health is a protected value on this client, so only the maximum is kept |
| `location` | Zone, subzone, map ID, map name and x,y in percent |
| `instance`, `currentRun` | Current instance and the dungeon run in progress (XP so far) |
| `party` | Party members: name, class, level, online flag, map ID, map name and x,y |
| `onlineFriends` | Online friends from the friend list, Battle.net friends playing WoW, and the guild: name, level, class, zone, realm and source (`friend`, `bnet`, `guild`) |
| `pvpFlagged`, `target` | PvP flag and the current target |
| `quests`, `completedQuests` | Quest log with objectives, and completed quest IDs |
| `equipment`, `bags` | Equipped items and bag contents, with stats |
| `skills`, `recipes` | Professions and the recipes seen in each profession window |
| `talents`, `unspentTalentPoints` | Full talent trees (trait system, classic API as fallback) |
| `spellbook`, `actionBars` | Known spells with rank, and what sits in each action slot |
| `pet` | Name, family, level, XP and happiness |
| `hearth` | Hearthstone bind location and cooldown left |
| `upkeep` | Free bag slots and durability |
| `flights` | Known flight paths (recorded whenever the flight map opens) |
| `buffs`, `debuffs` | Active auras with stacks and time left |
| `lastQuestWindow`, `lastTrainer`, `lastMerchant` | Last quest reward window, trainer and vendor opened, with items and costs |
| `lastRolls` | Last 10 loot roll verdicts |
| `apiDiagnostics` | Which APIs exist on the client; only collected while talents or skills come back empty |
| `errors` | Error message per failed section |

`FeliExportHistory` (per character, kept across sessions): running XP total, level-ups with
date and zone, deaths with place and level (killer taken from a hostile target, best effort),
dungeon runs with XP gained, flight paths and recipes.

Values from roster APIs can be restricted ("secret") on this client. Storing one in
SavedVariables triggers the blocked-action dialog, so the addon drops any value that fails a
comparison inside `pcall`.

## Loot advisor

When a loot roll starts (or on `/wow <item link>`), the item is scored with the RestedXP
hunter weights (levels 20-29) and compared to the equipped item in that slot. The verdict
(NEED or GREED, a reason and the score difference) is printed in chat and stored in
`lastRolls`.

## Copy box

`/wow` shows a one-line summary: level, XP, rested XP, gold, location, hearthstone, free bag
slots, durability, buffs, pet, party, online friends, quests with objectives, bags and
equipment. Press Ctrl+C to copy it (the box closes) or Esc to close it.
