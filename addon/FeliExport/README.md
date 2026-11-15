# FeliExport

In-game addon for WoW Forever (Interface 16001). It saves a per-character snapshot to
SavedVariables for the offline tools in `tools/`, gives loot advice in chat, warns about ammo,
pet, bags and durability, and points a TomTom arrow at NPCs or party members.

The game's `Interface/AddOns/FeliExport` folder is a symlink to this directory.

## Requirements

- Required: none.
- Optional: **Questie** (NPC spawn data for `/donde`) and **TomTom** (arrow and live distance
  for `/donde`). Both are listed in `## OptionalDeps`, so they load first when enabled.

## Slash commands

| Command | What it does |
|---|---|
| `/wow [question]` (alias `/feli`) | Builds the snapshot now and opens a copy box with a one-line summary to paste into a chat. The optional question is stored in the snapshot. Type `/reload` afterwards to write the full snapshot to disk. |
| `/wow addons` | Lists loaded addons that do the same job (bags, damage meters, action bars, quest auto-accept, map coordinates, fast loot, vendor prices…). Leatrix Plus and ElvUI only clash if the matching option is on. |
| `/wow alerts` | Shows the upkeep alert thresholds and runs a check now. |
| `/wow alerts off` / `/wow alerts on` | Mutes or re-enables upkeep alerts (saved per character). |
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
| `onlineFriends` | Online friends from the friend list, Battle.net friends playing WoW, the guild and communities: name, level, class, zone, realm and source (`friend`, `bnet`, `guild`, `community`) |
| `guild` | Guild name, own rank and rank index, members and members online; absent when not in a guild |
| `communities` | Every subscribed community except the guild: name, type (`bnet`, `wow`, `other`), member count and online members with level, class and zone |
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
| `addons` | Loaded addon names, installed count and overlapping groups |
| `apiDiagnostics` | Which APIs exist on the client; only collected while talents or skills come back empty |
| `errors` | Error message per failed section |

`FeliExportHistory` (per character, kept across sessions): running XP total, level-ups with
date and zone, deaths with place and level (killer taken from a hostile target, best effort),
dungeon runs with XP gained, flight paths, recipes and the upkeep alert setting (`alerts`).

Values from roster APIs can be restricted ("secret") on this client. Storing one in
SavedVariables triggers the blocked-action dialog, so the addon drops any value that fails a
comparison inside `pcall`.

## Upkeep alerts

A warning in the middle of the screen, the raid warning sound and a chat line when something
needs attention. Each alert fires when its condition starts and repeats every 5 minutes while
it lasts. Checks run a second after bag, pet, durability, combat-end and resting changes, and
every 20 seconds.

| Alert | Condition | Message hint |
|---|---|---|
| Low ammo (hunter) | Equipped ammo below 400 | Equip the bigger stack of other ammo if there is one, else buy more |
| No ammo (hunter) | No ammo equipped | Drag arrows to the ammo slot, or buy them |
| Pet dead (hunter) | Pet is dead, out of combat | Revive Pet |
| Pet unhappy (hunter) | Happiness 1 (75% damage, may run away) | Feed Pet now |
| Pet content (hunter) | Happiness 2, out of combat | Feed Pet for +25% damage |
| No pet (hunter, level 10+) | No pet out, out of combat, not resting, mounted or flying | Call Pet |
| Bags almost full | 2 free bag slots or fewer | — |
| Low durability | Any equipped item below 25% | Repair |

Ammo is counted from the bag stacks (quiver included), since the ammo slot only references
them. Thresholds live in `ALERT_LIMITS` in `FeliExport.lua`.

## Loot advisor and tooltip score

Hunters only: the weights and the usable-gear rules are for hunters, so other classes get
no roll advice and no tooltip line.

Items are scored with the RestedXP hunter weights (levels 20-29: ranged DPS 14, agility 2.33,
spirit 1.12, attack power 0.8, stamina 0.75, intellect 0.55, strength 0.2, armor 0.035) and
compared to the equipped item in the same slot. For rings and trinkets the weaker equipped one
is the comparison; a two-hander is compared to main hand plus off hand.

- **Loot rolls**: when a roll starts (or on `/wow <item link>`), the verdict (NEED or GREED,
  a reason and the score difference) is printed in chat and stored in `lastRolls`.
- **Tooltips**: every gear tooltip (bags, quest rewards, vendors, chat links) gets one line,
  for hunters only:
  - `FeliExport: +12.3 vs equipped (score 45.1)`: green above +0.5, red below -0.5, gray in
    between; adds `needs level N` when the item requires a higher level.
  - `FeliExport: equipped, score N` on the item you are wearing.
  - `FeliExport: not for you (...)` on plate, shields, mail before 40 and weapons hunters
    cannot use.
  - No line on non-gear items (materials, ammo, bags, shirts). Comparison tooltips are left
    alone.

## Copy box

`/wow` shows a one-line summary: level, XP, rested XP, gold, location, hearthstone, free bag
slots, durability, buffs, pet, party, online friends, quests with objectives, bags and
equipment. Press Ctrl+C to copy it (the box closes) or Esc to close it.
