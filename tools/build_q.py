"""Build data/Q.pkl: a cache of QuestieDB (quests, NPCs, objects, items) plus real Forever XP.

Run again whenever QuestieDB is updated; `common.load_q()` warns when the cache is stale.
"""
import pickle
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import config  # noqa: E402
import qdb  # noqa: E402


def source_stamp():
    """Fingerprint of the live source files, used to detect a stale cache."""
    stamp = {}
    for p in (config.QUESTIEDB_TOC, config.XP_TRACES):
        st = Path(p).stat()
        stamp[str(p)] = (st.st_size, int(st.st_mtime))
    return stamp


# Bumped when the cache gains a field, so an older Q.pkl is rebuilt even with QuestieDB unchanged.
SCHEMA = 2


def slot(value, index):
    """Field `index` (1-based) of a CBOR value that may be a list (0-based) or a dict (1-based)."""
    if isinstance(value, list):
        return value[index - 1] if len(value) >= index else None
    if isinstance(value, dict):
        return value.get(index)
    return None


def slots(value, count):
    """Normalize a list/dict field into {1..count: list}."""
    return {i: slot(value, i) or [] for i in range(1, count + 1)}


def build():
    t0 = time.time()
    db = qdb.QuestieDB()
    xp = qdb.load_xp()
    xp_classic = qdb.load_xp_classic()
    names_es = {p: db.l10n(p, "esMX") for p in qdb.PREFIXES}
    objectives_es = db.l10n("Quest", "esMX", column=1)

    quests = {}
    for qid, r in db.rows("Quest"):
        starts = slots(r.get(2), 3)
        ends = slots(r.get(3), 2)
        objectives = {k: v for k, v in slots(r.get(10), 5).items() if v}
        real = xp.get(qid)
        classic = xp_classic.get(qid)
        quests[qid] = {
            "id": qid,
            "name": r.get(1),
            "name_es": names_es["Quest"].get(qid),
            "start_npcs": starts[1], "start_objects": starts[2], "start_items": starts[3],
            "end_npcs": ends[1], "end_objects": ends[2],
            "req_level": r.get(4) or 0,
            "level": r.get(5) or 0,
            "races": r.get(6) or 0,
            "classes": r.get(7) or 0,
            "text": [t for t in (r.get(8) or []) if t],
            "text_es": [t for t in (objectives_es.get(qid) or []) if t],
            # 1: creatures, 2: objects, 3: items, each entry [id, optionalText, ...].
            "objectives": objectives,
            "prereq_all": r.get(12) or [],
            "prereq_any": r.get(13) or [],
            "exclusive_to": r.get(16) or [],
            "zone": r.get(17) or 0,
            "next": r.get(22),
            "flags": r.get(23) or 0,
            "xp": real[1] if real else None,
            "xp_level": real[0] if real else None,
            "xp_classic": classic[1] if classic else None,
        }

    npcs = {}
    for nid, r in db.rows("Npc"):
        npcs[nid] = {
            "name": r.get(1), "name_es": names_es["Npc"].get(nid),
            "min_level": r.get(4), "max_level": r.get(5), "rank": r.get(6) or 0,
            "spawns": r.get(7) or {}, "faction": r.get(13),
        }

    objects = {}
    for oid, r in db.rows("Object"):
        objects[oid] = {"name": r.get(1), "name_es": names_es["Object"].get(oid), "spawns": r.get(4) or {}}

    items = {}
    for iid, r in db.rows("Item"):
        items[iid] = {
            "name": r.get(1), "name_es": names_es["Item"].get(iid),
            "npcs": r.get(2) or [], "objects": r.get(3) or [], "vendors": r.get(14) or [],
        }

    Q = {
        "schema": SCHEMA,
        "built_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "source": source_stamp(),
        "flavor": db.get("Flavor"),
        "build": db.get("BUILD-COMMIT"),
        "quests": quests, "npcs": npcs, "objects": objects, "items": items,
        "zones": qdb.load_zone_names(),
        "zones_es": dict(config.ZONE_NAMES_ES),
        "uimap": qdb.load_uimap(),
        "drops": qdb.load_drop_rates(),
    }
    config.DATA_DIR.mkdir(exist_ok=True)
    with open(config.Q_PKL, "wb") as fh:
        pickle.dump(Q, fh, protocol=pickle.HIGHEST_PROTOCOL)

    with_xp = sum(1 for q in quests.values() if q["xp"])
    with_es = sum(1 for q in quests.values() if q["name_es"])
    print(f"Q.pkl built in {time.time() - t0:.1f}s -> {config.Q_PKL}")
    print(f"  quests {len(quests)} (real XP {with_xp}, esMX {with_es}) | npcs {len(npcs)} | "
          f"objects {len(objects)} | items {len(items)} | drops {len(Q['drops'])}")
    print(f"  QuestieDB flavor={Q['flavor']} build={Q['build']}")


if __name__ == "__main__":
    build()
