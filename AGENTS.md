# forever-scout — guide for AI assistants

This file is for any AI agent (Claude Code, Codex, Cursor, Gemini CLI, Copilot…) opened on
this folder. You are helping a WoW Forever player use this toolkit: the in-game addon
ForeverScout plus the offline Python tools that read its snapshot. You need to be able to read
files and run commands here; if you cannot, say so and fall back to the `/scout` copy box
(README → *Your first five minutes*).

Every player has a private `PLAYER.md` at the repo root (git-ignored): their character,
professions, language and any personal rules. Read it at the start of every session and
follow it; where it differs from this file, `PLAYER.md` wins. When it does not exist, this is
a new player: start with the onboarding below. `CLAUDE.md` only points Claude Code at these
two files.

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
2. **Addon.** Guide the player through README → *Install* for their operating
   system, including Questie (Forever version) and TomTom. Done when the player confirms that
   ForeverScout is enabled in game and they ran `/reload` with their main character.
3. **Tools.** Guide README → *Install the offline tools*, with `WOW_DIR` set to their game
   folder. Prefer setting `WOW_DIR` in the environment over editing `config.py`, which holds
   the author's defaults. Done when `tools/analyze.py` prints their own character name and a
   snapshot time from today.
4. **Tour.** Show the player what works for their class (README → *What works for each
   class*) and the in-game commands they will use most: `/scout`, `/reload`, `/whereis`,
   `/scout alerts`. Done when the player has tried `/whereis` on one NPC.

## Every session: "read"

The player's cue is a single word, **"read"** ("lee", "lê", "lis"... in their language),
usually right after a `/reload` in game. Treat it, and any request to plan their next steps,
as this routine:

1. Read `PLAYER.md`. Run `tools/analyze.py` (add `--char NAME` when they play an alt). If the
   snapshot is older than 30 minutes, ask for a `/reload` before planning.
2. Before planning, check the snapshot for: friends online and where they are (never plan
   around someone offline or far away), rested XP, and the NPC and location of every quest
   ready to turn in so none gets lost.
3. Read the *Bank, mail and other characters* section: quest items the player already owns
   away from their bags save a farming stop (plan the bank or mailbox visit instead), and mail
   close to expiring has to be collected. When the section says there is no data, the
   player lacks the Syndicator addon: say what they would gain by installing it.
4. Check upkeep and say what needs attention: the right weapon equipped and upgrades sitting
   in bags, free bag slots, durability, unspent talent or legacy points, professions close
   to their cap, and for hunters ammo, pet food and pet level. For points and professions
   follow *Talents, legacy points and professions* below.
5. In the next steps, remind the player of the buffs worth grabbing before leaving (food,
   campfire and camp buffs they own) and say whether the hearthstone is worth using: where it
   is bound and its cooldown are in the snapshot (`hearth`), and it pays off when the route
   ends far from the turn-ins.
6. Before telling them to skip or abandon a quest, run `tools/route_check.py` with their
   planned route. A quest whose objectives sit on the route gets done on the way.
7. When you propose a route, also draw it: if `WOW_AI_MAP_FILE` is set (a wow-ai chat), run
   `tools/map_route.py` with the quest IDs and waypoints of your plan; otherwise, for players
   with TomTom, run `tools/map_route.py --addon` and tell them to `/reload` and type
   `/scout route`.
8. Use `tools/guide.py <questID>` for quest details and `tools/inventory.py` for what to sell,
   auction or keep.
9. Look up game facts (quest rewards, item stats, zones) in current WoW Forever sources and
   say which ones you could not verify. Forever changes Classic in places, so Classic data is
   a fallback, labelled as such.

Answer in the player's language. Name quests, NPCs and zones as their game client shows them,
with the English name beside it.

## Talents, legacy points and professions

`tools/analyze.py` prints two sections for this, *Talents and perk trees* and *Professions*.
Turn them into advice for this player, not a generic build:

- **Class talents.** The snapshot has every talent with its rank, the game's own description
  and whether a point can go there now. Recommend from the player's class, spec and how they
  play (`PLAYER.md`: solo or grouped, PvP realm, leveling or endgame), and say which talent
  the next points should open. Forever changed talents from Classic: trust the descriptions
  in the snapshot over anything you remember, and look up a current Forever build before
  recommending a full path.
- **Legacy points.** Forever has account-wide Legacy perk trees (Professions, Adventure,
  Resourcefulness) with their own points, earned from Legacy Challenges and capped per
  character. When the snapshot has them (`traitSystems`), treat unspent points like unspent
  talents and pick perks that match the player's professions and goals: a skinner or crafter
  gets more from the Professions tree, a solo leveler from Adventure. When the snapshot does
  not have them, say so and ask the player how many legacy points they have and where they
  are spent; do not guess.
- **Professions.** Use the skill levels and the skill-up recipes to say what to do next: the
  next rank to train before hitting the cap, which known recipes still give skill-ups and
  what materials they need (check the bags with `tools/inventory.py`), and whether a
  gathering skill is behind the zone (skinning below the level of the mobs being killed).
  Tie it to the route: a trainer on the way is a stop worth adding.
- Rules labelled "Classic rule" in the output are Classic values not confirmed on Forever.
  Pass that label on.

## Tools

Run them with the repo virtualenv: `.venv/bin/python tools/<script>.py` (on Windows
`.venv\Scripts\python tools\<script>.py`). Zones accept an ID or a partial zone name in
English or the client language (`17`, `barrens`, `"Mil Agujas"`).

| Script | Purpose |
|---|---|
| `tools/analyze.py [--char NAME] [zone …]` | Character summary, where talent and perk points can go, professions, bank and mail, turn-ins, progress, unlocks, available quests |
| `tools/guide.py [--char NAME] <questID …>` | Start, turn-in, text, objectives with levels, ELITE and spawn clusters |
| `tools/route_check.py [--char NAME] ZONE:X,Y …` | Distance of each logged quest to a route, and XP at the current level |
| `tools/map_route.py [--char NAME] [--addon \| --tomtom] [QUESTID \| turnin:QUESTID \| ZONE:X,Y=label …]` | Numbered route for the in-game map (objectives first, turn-ins last); no stops = every quest in the current zone. `--addon` writes it for `/scout route`; writes to `$WOW_AI_MAP_FILE` when set |
| `tools/inventory.py [--all]` | Vendor / auction / use / keep / turn-in for every character's bags, bank and mail (Syndicator + Auctionator). Ask for an Auctionator full scan and a `/reload` when prices are stale. Keep list: `config.KEEP_ITEMS` |
| `tools/build_q.py` | Rebuild the `data/Q.pkl` cache from QuestieDB (the other tools do it when it is stale) |

## Class notes

Only hunters have built-in stat weights (`STAT_WEIGHTS` in `config.py`, `CLASS_WEIGHTS` in
`addon/ForeverScout/ForeverScout.lua`); the ammo and pet alerts are hunter-only too. For any
other class:

- In game, the loot advisor and the tooltip score stay off until the player sets weights.
  Look up current stat priorities for their class and spec, then give them one line to type,
  for example `/scout weights int=1 sp=0.8 sta=0.5 spi=0.4`. Say where the numbers came from.
- Offline, `analyze.py` skips the bag-upgrade check: judge upgrades yourself from the item
  stats in the snapshot.

## Changing the repo

Write code, comments, script output and docs in English. Personal settings and rules go in
`PLAYER.md` or environment variables, never in tracked files; `CLAUDE.md` stays a pointer to
this file and `PLAYER.md`.

After any change to `addon/ForeverScout/ForeverScout.lua`, run `npm test` (see README →
*Development*) before asking the player to `/reload`.
