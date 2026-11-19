# Changelog

Newest version first. The section of a version is what goes in the changelog box when its zip
is uploaded to CurseForge.

## TrailScout 1.10.0

- New reminders for the classes that carry supplies: warlocks (Soul Shards), shamans (Ankh), mages (runes, Arcane Powder, Light Feather), priests (candles, Light Feather), druids (seeds, Wild Berries, Wild Thornroot), paladins (Symbols) and rogues (Flash Powder, Blinding Powder). You are told once when one runs low and once when it runs out.
- Only a supply your character has carried in the last week is watched, so nothing warns about a spell you have not learned or a reagent you no longer need. The switch is shared with the hunter's ammo reminder on the Settings page.
- A question you type yourself that mentions talents now brings the list of talents that can take a point, like the ready-made talent question does.

## TrailScout 1.9.0

- The summary you paste into an AI chat now says your race, class and faction, and lists the talents and perks you have taken.
- Asking "Where do my talent points go?" adds every talent that can take a point, with the game's own description, so the AI can answer without reading any file. The same list is added whenever you have a talent or legacy point to spend.
- Offline tools: a quest item that is bought, not looted, now shows who sells it near you (`tools/guide.py`) and becomes a "Buy ..." stop on the route (`tools/map_route.py`). It used to be listed as "no known spawns".
- Offline tools: opening one profession window no longer hides the recipes recorded earlier for your other professions.

## TrailScout 1.8.1

- `/whereis` on your target and the record of who gave you each quest no longer depend on the hidden parts of an NPC's identifier being plain numbers. Forever scrambles those parts, which could make both fail without a message.

## TrailScout 1.8.0

- Loot advice now works for every class out of the box. Warriors, paladins, rogues, priests, shamans, mages, warlocks and druids get their own stat weights, so NEED or GREED on rolls and the score line on tooltips appear without setting anything up.
- Classes with more than one job pick a role: damage, healer or tank. Use the new buttons on the Settings page or type `/scout weights healer` (`tank`, `melee`, `caster`).
- Spell critical strike and spell hit are now scored (`spellcrit`, `spellhit` in `/scout weights`).
- The new weights are TrailScout's own estimates for leveling, worked out from Classic's rules and not yet checked against Forever's changes. Hunters keep theirs. You can still tune any number with `/scout weights`.
- The floating button now sits above quest trackers and bag bars, so it can be clicked and dragged when it is next to one.

## TrailScout 1.7.0

- Routes from an AI chat, with no extra tools: the new question **Plan a route for me** asks the assistant to end its answer with one line that starts with `TSR1`. Paste that line into the new box on the Start page (or type `/scout import <line>`) and the route starts, with a waypoint per stop.
- The game places the stops itself from Questie's data: one stop for each place a quest's open objectives send you to (drops, objects and vendors), where it is turned in, or any NPC or object by name. Objectives you already finished are skipped, and stops that cannot be placed are listed in chat instead of failing the whole route.
- Stops in a row at the same place (several turn-ins in one town) are merged into one stop.
- The summary now carries the number of the map you are on, so a route can also name a plain place by coordinates.
- A **Clear route** button beside the route box takes the waypoints off the map.
- An imported route is kept across `/reload`. When the offline tools write a newer route, that one is used.

## TrailScout 1.6.1

- A floating TrailScout button that you can drag anywhere on screen, besides the one on the minimap. Each has its own switch in Settings.
- Window layout fixes: no button runs past the edge any more, and the stat weights line is full width and shown from its start.

## TrailScout 1.6.0

- New TrailScout window: click the button on the minimap. It opens by itself the first time you log in with a character, so nothing has to be typed.
- Start page: six ready-made questions for an AI (what to do next, quests to do or skip, talents, what to sell, gear in your bags, stat weights for your class) and a box for your own. One click copies the summary with the question in it, in your language.
- Start page: a search box to find NPCs, objects and party members, with Show on map and Clear arrow.
- Settings page: switch each reminder on or off (bags, durability, talent points, ammo, pet), the loot roll advice, the tooltip score line and the minimap button; edit your stat weights in place; buttons to copy the summary, start or clear a route and check your addons.
- Help page: every feature explained, with its commands. `/scout guide` opens it directly.
- The minimap button can be dragged around the minimap; right-click opens the copy box.
- Spanish is now neutral Latin American, and covers everything: the new window, the addon list note and the `/scout addons` categories.

## TrailScout 1.5.2

- The snapshot now includes the size of every zone in yards, measured from the game client. The offline tools use it to estimate walking time and rank your quests by XP per minute.

## TrailScout 1.5.1

- The snapshot now records what the game client itself says each quest in your log pays in XP at your level. This covers Forever's new quests, which quest databases do not have yet.
- It also remembers who gave you each quest and where you were when you accepted it.

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
