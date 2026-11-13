"""Shared helpers: load the Q.pkl cache and the live FeliExport snapshot, name/zone lookups,
spawn geometry and quest availability rules."""
import datetime as dt
import math
import pickle
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import config  # noqa: E402

PY = sys.executable
TOOLS = Path(__file__).resolve().parent


# -- loading ---------------------------------------------------------------------------
def load_q(auto_build=True):
    """Load data/Q.pkl, (re)building it when missing or older than the live QuestieDB."""
    import build_q

    stale = not config.Q_PKL.exists()
    if not stale:
        with open(config.Q_PKL, "rb") as fh:
            Q = pickle.load(fh)
        stale = Q.get("source") != build_q.source_stamp()
        if not stale:
            return Q
    if not auto_build:
        sys.exit("data/Q.pkl is missing or stale: run tools/build_q.py")
    print("[Q.pkl missing or QuestieDB changed: rebuilding]", file=sys.stderr)
    subprocess.run([PY, str(TOOLS / "build_q.py")], check=True, stdout=sys.stderr)
    with open(config.Q_PKL, "rb") as fh:
        return pickle.load(fh)


def _lua_to_py(obj):
    import lupa
    if lupa.lua_type(obj) != "table":
        return obj
    d = {k: _lua_to_py(v) for k, v in obj.items()}
    if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
        return [d[i] for i in range(1, len(d) + 1)]
    return d


def load_lua_globals(path, *names):
    """Execute a SavedVariables file in a sandboxed Lua runtime and return the named globals."""
    import lupa
    lua = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
    lua.execute(Path(path).read_text(encoding="utf-8", errors="replace"))
    g = lua.globals()
    return [_lua_to_py(g[n]) if g[n] is not None else None for n in names]


def load_snapshot(path=None):
    """Return (FeliExportDB, FeliExportHistory) from the live SavedVariables."""
    db, hist = load_lua_globals(path or config.SNAPSHOT, "FeliExportDB", "FeliExportHistory")
    return db or {}, hist or {}


def load_known_taxis():
    """Known flight paths from ShortestPathForever: list of names."""
    if not config.SHORTESTPATH_SV.exists():
        return []
    (char,) = load_lua_globals(config.SHORTESTPATH_SV, "ShortestPathForeverCharDB")
    if not char:
        return []
    names = char.get("taxiNames") or {}
    taxi = char.get("taxi") or {}
    return sorted(names.get(k, f"#{k}") for k, v in taxi.items() if v)


def snapshot_age_minutes(snap):
    try:
        saved = dt.datetime.strptime(snap["savedAt"], "%Y-%m-%d %H:%M:%S")
    except (KeyError, ValueError, TypeError):
        return None
    return (dt.datetime.now() - saved).total_seconds() / 60


# -- names -----------------------------------------------------------------------------
def both(en, es):
    """'English / esMX' name pair (or whichever exists)."""
    if en and es and en != es:
        return f"{en} / {es}"
    return en or es or "?"


def quest_name(Q, qid):
    q = Q["quests"].get(qid)
    return both(q["name"], q["name_es"]) if q else f"quest {qid}"


def npc_name(Q, nid):
    n = Q["npcs"].get(nid)
    return both(n["name"], n["name_es"]) if n else f"npc {nid}"


def object_name(Q, oid):
    o = Q["objects"].get(oid)
    return both(o["name"], o["name_es"]) if o else f"obj {oid}"


def item_name(Q, iid):
    i = Q["items"].get(iid)
    return both(i["name"], i["name_es"]) if i else f"item {iid}"


def zone_name(Q, zid):
    return both(Q["zones"].get(zid), Q.get("zones_es", {}).get(zid)) if zid in Q["zones"] or zid in Q.get("zones_es", {}) \
        else f"zone {zid}"


def resolve_zone(Q, token):
    """Zone ID from a number or a (partial, case-insensitive) zone name."""
    if str(token).lstrip("-").isdigit():
        return int(token)
    t = str(token).lower()
    names = list(Q["zones"].items()) + list(Q.get("zones_es", {}).items())
    for zid, name in names:
        if name.lower() == t:
            return zid
    for zid, name in names:
        if t in name.lower():
            return zid
    raise SystemExit(f"Unknown zone: {token}")


def player_zone(Q, snap):
    """QuestieDB zone ID for the snapshot location (via uiMapID), or None."""
    loc = snap.get("location") or {}
    ui = loc.get("mapID")
    if ui in config.MAPID_TO_ZONE:
        return config.MAPID_TO_ZONE[ui]
    if ui in Q["uimap"]:
        return Q["uimap"][ui][0]
    name = (loc.get("zone") or "").lower()
    for zid, zn in list(Q["zones"].items()) + list(Q.get("zones_es", {}).items()):
        if zn.lower() == name:
            return zid
    return None


def player_pos(Q, snap):
    loc = snap.get("location") or {}
    return player_zone(Q, snap), loc.get("x"), loc.get("y")


# -- geometry --------------------------------------------------------------------------
def valid_points(points):
    return [(p[0], p[1]) for p in points or [] if p and p[0] is not None and p[0] >= 0 and p[1] >= 0]


def spawns_of(Q, kind, eid):
    """{zone: [(x, y), ...]} for an npc or object."""
    table = Q["npcs"] if kind == "npc" else Q["objects"]
    e = table.get(eid)
    if not e or not isinstance(e.get("spawns"), dict):
        return {}
    out = {}
    for z, pts in e["spawns"].items():
        v = valid_points(pts)
        if v:
            out[int(z)] = v
    return out


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def nearest(points, origin):
    """(distance, point) of the closest point to origin."""
    best = min(points, key=lambda p: dist(p, origin))
    return dist(best, origin), best


def locate(Q, npcs=(), objects=(), zone=None, pos=None):
    """Describe where a set of npcs/objects is: list of (label, zone, (x, y), distance|None).
    Picks the nearest spawn in the player's zone when possible, else the first spawn."""
    out = []
    for kind, ids in (("npc", npcs), ("obj", objects)):
        for eid in ids or []:
            label = npc_name(Q, eid) if kind == "npc" else object_name(Q, eid)
            sp = spawns_of(Q, kind, eid)
            if not sp:
                out.append((label, None, None, None))
                continue
            if zone in sp and pos and pos[0] is not None:
                d, p = nearest(sp[zone], pos)
                out.append((label, zone, p, d))
            else:
                z = next(iter(sp))
                out.append((label, z, sp[z][0], None))
    return out


def fmt_loc(Q, loc):
    label, z, p, d = loc
    if z is None:
        return f"{label} (no coordinates)"
    s = f"{label} — {zone_name(Q, z)} {p[0]:.1f},{p[1]:.1f}"
    if d is not None:
        s += f" ({d:.1f} away)"
    return s


def cluster(points, radius=8.0):
    """Single-linkage clusters of points closer than `radius` map units.
    Returns [(count, (cx, cy)), ...] sorted by size."""
    pts = list(points)
    seen = [False] * len(pts)
    groups = []
    for i in range(len(pts)):
        if seen[i]:
            continue
        seen[i] = True
        stack, members = [i], []
        while stack:
            j = stack.pop()
            members.append(pts[j])
            for k in range(len(pts)):
                if not seen[k] and dist(pts[j], pts[k]) < radius:
                    seen[k] = True
                    stack.append(k)
        cx = sum(p[0] for p in members) / len(members)
        cy = sum(p[1] for p in members) / len(members)
        groups.append((len(members), (cx, cy)))
    return sorted(groups, key=lambda g: -g[0])


# -- quest rules -----------------------------------------------------------------------
def fits_character(q):
    races, classes = q["races"], q["classes"]
    return (not races or races & config.RACE_BIT) and (not classes or classes & config.CLASS_BIT)


def is_horde_ok(Q, q):
    """False when every starting NPC is Alliance-only."""
    factions = [Q["npcs"].get(n, {}).get("faction") for n in q["start_npcs"]]
    return not factions or any(f in (None, "AH", "H") for f in factions)


def prereqs_met(q, done):
    if any(p > 0 and p not in done for p in q["prereq_all"]):
        return False
    pos_any = [p for p in q["prereq_any"] if p > 0]
    if pos_any and not any(p in done for p in pos_any):
        return False
    return True


def quest_level(q, player_level):
    return q["level"] if q["level"] and q["level"] > 0 else player_level


def xp_at_level(q, player_level):
    """(xp, pct, source) with Classic gray-quest penalty. source: 'real', 'classic' or None."""
    base, source = q["xp"], "real"
    if not base:
        base, source = q.get("xp_classic"), "classic"
    if not base:
        return None, None, None
    diff = player_level - quest_level(q, player_level)
    pct = 100 if diff <= 5 else {6: 80, 7: 60, 8: 40, 9: 20}.get(diff, 10)
    return int(round(base * pct / 100 / 5.0) * 5) if pct < 100 else base, pct, source


def fmt_xp(q, level):
    xp, pct, src = xp_at_level(q, level)
    if xp is None:
        return "XP ?"
    s = f"{xp} XP"
    if pct < 100:
        s += f" ({pct}%)"
    if src == "classic":
        s += " ~classic"
    return s


def money(copper):
    copper = int(copper or 0)
    return f"{copper // 10000}g {copper // 100 % 100}s {copper % 100}c"


# -- objectives ------------------------------------------------------------------------
def is_elite(npc):
    return 1 <= (npc.get("rank") or 0) <= 3


def npc_level(npc):
    lo, hi = npc.get("min_level"), npc.get("max_level")
    if lo is None:
        return "?"
    return str(lo) if lo == hi or hi is None else f"{lo}-{hi}"


def objective_targets(Q, q):
    """Expand a quest's objectives into targets with their spawn points.

    Returns a list of dicts:
      {"kind": "mob"|"object"|"item", "id", "label",
       "sources": [{"kind": "npc"|"obj", "id", "label", "level", "elite", "drop"}],
       "points": {zone: [(x, y), ...]}}
    """
    out = []

    def add_points(points, kind, eid):
        for z, pts in spawns_of(Q, kind, eid).items():
            points.setdefault(z, []).extend(pts)

    def npc_source(nid, drop=None):
        n = Q["npcs"].get(nid, {})
        return {"kind": "npc", "id": nid, "label": npc_name(Q, nid), "level": npc_level(n),
                "elite": is_elite(n), "drop": drop}

    objectives = q.get("objectives") or {}
    for entry in objectives.get(1, []):
        nid = entry[0] if isinstance(entry, list) else entry
        points = {}
        add_points(points, "npc", nid)
        out.append({"kind": "mob", "id": nid, "label": npc_name(Q, nid),
                    "sources": [npc_source(nid)], "points": points})
    for entry in objectives.get(2, []):
        ids = entry[0] if isinstance(entry, list) else entry
        ids = ids if isinstance(ids, list) else [ids]
        points, sources = {}, []
        for oid in ids:
            add_points(points, "obj", oid)
            sources.append({"kind": "obj", "id": oid, "label": object_name(Q, oid)})
        out.append({"kind": "object", "id": ids[0], "label": object_name(Q, ids[0]),
                    "sources": sources, "points": points})
    for entry in objectives.get(3, []):
        iid = entry[0] if isinstance(entry, list) else entry
        item = Q["items"].get(iid, {})
        rates = Q["drops"].get(iid, {})
        points, sources = {}, []
        for nid in item.get("npcs") or []:
            add_points(points, "npc", nid)
            sources.append(npc_source(nid, rates.get(nid)))
        for oid in item.get("objects") or []:
            add_points(points, "obj", oid)
            sources.append({"kind": "obj", "id": oid, "label": object_name(Q, oid)})
        sources.sort(key=lambda s: -(s.get("drop") or 0))
        out.append({"kind": "item", "id": iid, "label": item_name(Q, iid),
                    "sources": sources, "points": points})
    return out


def fmt_source(s):
    if s["kind"] == "obj":
        return f"{s['label']} (object)"
    txt = f"{s['label']} lvl {s['level']}"
    if s.get("elite"):
        txt += " ELITE"
    if s.get("drop") is not None:
        txt += f" drop {s['drop']:.0f}%"
    return txt
