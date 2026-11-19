"""Per-quest guide: start, turn-in, text and objectives with mob levels and spawn clusters.

Usage: guide.py [--char NAME] <questID> [questID ...]
  The character only sets the level used for XP.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (  # noqa: E402
    cluster, fits_character, fmt_loc, fmt_source, fmt_xp, load_q, load_snapshot, locate, take_char_arg,
    objective_targets, player_zone, quest_name, vendors_in, zone_name,
)

CLUSTER_RADIUS = 8.0
TOP_CLUSTERS = 3
MAX_SOURCES = 8


def clusters_for(points):
    """Top clusters across all zones: [(count, zone, (x, y))]."""
    found = []
    for z, pts in points.items():
        for count, center in cluster(pts, CLUSTER_RADIUS):
            found.append((count, z, center))
    return sorted(found, key=lambda c: -c[0])[:TOP_CLUSTERS]


def show(Q, qid, level, here=None):
    q = Q["quests"].get(qid)
    if not q:
        print(f"\n### {qid}: not in QuestieDB")
        return
    print(f"\n### [{qid}] {quest_name(Q, qid)}")
    zone = zone_name(Q, q["zone"]) if q["zone"] else "?"
    print(f"Level {q['level']} (req {q['req_level']}) · {zone} · {fmt_xp(q, level)} at level {level}"
          + ("" if fits_character(q) else " · !! not available to this character's race/class"))
    for loc in locate(Q, q["start_npcs"], q["start_objects"]):
        print(f"Start: {fmt_loc(Q, loc)}")
    if q["start_items"]:
        print("Start: item " + ", ".join(map(str, q["start_items"])))
    for loc in locate(Q, q["end_npcs"], q["end_objects"]):
        print(f"Turn-in: {fmt_loc(Q, loc)}")
    if q["prereq_all"] or q["prereq_any"]:
        print("Requires: " + ", ".join(f"[{p}] {quest_name(Q, p)}" for p in q["prereq_all"] + q["prereq_any"]))
    if q["next"]:
        print(f"Next: [{q['next']}] {quest_name(Q, q['next'])}")
    for t in q["text"]:
        print(f"  EN: {t}")
    for t in q["text_es"]:
        print(f"  ES: {t}")
    targets = objective_targets(Q, q)
    if not targets:
        print("Objectives: no mob/object/item data in QuestieDB")
    for t in targets:
        kind = {"mob": "Kill", "object": "Use", "item": "Collect"}[t["kind"]]
        print(f"- {kind}: {t['label']}")
        vendors = [s for s in t["sources"] if s["kind"] == "vendor"]
        drops = [s for s in t["sources"] if s["kind"] != "vendor"]
        if t["kind"] != "mob" or len(t["sources"]) > 1:
            for s in drops[:MAX_SOURCES]:
                print(f"    from: {fmt_source(s)}")
            if len(drops) > MAX_SOURCES:
                print(f"    … and {len(drops) - MAX_SOURCES} more sources")
            if vendors:
                print(f"    sold by {len(vendors)} vendor{'s' if len(vendors) != 1 else ''}"
                      + ("" if t.get("bought") else f", e.g. {vendors[0]['label']}"))
        else:
            print(f"    {fmt_source(t['sources'][0])}")
        if t.get("bought"):
            # A vendor item: the useful places are where the player is and where it is handed in.
            zones = [here] + [loc[1] for loc in locate(Q, q["end_npcs"], q["end_objects"])]
            shown = False
            for z in dict.fromkeys(z for z in zones if z):
                for seller, (x, y) in vendors_in(Q, t, z)[:3]:
                    print(f"    buy from: {seller} — {zone_name(Q, z)} {x:.1f},{y:.1f}")
                    shown = True
            if shown:
                continue
        cl = clusters_for(t["points"])
        if not cl:
            print("    no known spawns")
        for count, z, (x, y) in cl:
            print(f"    area: {zone_name(Q, z)} {x:.1f},{y:.1f} ({count} spawn{"s" if count != 1 else ""})")


def main():
    take_char_arg()
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    Q = load_q()
    try:
        snap = load_snapshot()[0]
        level, here = snap.get("level") or 60, player_zone(Q, snap)
    except (Exception, SystemExit):  # no snapshot: still print the guide
        level, here = 60, None
    for arg in sys.argv[1:]:
        show(Q, int(arg), level, here)


if __name__ == "__main__":
    main()
