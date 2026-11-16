"""Estimate what each quest in the log is worth: minutes to finish it from where the character
stands, the XP it brings (quest reward plus the kills it needs) and XP per minute.

Usage: quest_value.py [--char NAME]

It is a model, not a measurement. Quest XP is the client's own number when the snapshot has
it. Everything else is estimated:
  * travel: straight lines on foot at RUN_YPS, using the zone sizes the addon measured
    (a default size when a zone was not measured); another zone costs a flat OTHER_ZONE_SEC
  * kills: remaining count divided by the drop rate, a time per kill that grows with the
    mob's level, and Classic's mob XP formula (no rested bonus)
  * each quest is timed on its own, as if it were the only one: quests that share an area
    are cheaper together than their separate numbers suggest
Use it to rank quests and to spot the ones that are not worth it, not to plan to the minute.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import config  # noqa: E402
from common import (  # noqa: E402
    cluster, dist, load_q, load_snapshot, objective_targets, player_pos, quest_name, spawns_of,
    take_char_arg, xp_at_level,
)

RUN_YPS = 7.0             # running speed on foot, yards per second
OTHER_ZONE_SEC = 480      # flat cost of getting to another zone (flight, boat or a long run)
DEFAULT_ZONE = (4000, 2667)   # yards, for zones the addon did not measure
KILL_SEC = 25             # an even-level, non-elite mob
KILL_SEC_PER_LEVEL = 3    # added per level the mob is above the character (removed below)
KILL_SEC_RANGE = (12, 70)
ELITE_FACTOR = 3
BETWEEN_KILLS_SEC = 10    # finding and reaching the next mob
LOOT_SEC = 8              # opening an object or looting a ground item
DIALOG_SEC = 10           # talking to the turn-in NPC
DEFAULT_DROP = 35.0       # percent, when the drop table has no rate for the source
MIN_DROP = 2.0            # floor, so a near-zero rate does not explode the estimate
MIN_QUEST_MINUTES = 3     # no quest is quicker than this once approach and overhead count


# -- Classic mob XP --------------------------------------------------------------------
def gray_level(level):
    """Highest mob level that gives no XP at `level` (Classic rule)."""
    if level <= 5:
        return 0
    if level <= 39:
        return level - level // 10 - 5
    if level <= 59:
        return level - level // 5 - 1
    return level - 9


def _zero_difference(level):
    for top, zd in ((7, 5), (9, 6), (11, 7), (15, 8), (19, 9), (29, 11), (39, 12), (44, 13), (49, 14),
                    (54, 15), (59, 16)):
        if level <= top:
            return zd
    return 17


def mob_xp(player_level, mob_level, elite=False):
    """XP for killing a mob, by Classic's formula, without rested bonus."""
    if mob_level <= gray_level(player_level):
        return 0
    base = 45 + 5 * player_level
    if mob_level >= player_level:
        xp = base * (1 + 0.05 * min(mob_level - player_level, 4))
    else:
        xp = base * (1 - (player_level - mob_level) / _zero_difference(player_level))
    return int(round(xp * (2 if elite else 1)))


def kill_seconds(player_level, mob_level, elite=False):
    seconds = KILL_SEC + KILL_SEC_PER_LEVEL * (mob_level - player_level)
    seconds = max(KILL_SEC_RANGE[0], min(KILL_SEC_RANGE[1], seconds))
    return seconds * (ELITE_FACTOR if elite else 1)


# -- geometry --------------------------------------------------------------------------
def zone_size(sizes, ui_map):
    """(width, height) in yards of a zone, and whether it was measured."""
    entry = (sizes or {}).get(ui_map) or (sizes or {}).get(str(ui_map))
    if entry and entry.get("w") and entry.get("h"):
        return (entry["w"], entry["h"]), True
    return DEFAULT_ZONE, False


def leg_seconds(a, b, sizes, ui_map_of):
    """Seconds to go from place a to place b, each (zone, (x, y)) in map percent; None is
    'wherever the character is'. Returns (seconds, crossed_zone, measured)."""
    if a is None or b is None:
        return 0, False, True
    if a[0] != b[0]:
        return OTHER_ZONE_SEC, True, True
    (width, height), measured = zone_size(sizes, ui_map_of(a[0]))
    yards = math.hypot((a[1][0] - b[1][0]) / 100 * width, (a[1][1] - b[1][1]) / 100 * height)
    return yards / RUN_YPS, False, measured


# -- per quest -------------------------------------------------------------------------
def _average_level(source):
    """Numeric level of an objective source ('21-22' -> 21.5), or None."""
    try:
        parts = [float(p) for p in str(source.get("level")).split("-")]
        return sum(parts) / len(parts)
    except (TypeError, ValueError):
        return None


def _remaining(target, log_quest):
    """(remaining count, done, known) for a target, matched to the snapshot objective by its
    client-language name."""
    name = target["label"].split(" / ")[-1]
    for objective in log_quest.get("objectives") or []:
        if name in (objective.get("text") or ""):
            if objective.get("done"):
                return 0, True, True
            need, have = objective.get("need"), objective.get("have") or 0
            if need:
                return max(need - have, 0), False, True
    return 1, False, False


def _nearest_point(points_by_zone, here, prefer_zone):
    """Where to go for a target: the centre of its biggest spawn cluster in the zone the
    character is heading through, else in any zone. Returns (zone, (x, y)) or None."""
    zone = here[0] if here and here[0] in points_by_zone else prefer_zone if prefer_zone in points_by_zone else None
    if zone is None:
        zone = next(iter(points_by_zone), None)
    if zone is None:
        return None
    _, centre = cluster(points_by_zone[zone])[0]
    return zone, centre


def estimate(Q, quest, log_quest, level, start, sizes, ui_map_of):
    """Estimate one logged quest. `start` is (zone, (x, y)) of the character, or None.
    Returns a dict: minutes (None when the quest cannot be timed), quest_xp, kill_xp, kills,
    xp_per_minute, notes (list of short caveats)."""
    notes = []
    quest_xp = log_quest.get("xp") or (xp_at_level(quest, level)[0] if quest else None)
    if quest_xp is None:
        notes.append("quest XP unknown")
    result = {"quest_xp": quest_xp or 0, "kill_xp": 0, "kills": 0, "minutes": None,
              "xp_per_minute": None, "notes": notes, "first_zone": None}
    if not quest:
        notes.append("not in the quest database")
        return result

    seconds, here, home_zone = 0.0, start, start[0] if start else None
    if not log_quest.get("complete"):
        targets = objective_targets(Q, quest)
        if not targets:
            notes.append("no objective data")
            return result
        for target in targets:
            remaining, done, known = _remaining(target, log_quest)
            if done:
                continue
            if not known:
                notes.append("count assumed 1")
            place = _nearest_point(target["points"], here, home_zone)
            if place is None:
                notes.append("no known spawn")
                return result
            if result["first_zone"] is None:
                result["first_zone"] = place[0]
            leg, crossed, measured = leg_seconds(here, place, sizes, ui_map_of)
            seconds += leg
            if crossed:
                notes.append("in another zone")
            if not measured:
                notes.append("zone size assumed")
            here = place

            sources = [s for s in target["sources"] if s["kind"] == "npc"]
            if target["kind"] == "object" or not sources:
                seconds += remaining * (LOOT_SEC + BETWEEN_KILLS_SEC)
                continue
            source = max(sources, key=lambda s: s.get("drop") or 0)
            mob_level = _average_level(source) or level
            kills = remaining
            if target["kind"] == "item":
                rate = source.get("drop")
                if rate is None:
                    rate = DEFAULT_DROP
                    notes.append("drop rate assumed")
                kills = math.ceil(remaining / (max(rate, MIN_DROP) / 100))
            elite = bool(source.get("elite"))
            if elite:
                notes.append("elite")
            seconds += kills * (kill_seconds(level, mob_level, elite) + BETWEEN_KILLS_SEC)
            result["kills"] += kills
            result["kill_xp"] += kills * mob_xp(level, int(round(mob_level)), elite)

    turnin = {}
    for kind, ids in (("npc", quest["end_npcs"]), ("obj", quest["end_objects"])):
        for eid in ids or []:
            for zone, points in spawns_of(Q, kind, eid).items():
                turnin.setdefault(zone, []).extend(points)
    if turnin:
        zone = here[0] if here and here[0] in turnin else next(iter(turnin))
        point = min(turnin[zone], key=lambda p: dist(p, here[1])) if here and here[0] == zone else turnin[zone][0]
        if result["first_zone"] is None:
            result["first_zone"] = zone
        leg, crossed, measured = leg_seconds(here, (zone, point), sizes, ui_map_of)
        seconds += leg + DIALOG_SEC
        if crossed:
            notes.append("turn-in in another zone")
        if not measured and "zone size assumed" not in notes:
            notes.append("zone size assumed")
    else:
        notes.append("turn-in place unknown")

    result["notes"] = list(dict.fromkeys(notes))
    result["minutes"] = max(seconds / 60, MIN_QUEST_MINUTES)
    result["xp_per_minute"] = (result["quest_xp"] + result["kill_xp"]) / result["minutes"]
    return result


def rank(Q, snap, ui_map_of):
    """[(log_quest, estimate)] for every logged quest. Quests that start in the character's
    zone come first, timed from where the character stands. Quests elsewhere follow, timed
    from arriving at their first stop (`elsewhere` is set): the trip there is not guessed.
    Within each group the best XP per minute is first and untimed quests are last."""
    level = snap.get("level") or 1
    zone, x, y = player_pos(Q, snap)
    start = (zone, (x, y)) if zone is not None and x is not None else None
    sizes = snap.get("mapSizes")
    rows = []
    for log_quest in snap.get("quests") or []:
        quest = Q["quests"].get(log_quest.get("id"))
        e = estimate(Q, quest, log_quest, level, start, sizes, ui_map_of)
        if start and e["first_zone"] is not None and e["first_zone"] != start[0]:
            e = estimate(Q, quest, log_quest, level, None, sizes, ui_map_of)
            e["elsewhere"] = e["first_zone"]
        rows.append((log_quest, e))
    rows.sort(key=lambda r: (r[1]["minutes"] is None, bool(r[1].get("elsewhere")), -(r[1]["xp_per_minute"] or 0)))
    return rows


def lines(Q, rows):
    out, in_elsewhere = [], False
    for log_quest, e in rows:
        if e.get("elsewhere") and e["minutes"] is not None and not in_elsewhere:
            in_elsewhere = True
            out.append("-- in other zones (timed from arriving there; the trip is not included) --")
        qid = log_quest.get("id")
        name = quest_name(Q, qid) if qid in Q["quests"] else log_quest.get("title")
        where = f" — {common.zone_name(Q, e['elsewhere'])}" if e.get("elsewhere") else ""
        if e["minutes"] is None:
            out.append(f"   ?      [{qid}] {name} — cannot be timed: {', '.join(e['notes'])}")
            continue
        total = e["quest_xp"] + e["kill_xp"]
        notes = f" [{', '.join(e['notes'])}]" if e["notes"] else ""
        if log_quest.get("complete"):
            when = "" if e.get("elsewhere") else f", ~{e['minutes']:.0f} min away"
            out.append(f"  TURN IN  [{qid}] {name} — {total} XP{when}{where}{notes}")
            continue
        detail = f"{e['quest_xp']} quest" + (f" + ~{e['kill_xp']} from {e['kills']} kills" if e["kills"] else "")
        out.append(f"{e['xp_per_minute']:6.0f}/min  [{qid}] {name} — ~{e['minutes']:.0f} min, "
                   f"{total} XP ({detail}){where}{notes}")
    return out


def ui_map_lookup(Q):
    """zone ID -> uiMapID, for the zone size table."""
    by_zone = {}
    for ui, (area, _) in sorted(Q["uimap"].items(), reverse=True):
        by_zone[area] = ui
    for ui, area in config.MAPID_TO_ZONE.items():
        by_zone[area] = ui
    return by_zone.get


def main():
    take_char_arg()
    if "-h" in sys.argv or "--help" in sys.argv:
        sys.exit(__doc__)
    Q = load_q()
    snap, _ = load_snapshot()
    measured = len(snap.get("mapSizes") or {})
    print(f"Quest value at level {snap.get('level')} (estimate; each quest timed on its own). "
          + (f"Zone sizes measured: {measured}." if measured else
             "Zone sizes not in the snapshot yet (/reload twice): a default size is assumed."))
    print("\n".join(lines(Q, rank(Q, snap, ui_map_lookup(Q)))))


if __name__ == "__main__":
    main()
