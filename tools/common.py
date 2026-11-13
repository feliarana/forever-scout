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


# -- characters ------------------------------------------------------------------------
_char_arg = None      # set by take_char_arg() from `--char NAME`
_snapshots = {}       # snapshot path -> (db, hist)
_syndicator = None    # cached syndicator_characters()


def take_char_arg(argv=None):
    """Remove `--char NAME` from argv (default sys.argv) and remember it for main_character()."""
    global _char_arg
    argv = sys.argv if argv is None else argv
    if "--char" in argv:
        i = argv.index("--char")
        if i + 1 >= len(argv):
            sys.exit("--char needs a character name")
        _char_arg = argv[i + 1]
        del argv[i:i + 2]
    return argv


def char_name(char_dir):
    """Display name of a character folder: 'Caza-Peques'."""
    return Path(char_dir).name


def _snapshot_at(path):
    path = Path(path)
    if path not in _snapshots:
        if not path.exists():
            _snapshots[path] = ({}, {})
        else:
            db, hist = load_lua_globals(path, "FeliExportDB", "FeliExportHistory")
            _snapshots[path] = (db or {}, hist or {})
    return _snapshots[path]


def snapshots():
    """{char_dir: (db, hist)} for every character with a FeliExport snapshot."""
    out = {}
    for d in config.character_dirs():
        path = config.char_sv(d, "FeliExport")
        if path.exists():
            out[d] = _snapshot_at(path)
    return out


def syndicator_characters():
    """{character folder name: Syndicator character data} (bags, bank tabs, mail, details)."""
    global _syndicator
    if _syndicator is None:
        _syndicator = {}
        if config.SYNDICATOR_SV.exists():
            (data,) = load_lua_globals(config.SYNDICATOR_SV, "SYNDICATOR_DATA")
            for key, char in ((data or {}).get("Characters") or {}).items():
                name = (char.get("details") or {}).get("character") or key.rsplit("-", 1)[0]
                _syndicator[name.replace(" ", "-")] = char
    return _syndicator


def main_character():
    """Character folder to analyze: --char, then WOW_CHAR, then the highest-level snapshot.
    Also sets IDENTITY (class/race/faction) for quest filtering."""
    d = _pick_character()
    use_identity(d)
    return d


def _pick_character():
    wanted = _char_arg or config.CHARACTER
    dirs = config.character_dirs()
    if wanted:
        w = wanted.lower().replace(" ", "-")
        for d in dirs:
            if d.name.lower() == w or d.name.split("-")[0].lower() == w:
                return d
        sys.exit(f"Unknown character '{wanted}'. Known: {', '.join(char_name(d) for d in dirs)}")
    snaps = snapshots()
    if not snaps:
        sys.exit("No FeliExport snapshot found: log in, run /wow or /reload, then retry")
    return max(snaps, key=lambda d: (snaps[d][0].get("level") or 0, snaps[d][0].get("savedAt") or ""))


def load_snapshot(char_dir=None):
    """Return (FeliExportDB, FeliExportHistory) for a character (default: main_character())."""
    if char_dir is None and config.SNAPSHOT_OVERRIDE:
        snap = _snapshot_at(config.SNAPSHOT_OVERRIDE)
        IDENTITY.update({k: snap[0].get(k) for k in ("class", "race", "faction")})
        return snap
    return _snapshot_at(config.char_sv(char_dir or main_character(), "FeliExport"))


def load_known_taxis(char_dir=None):
    """Known flight paths from ShortestPathForever: list of names."""
    path = config.char_sv(char_dir or main_character(), "ShortestPathForever")
    if not path.exists():
        return []
    (char,) = load_lua_globals(path, "ShortestPathForeverCharDB")
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
# Identity of the character being analyzed; set by main_character() / use_identity().
IDENTITY = {"class": None, "race": None, "faction": None}


def identity_of(char_dir):
    """{"class": "HUNTER", "race": "Troll", "faction": "Horde"} from the snapshot, falling
    back to Syndicator's character details for snapshots taken before these fields existed."""
    snap = _snapshot_at(config.char_sv(char_dir, "FeliExport"))[0]
    ident = {k: snap.get(k) for k in ("class", "race", "faction")}
    if not all(ident.values()):
        details = syndicator_characters().get(char_name(char_dir), {}).get("details") or {}
        ident["class"] = ident["class"] or details.get("className")
        ident["race"] = ident["race"] or details.get("race")
        ident["faction"] = ident["faction"] or details.get("faction")
    if not ident["faction"] and ident["race"]:
        ident["faction"] = "Horde" if ident["race"] in config.HORDE_RACES else "Alliance"
    return ident


def use_identity(char_dir):
    IDENTITY.update(identity_of(char_dir))
    return IDENTITY


def fits_character(q, ident=None):
    ident = ident or IDENTITY
    races, classes = q["races"], q["classes"]
    race_bit = config.RACE_BITS.get(ident.get("race") or "", 0)
    class_bit = config.CLASS_BITS.get(ident.get("class") or "", 0)
    # Unknown identity: do not filter on that dimension.
    race_ok = not races or not race_bit or races & race_bit
    class_ok = not classes or not class_bit or classes & class_bit
    return bool(race_ok and class_ok)


def is_horde_ok(Q, q, ident=None):
    """False when every starting NPC belongs to the other faction."""
    faction = (ident or IDENTITY).get("faction")
    if faction not in ("Horde", "Alliance"):
        return True
    mine = faction[0]
    factions = [Q["npcs"].get(n, {}).get("faction") for n in q["start_npcs"]]
    return not factions or any(f in (None, "AH", mine) for f in factions)


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
