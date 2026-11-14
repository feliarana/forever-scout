"""Character summary + quest planning from the live FeliExport snapshot.

Usage: analyze.py [--char NAME] [zoneID|zoneName ...]
  Zones default to the player's current zone plus its neighbors (config.NEIGHBORS).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import config  # noqa: E402
from common import (  # noqa: E402
    char_name, fits_character, fmt_loc, fmt_xp, is_horde_ok, load_known_taxis, load_q, load_snapshot, main_character, snapshots, take_char_arg, IDENTITY,
    dist, locate, money, player_pos, prereqs_met, quest_level, quest_name, resolve_zone,
    snapshot_age_minutes, xp_at_level, zone_name,
)

INVTYPE_SLOTS = {
    "INVTYPE_HEAD": [1], "INVTYPE_NECK": [2], "INVTYPE_SHOULDER": [3], "INVTYPE_BODY": [4],
    "INVTYPE_CHEST": [5], "INVTYPE_ROBE": [5], "INVTYPE_WAIST": [6], "INVTYPE_LEGS": [7],
    "INVTYPE_FEET": [8], "INVTYPE_WRIST": [9], "INVTYPE_HAND": [10], "INVTYPE_FINGER": [11, 12],
    "INVTYPE_TRINKET": [13, 14], "INVTYPE_CLOAK": [15], "INVTYPE_WEAPON": [16, 17],
    "INVTYPE_2HWEAPON": [16], "INVTYPE_WEAPONMAINHAND": [16], "INVTYPE_WEAPONOFFHAND": [17],
    "INVTYPE_HOLDABLE": [17], "INVTYPE_SHIELD": [17], "INVTYPE_RANGED": [18],
    "INVTYPE_RANGEDRIGHT": [18], "INVTYPE_THROWN": [18],
}
RANGED = {"INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN"}
# Armor a hunter cannot wear yet (mail unlocks at 40, plate never). Only used for hunters,
# the only class with stat weights so far.
BLOCKED_ARMOR = {"Placas", "Plate", "Escudos", "Shields"}
MAIL = {"Malla", "Mail"}
# Quest sort categories / zones that are not leveling content: holidays, AQ war effort,
# Children's Week, Darkmoon Faire, PvP commendations and battlegrounds.
SKIP_ZONES = {-22, -41, -284, -367, -364, -365, -366, -369, -370, -376, -1002, -1003, 2597, 3277, 3358}


def score(item, weights):
    stats = item.get("stats") or {}
    total = 0.0
    for key, weight in weights.items():
        if key == "dps" and item.get("slot") not in RANGED:
            continue
        total += (stats.get(key) or 0) * weight
    return total


def fmt_time(seconds):
    seconds = int(seconds or 0)
    if seconds >= 3600:
        return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"
    return f"{seconds // 60}m{seconds % 60:02d}s"


def as_slot_map(equipment):
    if isinstance(equipment, list):
        return {i + 1: v for i, v in enumerate(equipment)}
    return {int(k): v for k, v in (equipment or {}).items()}


def section(title):
    print(f"\n== {title} ==")


def character(Q, snap, hist):
    level = snap.get("level") or 0
    age = snapshot_age_minutes(snap)
    print(f"Snapshot {snap.get('savedAt')}" + (f" ({age:.0f} min ago)" if age is not None else ""))
    if age is not None and age > config.STALE_MINUTES:
        print(f"  !! Stale snapshot (> {config.STALE_MINUTES} min): run /wow or /reload")

    section("Character")
    xp, xp_max, rested = snap.get("xp") or 0, snap.get("xpMax") or 1, snap.get("rested") or 0
    print(f"{snap.get('name')} @ {snap.get('realm')} — level {level}, XP {xp}/{xp_max} "
          f"({xp / xp_max:.0%}), {xp_max - xp} to go")
    print(f"Rested: {rested} XP ({rested / xp_max:.0%} of the level) → the next {rested} XP from mobs "
          f"is doubled (quests do not use rested)")
    zid, x, y = player_pos(Q, snap)
    loc = snap.get("location") or {}
    print(f"Location: {loc.get('zone')} / {loc.get('subZone')} {x},{y} "
          f"(zone {zid}: {zone_name(Q, zid) if zid else '?'})")
    hearth = snap.get("hearth") or {}
    cd = hearth.get("cooldownLeft") or 0
    print(f"Hearthstone: {hearth.get('bind')} — " + ("ready" if cd <= 0 else f"cooldown {fmt_time(cd)}"))
    buffs = snap.get("buffs") or []
    if isinstance(buffs, dict):
        buffs = list(buffs.values())
    print("Buffs: " + (", ".join(f"{b.get('name')} ({fmt_time(b.get('left'))})" if b.get("left")
                                 else str(b.get("name")) for b in buffs) or "none"))
    debuffs = snap.get("debuffs") or []
    if debuffs:
        debuffs = list(debuffs.values()) if isinstance(debuffs, dict) else debuffs
        print("Debuffs: " + ", ".join(str(d.get("name")) for d in debuffs))
    up = snap.get("upkeep") or {}
    free = up.get("freeSlots")
    print(f"Gold: {money(snap.get('money'))} | Bags: {free} free of {up.get('totalSlots')}"
          f"{' !! FULL' if free is not None and free <= 2 else ''} | Lowest durability {up.get('lowestDurability')}%"
          f"{' !! repair' if (up.get('lowestDurability') or 100) < 30 else ''}")
    pet = snap.get("pet") or {}
    if pet:
        warn = " !! more than 2 levels behind" if (pet.get("level") or 0) < level - 2 else ""
        print(f"Pet: {pet.get('name')} ({pet.get('family')}) level {pet.get('level')} "
              f"XP {pet.get('xp')}/{pet.get('xpMax')}{warn}")
    if snap.get("unspentTalentPoints"):
        print(f"!! Unspent talent points: {snap['unspentTalentPoints']}")
    print("PvP flagged: " + ("YES" if snap.get("pvpFlagged") else "no"))
    loc = snap.get("location") or {}
    party = snap.get("party") or []
    if party:
        print("Party:")
        for m in party:
            where = m.get("mapName") or "zone unknown"
            if m.get("mapID") and m.get("mapID") == loc.get("mapID"):
                where += " (same map"
                if None not in (m.get("x"), m.get("y"), loc.get("x"), loc.get("y")):
                    where += f", {dist((m['x'], m['y']), (loc['x'], loc['y'])):.1f} away"
                where += ")"
            state = "online" if m.get("online") == "yes" else "OFFLINE"
            print(f"  {m.get('name')} {m.get('class')} {m.get('level')} ({state}) — {where}")
    else:
        print("Party: solo")
    guild = snap.get("guild")
    if "guild" in snap or "communities" in snap:
        print("Guild: " + (f"<{guild.get('name')}> rank {guild.get('rank')}, "
                           f"{guild.get('online')}/{guild.get('members')} online" if guild else "none"))
        clubs = snap.get("communities") or []
        print("Communities: " + (", ".join(f"{c.get('name')} ({c.get('type')}, "
                                           f"{len(c.get('online') or [])}/{c.get('members')} online)"
                                           for c in clubs) or "none"))
    friends = snap.get("onlineFriends")
    if friends is None:
        print("Friends online: not captured (addon older than this tool; /reload)")
    elif not friends:
        print("Friends online: none")
    else:
        here = {loc.get("zone"), loc.get("realZone"), loc.get("mapName")} - {None}
        print("Friends online:")
        for f in sorted(friends, key=lambda f: (f.get("zone") not in here, -(f.get("level") or 0))):
            near = " (same zone)" if f.get("zone") in here else ""
            realm = f" [{f['realm']}]" if f.get("realm") and f.get("realm") != snap.get("realm") else ""
            who = " ".join(str(x) for x in (f.get("name"), f.get("class"), f.get("level")) if x)
            print(f"  {who} — {f.get('zone') or '?'}{near}"
                  f"{realm} via {f.get('source')}")
    deaths = [d for d in hist.get("deaths") or [] if d.get("level") == level]
    if deaths:
        pvp = sum(1 for d in deaths if d.get("killerIsPlayer"))
        print(f"Deaths at level {level}: {len(deaths)} ({pvp} by players)")
    taxis = load_known_taxis()
    if taxis:
        print(f"Known flight paths ({len(taxis)}): " + "; ".join(taxis))


def gear(snap):
    section("Gear and consumables")
    level = snap.get("level") or 0
    cls = IDENTITY.get("class")
    equipped = as_slot_map(snap.get("equipment"))
    bags = snap.get("bags") or []
    if isinstance(bags, dict):
        bags = list(bags.values())
    if cls == "HUNTER":
        ranged = equipped.get(18)
        if ranged:
            print(f"Ranged: {ranged.get('name')} ({ranged.get('subType')}, "
                  f"{(ranged.get('stats') or {}).get('dps') or 0:.1f} DPS)")
        else:
            print("!! No ranged weapon equipped")
        ammo = [b for b in bags if b.get("slot") == "INVTYPE_AMMO" or b.get("type") in ("Proyectil", "Projectile")]
        print("Ammo: " + (", ".join(f"{a.get('name')} x{a.get('count')}" for a in ammo) or "!! NONE"))
    food = [b for b in bags if b.get("subType") in ("Comida y bebida", "Food & Drink")]
    print("Food/drink: " + (", ".join(f"{f.get('name')} x{f.get('count')}" for f in food) or "none"))

    weights = config.STAT_WEIGHTS.get(cls)
    if not weights:
        print(f"No stat weights for {cls or 'unknown class'}: bag-upgrade check skipped "
              "(add them to config.STAT_WEIGHTS).")
        return
    upgrades = []
    for item in bags:
        slots = INVTYPE_SLOTS.get(item.get("slot"))
        if not slots or (item.get("reqLevel") or 0) > level:
            continue
        sub = item.get("subType")
        if sub in BLOCKED_ARMOR or (sub in MAIL and level < 40):
            continue
        new = score(item, weights)
        cur = min(slots, key=lambda s: score(equipped.get(s) or {}, weights))
        old = score(equipped.get(cur) or {}, weights)
        if new > old + 0.01:
            upgrades.append((new - old, item, equipped.get(cur), cur))
    if upgrades:
        print("Possible upgrades in bags (RestedXP weights):")
        for gain, item, cur, slot in sorted(upgrades, key=lambda u: -u[0]):
            print(f"  +{gain:.1f}  {item.get('name')} → slot {slot} "
                  f"(replaces {cur.get('name') if cur else 'empty'})")
    else:
        print("No upgrades in bags by stat weights.")


def quests(Q, snap, zones):
    level = snap.get("level") or 0
    zid, x, y = player_pos(Q, snap)
    pos = (x, y) if x is not None else None
    done = set(snap.get("completedQuests") or [])
    log = snap.get("quests") or []
    in_log = {q.get("id") for q in log}
    complete = [q for q in log if q.get("complete")]
    progress = [q for q in log if not q.get("complete")]

    def turnin(qid):
        q = Q["quests"].get(qid)
        if not q:
            return ["(not in QuestieDB)"]
        return [fmt_loc(Q, l) for l in locate(Q, q["end_npcs"], q["end_objects"], zid, pos)] or ["?"]

    section(f"Ready to turn in ({len(complete)})")
    for lq in sorted(complete, key=lambda q: q.get("level") or 0):
        q = Q["quests"].get(lq["id"])
        xp = fmt_xp(q, level) if q else "XP ?"
        print(f"[{lq['id']}] {quest_name(Q, lq['id'])} (lvl {lq.get('level')}, {xp})")
        for t in turnin(lq["id"]):
            print(f"    turn-in: {t}")

    section(f"In progress ({len(progress)})")
    for lq in sorted(progress, key=lambda q: q.get("level") or 0):
        q = Q["quests"].get(lq["id"])
        xp = fmt_xp(q, level) if q else "XP ?"
        print(f"[{lq['id']}] {quest_name(Q, lq['id'])} (lvl {lq.get('level')}, {xp}) — {lq.get('zoneHeader')}")
        for o in lq.get("objectives") or []:
            mark = "✓" if o.get("done") else "·"
            print(f"    {mark} {o.get('text')}")
        for t in turnin(lq["id"]):
            print(f"    turn-in: {t}")

    # Quests unlocked once the complete ones are turned in.
    after = done | {q["id"] for q in complete}
    complete_ids = {q["id"] for q in complete}
    unlocks = []
    for q in Q["quests"].values():
        if q["id"] in done or q["id"] in in_log or not fits_character(q) or not is_horde_ok(Q, q):
            continue
        linked = complete_ids & (set(q["prereq_all"]) | set(q["prereq_any"]))
        linked |= {c for c in complete_ids if Q["quests"].get(c, {}).get("next") == q["id"]}
        if linked and prereqs_met(q, after):
            unlocks.append((q, linked))
    section(f"Unlocked by turning in ({len(unlocks)})")
    for q, linked in sorted(unlocks, key=lambda u: -(xp_at_level(u[0], level)[0] or 0)):
        start = [fmt_loc(Q, l) for l in locate(Q, q["start_npcs"], q["start_objects"], zid, pos)]
        print(f"[{q['id']}] {quest_name(Q, q['id'])} (req {q['req_level']}, lvl {q['level']}, "
              f"{fmt_xp(q, level)}) ← {', '.join(map(str, sorted(linked)))}")
        for s in start:
            print(f"    start: {s}")

    # Quests available right now in the selected zones.
    avail = []
    for q in Q["quests"].values():
        if q["id"] in done or q["id"] in in_log or not fits_character(q) or not is_horde_ok(Q, q):
            continue
        qlvl = quest_level(q, level)
        # Level 0 quests are system/mail quests; 10+ above is not leveling content (AQ, PvP signets).
        if q["zone"] in SKIP_ZONES or q["level"] == 0 or q["req_level"] > level \
                or qlvl < level - 4 or qlvl > level + 10:
            continue
        if any(e in done or e in in_log for e in q["exclusive_to"]) or not prereqs_met(q, done):
            continue
        starts = locate(Q, q["start_npcs"], q["start_objects"], zid, pos)
        start_zones = {l[1] for l in starts if l[1] is not None}
        if start_zones & zones or (not start_zones and q["zone"] in zones):
            avail.append((q, starts))
    section(f"Available now in {', '.join(zone_name(Q, z) for z in sorted(zones))} ({len(avail)})")
    for q, starts in sorted(avail, key=lambda a: -(xp_at_level(a[0], level)[0] or 0)):
        print(f"[{q['id']}] {quest_name(Q, q['id'])} (req {q['req_level']}, lvl {q['level']}, "
              f"{fmt_xp(q, level)}) — {zone_name(Q, q['zone']) if q['zone'] else '?'}")
        for s in starts or [("(started by an item)", None, None, None)]:
            print(f"    start: {fmt_loc(Q, s)}")


def main():
    take_char_arg()
    Q = load_q()
    me = main_character()
    others = [f"{char_name(d)} ({s.get('level')})" for d, (s, _) in snapshots().items() if d != me]
    print(f"Character: {char_name(me)} ({IDENTITY.get('race')} {IDENTITY.get('class')}, {IDENTITY.get('faction')})" + (f" | other snapshots: {', '.join(others)}" if others else "")
          + " (pick another with --char NAME)")
    snap, hist = load_snapshot()
    zid = player_pos(Q, snap)[0]
    if len(sys.argv) > 1:
        zones = {resolve_zone(Q, a) for a in sys.argv[1:]}
    else:
        zones = ({zid} | config.NEIGHBORS.get(zid, set())) if zid else set()
    character(Q, snap, hist)
    gear(snap)
    quests(Q, snap, zones)


if __name__ == "__main__":
    main()
