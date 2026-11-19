"""Shared helpers: load the Q.pkl cache and the live TrailScout snapshot, name/zone lookups,
spawn geometry and quest availability rules."""
import datetime as dt
import math
import pickle
import subprocess
import re
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
        stale = Q.get("source") != build_q.source_stamp() or Q.get("schema") != build_q.SCHEMA
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


# The addon was called FeliExport, then ForeverScout, before TrailScout. The game keeps addon
# data in a file named after the addon, so each rename started a new SavedVariables file and
# left the older ones on disk. All of them are read, oldest first, so no history is lost.
ADDON = ("TrailScout", "TrailScoutDB", "TrailScoutHistory")
OLD_ADDONS = (
    ("FeliExport", "FeliExportDB", "FeliExportHistory"),
    ("ForeverScout", "ForeverScoutDB", "ForeverScoutHistory"),
)
# Keys only this addon writes. Another addon on CurseForge is also called ForeverScout: a
# ForeverScout.lua that lacks these is its data, not an older snapshot of ours.
_OUR_SNAPSHOT_KEYS = ("savedAt", "quests", "upkeep")
_OUR_HISTORY_KEYS = ("levelUps", "deaths", "xpTotal", "flights", "recipes")


def _load_sv(path, names):
    path = Path(path)
    key = (path, names)
    if key not in _snapshots:
        if not path.exists():
            _snapshots[key] = ({}, {})
        else:
            db, hist = load_lua_globals(path, *names)
            db = db if isinstance(db, dict) and any(k in db for k in _OUR_SNAPSHOT_KEYS) else {}
            hist = hist if isinstance(hist, dict) and any(k in hist for k in _OUR_HISTORY_KEYS) else {}
            _snapshots[key] = (db, hist)
    return _snapshots[key]


def _merge_history(old, new):
    """History across a rename: lists are concatenated, maps merged, the XP total summed."""
    if not old:
        return new
    if not new:
        return old
    merged = dict(old)
    for key, value in new.items():
        prev = merged.get(key)
        # An empty Lua table loads as an empty dict whatever it was meant to hold: a list the
        # new addon has not added to yet must not wipe the older entries.
        if prev and isinstance(value, (list, dict)) and not value:
            continue
        if isinstance(value, list) and isinstance(prev, list):
            merged[key] = prev + value
        elif isinstance(value, dict) and isinstance(prev, dict):
            merged[key] = {**prev, **value}
        elif key == "xpTotal" and isinstance(prev, (int, float)):
            merged[key] = prev + (value or 0)
        else:
            merged[key] = value
    # A dungeon run left open under an older name is stale once the new addon is running.
    merged["openRun"] = new.get("openRun")
    return merged


def _snapshot_at(path):
    """(db, hist) from an explicit snapshot file, under any of the addon's names."""
    for _, *names in (ADDON,) + tuple(reversed(OLD_ADDONS)):
        db, hist = _load_sv(path, tuple(names))
        if db or hist:
            return db, hist
    return {}, {}


def char_snapshot(char_dir):
    """(db, hist) for a character: the newest snapshot among the addon's names (the file
    with the latest savedAt) and the history of all of them merged, oldest first."""
    loaded = [_load_sv(config.char_sv(char_dir, name), tuple(names)) for name, *names in OLD_ADDONS + (ADDON,)]
    hist = {}
    for _, part in loaded:
        hist = _merge_history(hist, part)
    snapshots_found = [db for db, _ in loaded if db]
    db = max(snapshots_found, key=lambda d: str(d.get("savedAt") or ""), default={})
    if db:
        fill_from_history(db, hist)
    return db, hist


def fill_from_history(db, hist):
    """Flight paths and recipes are only re-recorded when their windows open again, so the
    snapshot keeps every entry the history has (also from before a rename) and its own on top.
    One profession opened today must not hide the others recorded earlier."""
    for key in ("flights", "recipes"):
        old, new = hist.get(key), db.get(key)
        if isinstance(old, dict) and old:
            db[key] = {**old, **new} if isinstance(new, dict) else old
    return db


def snapshots():
    """{char_dir: (db, hist)} for every character with a snapshot under any addon name."""
    out = {}
    names = [ADDON[0]] + [old[0] for old in OLD_ADDONS]
    for d in config.character_dirs():
        if any(config.char_sv(d, name).exists() for name in names):
            snap = char_snapshot(d)
            if snap[0]:
                out[d] = snap
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


# -- items across the account ---------------------------------------------------------
def flatten_items(value):
    """Yield item dicts (with itemID) from Syndicator's nested bag/tab/mail structures."""
    if isinstance(value, dict):
        if value.get("itemID"):
            yield value
            return
        value = list(value.values())
    for v in value or []:
        if isinstance(v, (list, dict)):
            yield from flatten_items(v)


def link_name(link):
    m = re.search(r"\[(.*?)\]", link or "")
    return m.group(1) if m else None


def collect_items(snaps):
    """{itemID: row} for every character: Syndicator bags/bank/mail, falling back to the
    TrailScout snapshot bags for characters Syndicator does not know. Snapshots of every
    character also supply item type and vendor price."""
    rows = {}

    def add(char, where, iid, name, count, quality, bound):
        r = rows.setdefault(iid, {"id": iid, "name": name, "where": {}, "chars": set(), "quality": quality,
                                  "bound": False, "sell": None, "type": None, "subType": None})
        key = f"{char}:{where}"
        r["where"][key] = r["where"].get(key, 0) + (count or 1)
        r["chars"].add(char)
        r["bound"] = r["bound"] or bool(bound)
        r["name"] = r["name"] or name

    syn = syndicator_characters()
    for char, data in syn.items():
        for label, section in (("bags", data.get("bags")), ("bank", data.get("bankTabs")),
                               ("bank", data.get("bank")), ("mail", data.get("mail"))):
            for e in flatten_items(section):
                add(char, label, e["itemID"], link_name(e.get("itemLink")),
                    e.get("itemCount"), e.get("quality"), e.get("isBound"))

    meta = {}
    for d, (snap, _) in snaps.items():
        char = char_name(d)
        for b in snap.get("bags") or []:
            meta[b["id"]] = b
            if char not in syn:
                add(char, "bags", b["id"], b.get("name"), b.get("count"), b.get("quality"), None)
    for iid, r in rows.items():
        b = meta.get(iid)
        if b:
            r["name"] = b.get("name") or r["name"]
            for k in ("sell", "type", "subType", "reqLevel"):
                if b.get(k) is not None:
                    r[k] = b[k]
    return rows


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
        sys.exit("No TrailScout snapshot found: log in, run /scout or /reload, then retry")
    return max(snaps, key=lambda d: (snaps[d][0].get("level") or 0, snaps[d][0].get("savedAt") or ""))


def load_snapshot(char_dir=None):
    """Return (TrailScoutDB, TrailScoutHistory) for a character (default: main_character())."""
    if char_dir is None and config.SNAPSHOT_OVERRIDE:
        snap = _snapshot_at(config.SNAPSHOT_OVERRIDE)
        IDENTITY.update({k: snap[0].get(k) for k in ("class", "race", "faction")})
        use_locale(snap[0].get("locale"))
        return snap
    return char_snapshot(char_dir or main_character())


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
# Names are shown as "English / Spanish" for a Spanish game client, because the player sees
# the Spanish one in game and most outside sources use the English one. On any other client
# only the English name is shown, and it is also what objective texts are matched against.
# Set from the snapshot's `locale` by use_locale(); Spanish until a snapshot says otherwise.
SPANISH_CLIENT = True


def use_locale(locale):
    """Follow the game client's language (snapshot `locale`, e.g. "esMX" or "enUS")."""
    global SPANISH_CLIENT
    if locale:
        SPANISH_CLIENT = str(locale).lower().startswith("es")


def both(en, es):
    """A display name: 'English / Spanish' on a Spanish client, English otherwise (or
    whichever exists)."""
    if SPANISH_CLIENT and en and es and en != es:
        return f"{en} / {es}"
    return en or es or "?"


def client_name(label):
    """The half of a display name the game client itself shows (what objective texts and
    map pins should use): the Spanish half of 'English / Spanish', or the whole name."""
    return label.split(" / ")[-1]


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
    snap = char_snapshot(char_dir)[0]
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
    """Adopt a character for the rest of the run: who it is (quest filters) and which
    language its game client is in (how names are shown and matched)."""
    IDENTITY.update(identity_of(char_dir))
    use_locale(char_snapshot(char_dir)[0].get("locale"))
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


def quest_xp_text(q, log_quest, level):
    """XP of a logged quest. The client's own number (snapshot `xp`) wins: it is what the
    quest pays at the current level, and the only source for quests the database lacks."""
    client = (log_quest or {}).get("xp")
    if client:
        return f"{client} XP"
    return fmt_xp(q, level) if q else "XP ?"


def map_label(Q, map_id):
    """Zone name of a uiMapID, in both languages when known."""
    area = config.MAPID_TO_ZONE.get(map_id) or (Q["uimap"].get(map_id) or (None,))[0]
    return zone_name(Q, area) if area else f"map {map_id}"


def client_places(Q, log_quest):
    """Where the client and the player's own history place a logged quest, for quests the
    database cannot locate: the game's next waypoint and where the quest was accepted."""
    lines = []
    way = (log_quest or {}).get("waypoint") or {}
    if way.get("mapID") and way.get("x") is not None:
        what = "turn-in" if log_quest.get("complete") else "next step"
        lines.append(f"{what} (game waypoint): {map_label(Q, way['mapID'])} {way['x']:.1f},{way['y']:.1f}")
    giver = (log_quest or {}).get("giver") or {}
    if giver.get("mapID") and giver.get("x") is not None:
        who = giver.get("name") or "no NPC (item or object)"
        lines.append(f"accepted from {who}: {map_label(Q, giver['mapID'])} {giver['x']:.1f},{giver['y']:.1f} "
                     f"(your own record, {giver.get('at')})")
    return lines


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
        # An item nothing drops is bought: its vendors are the places to go. For an item that
        # also drops, vendors are listed but the stops stay on the drops.
        vendors = [nid for nid in item.get("vendors") or [] if _vendor_serves(Q, nid)]
        bought = bool(vendors) and not sources
        for nid in vendors:
            if bought:
                add_points(points, "npc", nid)
            sources.append({"kind": "vendor", "id": nid, "label": npc_name(Q, nid)})
        out.append({"kind": "item", "id": iid, "label": item_name(Q, iid),
                    "sources": sources, "points": points, "bought": bought})
    return out


def _vendor_serves(Q, nid, ident=None):
    """False for a vendor of the other faction."""
    faction = (ident or IDENTITY).get("faction")
    theirs = Q["npcs"].get(nid, {}).get("faction")
    return faction not in ("Horde", "Alliance") or theirs in (None, "AH", faction[0])


def vendors_in(Q, target, zone):
    """[(label, (x, y))] for the vendors of a bought objective that stand in `zone`."""
    found = []
    for source in target["sources"]:
        if source["kind"] == "vendor":
            for point in spawns_of(Q, "npc", source["id"]).get(zone) or []:
                found.append((source["label"], point))
                break
    return found


def fmt_source(s):
    if s["kind"] == "obj":
        return f"{s['label']} (object)"
    if s["kind"] == "vendor":
        return f"{s['label']} (vendor)"
    txt = f"{s['label']} lvl {s['level']}"
    if s.get("elite"):
        txt += " ELITE"
    if s.get("drop") is not None:
        txt += f" drop {s['drop']:.0f}%"
    return txt
