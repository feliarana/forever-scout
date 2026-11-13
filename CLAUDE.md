# WoW Forever — rules

- Reply to the user in Rioplatense Spanish: direct and actionable. Everything written into this repo (code, comments, script output, docs) is in English.
- Everything is for a Horde troll hunter, Beast Mastery, on a PvP server: account for world PvP on every route.
- Professions: Skinning + Leatherworking; secondary First Aid, Cooking and Fishing.
- The game client is esMX: name quests, abilities, talents, zones and NPCs in English and Latin American Spanish ("Samophlange Manual / Manual del churumbele").
- I play with friends who level faster; I mostly level solo.
- Before stating game facts, look for 2026 sources. Everything for levels 31-60 comes from a beta that only went up to level 30: mark it as unverified.
- Code comments always in English.

## When I say "leé" (read)

1. Read the FeliExport snapshot live (paths in `config.py`). If it is old (`savedAt`), ask me for a /reload.
2. Run `tools/analyze.py` (and `tools/build_q.py` if `data/Q.pkl` does not exist or QuestieDB changed; the tools also rebuild it automatically).
3. Before planning:
   - Check whether my party friends are online and nearby, and how much rested XP I really have. Do not plan around an offline friend or rested XP that is not enough.
   - Check the NPC and location of every quest turn-in so none gets lost.
4. Before recommending to abandon or skip a quest, run `tools/route_check.py` with the route: if the objective is on the route, recommend doing it on the way without farming. Also weigh real XP at my level, where it is turned in, drop rate, elite or escort, reward, and whether it opens a better chain.
5. In the next steps, remind me which buffs to grab (campfire, Camping Tent / Tienda de campamento, food, Cozy Sleeping Bag / Saco de dormir acogedor, Warchief's Blessing / Bendición del Jefe de Guerra if I have it) and whether the hearthstone is worth it (location and cooldown in `hearth`) when the route ends far from the turn-ins.
6. Also check: gear (correct weapon equipped, upgrades in bags by the weights below), free bag slots, ammo, pet food, pet level and unspent talent points.

## Stat weights (RestedXP, hunter 20-29)

Ranged weapon DPS 14.0 · Agility 2.33 · Spirit 1.12 · Ranged Attack Power 0.80 · Stamina 0.75 · Intellect 0.55 · Strength 0.20 · Armor 0.035.

## Guide

`guide/guia-leveleo-cazador-troll.md` is the source for the route, quests and talents. Read it before answering and propose changes when something does not match the data. Pending: in the talent table, Summon Hawk / Invocar halcón goes at 28 (not 27) because there are 3 points in Hawk Eye / Ojo de halcón.

## Tools

Run with the repo virtualenv: `.venv/bin/python tools/<script>.py`.

| Script | Purpose |
|---|---|
| `tools/build_q.py` | Build `data/Q.pkl` from QuestieDB + real Forever XP |
| `tools/analyze.py [zone …]` | Character summary, turn-ins, progress, unlocks, available quests |
| `tools/guide.py <questID …>` | Start, turn-in, text, objectives with levels, ELITE and spawn clusters |
| `tools/route_check.py ZONE:X,Y …` | Distance of each logged quest to a route + XP at current level |

Zones accept an ID or a partial English/esMX name (`17`, `barrens`, `"Mil Agujas"`).
