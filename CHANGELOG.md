# Changelog

Newest version first. The section of a version is what goes in the changelog box when its zip
is uploaded to CurseForge.

## TrailScout 1.5.0

First public release. Works with any class and faction on World of Warcraft: Forever.

Before this release the addon was called ForeverScout. It was renamed because another addon
on CurseForge already has that name. If you had the earlier version: delete the old
`Interface/AddOns/ForeverScout` folder and install `TrailScout`. The game keeps addon data
per addon name, so in-game settings (your stat weights, the alerts switch) start fresh; the
offline tools still read the history saved under the old name.

### Ask an AI about your character
- `/scout` opens a box with a summary of your character (level, zone, quests with progress, bags, gear, party, friends online). Press Ctrl+C and paste it into any AI chat.
- `/scout <question>` includes your question in the summary.
- `/reload` writes the full snapshot to disk for the optional offline tools.

### Find things
- `/whereis <name>` finds an NPC or a world object: distance, a TomTom arrow and a clickable **[Show on map]** link. Works without TomTom too (no arrow).
- `/whereis <party member>` follows a party member live.
- `/whereis map` opens the map on the last result again.

### Routes
- `/scout route` walks a route stop by stop with TomTom waypoints. `/scout route next` moves on, `/scout route clear` removes it. The current stop survives a `/reload`.

### Loot advice
- NEED or GREED in chat on every loot roll, and a score line on gear tooltips against what you wear.
- Hunters have built-in stat weights. Every other class sets its own with `/scout weights`.

### Reminders
- Bags almost full, low durability, unspent talent points.
- Hunters: low ammo, and a dead, missing or unhappy pet.
- `/scout alerts on|off`.

### Snapshot contents
- Quests with objectives, quest log size, gear and bags with stats, professions and known recipes.
- Talents with the game's own descriptions and where a point can go.
- Legacy perk trees and unspent legacy points.
- Pet happiness, loyalty and diet.
- XP pace, deaths, dungeon runs, known flight paths.

### Other
- `/scout help` explains every command.
- English and Spanish (esMX, esES), following your game client.
- `/scout addons` lists addons you have that do the same job twice.
- Questie and TomTom are optional: only `/whereis` and `/scout route` use them.

### Known limits
- Tested on one setup so far (hunter, Spanish client). Reports are welcome on the GitHub issues page.
- Players outside your party cannot be located: the game does not give addons their position.
- Bank and mail are only read by the offline tools, and need the Syndicator addon.
