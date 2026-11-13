"""Reader for QuestieDB_Forever.toc (baked mode) and its Forever support files.

TOC format:
  * Data lives in `## X-<key>: <value>` lines. A value `~N~` means the real value is the
    concatenation of `X-<key>-1` .. `X-<key>-N`.
  * `X-<Prefix>-IDS`: base64 -> zlib -> CBOR -> sorted list of IDs.
  * `X-<Prefix>-<id>-S`: base64 -> CBOR row (list where index 0 is field 1, or dict).
    Fields missing from the row live in `X-<Prefix>-<id>-<field>` (base64 -> CBOR).
  * `X-l10n-<locale>-<Prefix>`: base64 -> zlib -> CBOR; block[0] is a list of names aligned
    with the sorted IDs (shorter lists simply have no translation for the tail).
"""
import base64
import re
import sys
import zlib
from pathlib import Path

import cbor2

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import config  # noqa: E402

PREFIXES = ("Quest", "Npc", "Object", "Item")


def _text(value):
    """Recursively turn CBOR bytes into str (UTF-8) so rows are plain Python data."""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, list):
        return [_text(v) for v in value]
    if isinstance(value, dict):
        return {_text(k): _text(v) for k, v in value.items()}
    return value


def _inflate(raw):
    """zlib-decompress trying zlib, raw deflate and gzip headers."""
    for wbits in (zlib.MAX_WBITS, -zlib.MAX_WBITS, 16 + zlib.MAX_WBITS):
        try:
            return zlib.decompress(raw, wbits)
        except zlib.error:
            continue
    raise ValueError("payload is not zlib/deflate/gzip")


class QuestieDB:
    def __init__(self, toc_path=None):
        self.path = Path(toc_path or config.QUESTIEDB_TOC)
        self.kv = {}
        with open(self.path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if line.startswith("## X-"):
                    key, _, value = line[5:].rstrip("\r\n").partition(": ")
                    self.kv[key] = value
        self._ids = {}
        self._fields_by_id = None

    # -- raw access -------------------------------------------------------------------
    def get(self, key):
        """Return the stored value for key, joining `~N~` chunks."""
        value = self.kv.get(key)
        if value is None:
            return None
        m = re.fullmatch(r"~(\d+)~", value)
        if m:
            return "".join(self.kv[f"{key}-{i}"] for i in range(1, int(m.group(1)) + 1))
        return value

    def _cbor(self, key, compressed=False):
        value = self.get(key)
        if value is None:
            return None
        raw = base64.b64decode(value)
        if compressed:
            raw = _inflate(raw)
        return cbor2.loads(raw)

    # -- entities ---------------------------------------------------------------------
    def ids(self, prefix):
        if prefix not in self._ids:
            self._ids[prefix] = sorted(self._cbor(f"{prefix}-IDS", compressed=True) or [])
        return self._ids[prefix]

    def _extra_fields(self):
        """Index `<Prefix>-<id>-<field>` keys once: (prefix, id) -> [field, ...]."""
        if self._fields_by_id is None:
            index = {}
            pat = re.compile(r"(Quest|Npc|Object|Item)-(\d+)-(\d+)$")
            for key in self.kv:
                m = pat.match(key)
                if m:
                    index.setdefault((m.group(1), int(m.group(2))), []).append(int(m.group(3)))
            self._fields_by_id = index
        return self._fields_by_id

    def row(self, prefix, entity_id):
        """Return {field: value} for one entity, or None if it does not exist."""
        data = self._cbor(f"{prefix}-{entity_id}-S")
        extras = self._extra_fields().get((prefix, entity_id), [])
        if data is None and not extras:
            return None
        out = {}
        if isinstance(data, list):
            out = {i + 1: v for i, v in enumerate(data) if v is not None}
        elif isinstance(data, dict):
            out = {k: v for k, v in data.items() if isinstance(k, int)}
        for field in extras:
            if field not in out:
                out[field] = self._cbor(f"{prefix}-{entity_id}-{field}")
        return _text(out)

    def rows(self, prefix):
        """Yield (id, row) for every entity of a type."""
        for entity_id in self.ids(prefix):
            r = self.row(prefix, entity_id)
            if r is not None:
                yield entity_id, r

    def l10n(self, prefix, locale="esMX", column=0):
        """Return {id: translated value} for one l10n column (0 = name, 1 = objectives text)."""
        block = self._cbor(f"l10n-{locale}-{prefix}", compressed=True)
        if not block or len(block) <= column:
            return {}
        values = block[column]
        return {i: _text(v) for i, v in zip(self.ids(prefix), values) if v is not None}


# -- support files (plain Lua, parsed with regexes) ------------------------------------
def load_xp(path=None):
    """Real Forever quest XP from xpDB-traces.lua: {questID: (questLevel, xp)}."""
    text = Path(path or config.XP_TRACES).read_text(encoding="utf-8", errors="replace")
    pat = re.compile(r"QuestXP\.db\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(\d+)")
    return {int(q): (int(a), int(xp)) for q, a, xp in pat.findall(text)}


def load_xp_classic(path=None):
    """Classic-era XP table, used only as a flagged fallback when traces have no entry."""
    p = Path(path or config.XP_CLASSIC)
    if not p.exists():
        return {}
    pat = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{\s*(-?\d+)\s*,\s*(\d+)", re.M)
    return {int(q): (int(a), int(xp)) for q, a, xp in pat.findall(p.read_text(encoding="utf-8", errors="replace"))}


def load_uimap():
    """uiMapID -> (areaID, english name) from QuestieDB, overlaid with config.MAPID_TO_ZONE."""
    out = {}
    p = config.UIMAP_TO_AREA
    if p.exists():
        pat = re.compile(r"^\s*\[(\d+)\]\s*=\s*(\d+),\s*--\s*(.*)$", re.M)
        for ui, area, name in pat.findall(p.read_text(encoding="utf-8", errors="replace")):
            out[int(ui)] = (int(area), name.strip())
    for ui, area in config.MAPID_TO_ZONE.items():
        out[ui] = (area, out.get(ui, (area, ""))[1])
    return out


def load_zone_names():
    """areaID -> English zone name from QuestieDB (uiMap comments first, then zone enums)."""
    names = {}
    p = config.ZONES_ENUM
    if p.exists():
        for sym, area in re.findall(r"^\s*([A-Z0-9_]+)\s*=\s*(\d+),", p.read_text(encoding="utf-8"), re.M):
            names.setdefault(int(area), sym.replace("_", " ").title())
    for area, name in (load_uimap().values()):
        if name and not name.lower().startswith(("referenced", "synthetic")):
            names[area] = name
    return names


def load_drop_rates():
    """Wowhead drop rates: {itemID: {npcID: percent}}."""
    p = config.ITEM_DROPS
    if not p.exists():
        return {}
    rates, current = {}, None
    item_pat = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{")
    npc_pat = re.compile(r"^\s*\[(\d+)\]\s*=\s*([\d.]+),")
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        m = npc_pat.match(line)
        if m and current is not None:
            rates[current][int(m.group(1))] = float(m.group(2))
            continue
        m = item_pat.match(line)
        if m:
            current = int(m.group(1))
            rates[current] = {}
    return rates


if __name__ == "__main__":
    db = QuestieDB()
    for prefix in PREFIXES:
        print(prefix, len(db.ids(prefix)))
    qid = int(sys.argv[1]) if len(sys.argv) > 1 else 5052
    print(qid, db.row("Quest", qid))
