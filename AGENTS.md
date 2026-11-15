# forever-claude — guide for AI assistants

You are helping a WoW Forever player use this toolkit: the in-game addon ForeverScout plus the
offline Python tools that read its snapshot. `CLAUDE.md` holds the repo author's personal rules
(their character, professions, routes). When your user is someone else, this file replaces it.

`README.md` is the source of truth for commands, paths and features; this file says what to do
and in which order. The addon's own reference (slash commands, snapshot fields, alerts) is
`addon/ForeverScout/README.md`.

## First session: onboarding

Work through these steps in order. Each ends on a check you can verify; move on only when it
passes.

1. **Player profile.** Ask the player for: main character name, class, race, faction, realm
   type (PvP or normal), professions, game client language, the folder of the game
   (`_forever_`, holding `Interface/` and `WTF/`), operating system, and whether they level
   with friends. Write the answers to `PLAYER.md` at the repo root (git-ignored, personal).
   Done when `PLAYER.md` exists with every field filled.
2. **Addon.** Guide the player through README → *Install → 1. The addon* for their operating
   system, including Questie (Forever version) and TomTom. Done when the player confirms that
   ForeverScout is enabled in game and they ran `/reload` with their main character.
3. **Tools.** Guide README → *Install → 2. The offline tools*, with `WOW_DIR` set to their game
   folder. Prefer setting `WOW_DIR` in the environment over editing `config.py`, which holds
   the author's defaults. Done when `tools/analyze.py` prints their own character name and a
   snapshot time from today.
4. **Tour.** Show the player what works for their class (README → *What works for each
   class*) and the in-game commands they will use most: `/wow`, `/reload`, `/donde`,
   `/wow alerts`. Done when the player has tried `/donde` on one NPC.

## Every session: "read"

When the player asks you to read their state (or to plan their next steps):

1. Read `PLAYER.md`. Run `tools/analyze.py` (add `--char NAME` when they play an alt). If the
   snapshot is older than 30 minutes, ask for a `/reload` before planning.
2. Before planning, check the snapshot for: friends online and where they are, rested XP,
   unspent talent points, bag space, durability, and the NPC and location of every quest
   ready to turn in.
3. Before telling them to skip or abandon a quest, run `tools/route_check.py` with their
   planned route. A quest whose objectives sit on the route gets done on the way.
4. Use `tools/guide.py <questID>` for quest details and `tools/inventory.py` for what to sell,
   auction or keep.
5. Look up game facts (quest rewards, item stats, zones) in current WoW Forever sources and
   say which ones you could not verify. Forever changes Classic in places, so Classic data is
   a fallback, labelled as such.

Answer in the player's language. Name quests, NPCs and zones as their game client shows them,
with the English name beside it.

## Class notes

The loot advisor, the tooltip score and the ammo and pet alerts use hunter stat weights and
run only for hunters (`STAT_WEIGHTS` in `config.py`, `WEIGHTS` in
`addon/ForeverScout/ForeverScout.lua`). For any other class, judge gear upgrades yourself from the
item stats in the snapshot, using current stat priorities for that class and spec.

## Changing the repo

Write code, comments, script output and docs in English. Keep `CLAUDE.md` as it is: it belongs
to the author. Personal settings go in `PLAYER.md` or environment variables, never in tracked
files.
