"""Check how far each quest in the log is from a planned route.

Usage: route_check.py [--char NAME] ZONE:X,Y [ZONE:X,Y ...]
  ZONE is a zone ID or (partial) zone name in English or esMX, e.g. 17:52,30 "Thousand:45,50".
  Consecutive points in the same zone form route segments.

For each quest: distance from its objectives (mob spawns, objects, item sources) and its
turn-in to the route, in map units of the same zone:
  <= 10 "on route", <= 20 "short detour", otherwise "off route".
Also shows real XP at the current level with the Classic gray-quest penalty.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (  # noqa: E402
    fmt_xp, load_q, quest_xp_text, load_snapshot, objective_targets, take_char_arg, quest_name, resolve_zone, spawns_of,
    xp_at_level, zone_name,
)

ON_ROUTE, SHORT_DETOUR = 10.0, 20.0


def parse_route(Q, args):
    points = []
    for arg in args:
        zone, sep, xy = arg.rpartition(":")
        if not sep:
            sys.exit(f"Invalid point (use ZONE:X,Y): {arg}")
        x, y = (float(v) for v in xy.split(","))
        points.append((resolve_zone(Q, zone), (x, y)))
    return points


def build_route(points):
    """{zone: [segments]} where a segment is (a, b); an isolated point is (a, a)."""
    route = {}
    for i, (z, p) in enumerate(points):
        segs = route.setdefault(z, [])
        if i + 1 < len(points) and points[i + 1][0] == z:
            segs.append((p, points[i + 1][1]))
        elif not (i > 0 and points[i - 1][0] == z):
            segs.append((p, p))
    return route


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(p[0] - ax, p[1] - ay)
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def closest(points_by_zone, route):
    """(distance, zone, point) of the point closest to the route, or None."""
    best = None
    for z, pts in points_by_zone.items():
        for seg in route.get(z, []):
            for p in pts:
                d = seg_dist(p, *seg)
                if best is None or d < best[0]:
                    best = (d, z, p)
    return best


def verdict(Q, hit, points_by_zone):
    if hit is None:
        if not points_by_zone:
            return 3, "no location data"
        zones = ", ".join(zone_name(Q, z) for z in list(points_by_zone)[:3])
        return 2, f"off route (in {zones})"
    d, z, p = hit
    label = "on route" if d <= ON_ROUTE else "short detour" if d <= SHORT_DETOUR else "off route"
    rank = 0 if d <= ON_ROUTE else 1 if d <= SHORT_DETOUR else 2
    return rank, f"{label} ({d:.1f}) in {zone_name(Q, z)} {p[0]:.1f},{p[1]:.1f}"


def main():
    take_char_arg()
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    Q = load_q()
    snap, _ = load_snapshot()
    level = snap.get("level") or 1
    route = build_route(parse_route(Q, sys.argv[1:]))
    print("Route: " + " → ".join(a for a in sys.argv[1:]))
    print(f"Level {level}. Thresholds: ≤{ON_ROUTE:.0f} on route, ≤{SHORT_DETOUR:.0f} short detour.\n")

    rows = []
    for lq in snap.get("quests") or []:
        qid = lq.get("id")
        q = Q["quests"].get(qid)
        lines = []
        worst = 0
        if not q:
            rows.append((9, 0, [f"[{qid}] {lq.get('title')} — not in QuestieDB"]))
            continue
        complete = bool(lq.get("complete"))
        state = "COMPLETE" if complete else "in progress"
        lines.append(f"[{qid}] {quest_name(Q, qid)} (lvl {q['level']}, {quest_xp_text(q, lq, level)}, {state})")
        if not complete:
            done_texts = [o for o in lq.get("objectives") or [] if o.get("done")]
            targets = objective_targets(Q, q)
            if not targets:
                lines.append("    objectives: no data in QuestieDB")
                worst = max(worst, 3)
            for t in targets:
                rank, text = verdict(Q, closest(t["points"], route), t["points"])
                # Objective already finished in game: does not count against the route.
                if any(t["label"].split(" / ")[-1] in (o.get("text") or "") for o in done_texts):
                    text, rank = "done", 0
                worst = max(worst, rank)
                lines.append(f"    {t['label']}: {text}")
        turnin = {}
        for nid in q["end_npcs"]:
            for z, pts in spawns_of(Q, "npc", nid).items():
                turnin.setdefault(z, []).extend(pts)
        for oid in q["end_objects"]:
            for z, pts in spawns_of(Q, "obj", oid).items():
                turnin.setdefault(z, []).extend(pts)
        rank, text = verdict(Q, closest(turnin, route), turnin)
        # Worst of objectives and turn-in decides the group; missing data never hides a far turn-in.
        worst = max(worst, rank) if worst != 3 else (3 if rank < 2 else 2)
        lines.append(f"    turn-in: {text}")
        xp = lq.get("xp") or xp_at_level(q, level)[0] or 0
        rows.append((worst, -xp, lines))

    titles = {0: "On route", 1: "Short detour", 2: "Off route", 3: "No data", 9: "Unknown"}
    current = None
    for worst, _, lines in sorted(rows, key=lambda r: (r[0], r[1])):
        if worst != current:
            current = worst
            print(f"== {titles[worst]} ==")
        print("\n".join(lines))


if __name__ == "__main__":
    main()
