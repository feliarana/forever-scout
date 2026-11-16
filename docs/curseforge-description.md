**ForeverScout** takes a snapshot of your character so an AI assistant can plan your next steps with you: quests with objectives, gear, bags, talents, professions, party and online friends. It works for every class and faction on **World of Warcraft: Forever**.

## What you get in game

- **`/scout`** — a summary of your character in a copy box. Press Ctrl+C and paste it into any AI chat together with your question.
- **`/whereis <name>`** — finds an NPC or an object in the world: how far it is, an arrow to it and a **[Show on map]** link. It also follows a party member.
- **`/scout route`** — walks a route stop by stop with waypoints, objectives first and turn-ins last (routes come from the offline tools).
- **Reminders** — nearly full bags, low durability, unspent talent points. Hunters also get low ammo and a dead, missing or unhappy pet.
- **Loot advice** — NEED or GREED on every roll, and a score line on gear tooltips against what you wear. Hunters have built-in stat weights; every other class sets its own with `/scout weights`.
- **`/scout help`** — every command, in English or Spanish to match your client.

## Quick start

1. Install the addon and log in. Chat shows `ForeverScout: loaded. Type /scout help`.
2. Type `/scout`, press Ctrl+C in the box that opens, and paste the line into your AI chat with a question like *"what should I do next?"*.

## Going further

`/reload` writes the full snapshot to disk. The free tools in the [forever-scout repository](https://github.com/feliarana/forever-scout) read it together with your installed Questie database and tell an AI assistant where every quest objective and turn-in is, what is on your way, what to sell, where your talent and legacy points can go and which route to take. That part needs Python and is optional.

## Good to know

- **Questie and TomTom are optional.** `/whereis` needs Questie, and TomTom adds the arrow. `/scout route` needs TomTom. Everything else works without them.
- **Privacy:** the snapshot and the copy box include the names of party members, friends, guild and communities. Nothing leaves your computer unless you paste or share it.
- **It does not play for you.** It only reads what any addon can read and shows you information.
- The game only saves addon data on `/reload` or logout, so the full snapshot needs a `/reload`.
- Messages are in Spanish on esMX / esES clients and in English everywhere else.

Source, issues and the offline tools: [github.com/feliarana/forever-scout](https://github.com/feliarana/forever-scout). MIT license.
