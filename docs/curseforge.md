# CurseForge listing

Texts for the ForeverScout project page. The logo is `assets/logo-400.png`
(`assets/make_logo.py` redraws it).

## Create-project form

| Field | Value |
|---|---|
| Project name | Forever Scout |
| Logo | `assets/logo-400.png` |
| Summary | Character snapshot for AI assistants, plus NPC arrows, route waypoints, upkeep alerts and loot advice. |
| Main category | Quests & Leveling |
| Additional categories | Map & Minimap, Data Export, Tooltip |
| Allow comments | yes |
| Unlisted | yes until friends have tested it, then listed |
| Social links | Source: https://github.com/feliarana/forever-scout |

Optional dependencies to declare on the page: Questie and TomTom (only `/whereis` and
`/scout route` use them).

## Description

**ForeverScout** takes a snapshot of your character so an AI assistant can plan your next
steps with you: quests with objectives, gear, bags, talents, professions, party and online
friends. It works for every class and faction on **World of Warcraft: Forever**.

### What you get in game

- **`/scout`** — a one-line summary of your character in a copy box. Press Ctrl+C and paste it
  into any AI chat together with your question.
- **`/whereis <npc>`** — an arrow to the nearest spawn of an NPC, or to a party member (needs
  Questie and TomTom).
- **`/scout route`** — walks a route stop by stop with TomTom waypoints (routes come from the
  offline tools).
- **Alerts** — nearly full bags, low durability, unspent talent points; for hunters also low
  ammo and a dead or missing pet.
- **Loot advice** — NEED or GREED on every roll, and a score line on gear tooltips, against
  what you wear. Hunters have built-in stat weights; every other class sets its own with
  `/scout weights`.
- **`/scout help`** — every command, in English or Spanish to match your client.

### Quick start

1. Install the addon and log in. Chat shows `ForeverScout: loaded. Type /scout help`.
2. Type `/scout`, press Ctrl+C in the box that opens, and paste the line into your AI chat
   with a question like *"what should I do next?"*.

### Going further

`/reload` writes the full snapshot to disk. The free tools in the
[forever-scout repository](https://github.com/feliarana/forever-scout) read it together with
your installed Questie database and tell an AI assistant where every quest objective and
turn-in is, what is on your way, what to sell and which route to take. That part needs
Python and is optional.

### Good to know

- Questie and TomTom are optional. Without them everything except `/whereis` and `/scout route`
  works.
- The snapshot and the copy box include the names of party members, friends, guild and
  communities. Nothing leaves your computer unless you paste or share it.
- The game only saves addon data on `/reload` or logout, so the full snapshot needs a
  `/reload`.
- Messages are in Spanish on esMX / esES clients and in English everywhere else.
