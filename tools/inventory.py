"""What to vendor, auction, keep or turn in, across every character's bags, bank and mail.

Covers every character on the account (mains, alts, bank alts): items mailed to a bank alt
show up under that character's mail until collected.

Usage: inventory.py [--all]
  --all also lists items with no price data at all.

Sources (read live):
  * ForeverScout snapshots (every character that has one): item type and vendor price.
  * Syndicator: bags, bank tabs and mail of every character on the account.
  * Auctionator: AH price database (CBOR blob per realm key) and vendor price cache.
Rules:
  * KEEP: config.KEEP_ITEMS, quest items, and items needed by any character's quest log.
  * TURN IN: bound items that are the objective of a quest their holder has not completed.
  * AUCTION: unbound, seen on the AH, and AH price after the cut beats the vendor price.
  * VENDOR: anything else with a vendor price.
  * USE: consumables that cannot be sold (containers, camp items): use or open them.
"""
import datetime as dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import config  # noqa: E402
from common import (  # noqa: E402
    char_name, collect_items as collect, fits_character, identity_of, is_horde_ok, load_q, money,
    quest_name, snapshots, syndicator_characters,
)

AUCTIONATOR_EPOCH = dt.date(2020, 1, 1)  # Auctionator day keys count days from this date
QUEST_TYPES = {"Misión", "Quest"}
CONSUMABLE_TYPES = {"Consumible", "Consumable"}


# -- loading ---------------------------------------------------------------------------
def load_auctionator():
    """Return (prices, vendor_cache, latest_scan_date).
    prices: {itemID: {"min": copper, "seen": count on latest day, "day": date}}"""
    import cbor2
    import lupa

    if not config.AUCTIONATOR_SV.exists():
        return {}, {}, None
    lua = lupa.LuaRuntime(encoding=None, register_eval=False)
    lua.execute(config.AUCTIONATOR_SV.read_bytes())
    g = lua.globals()
    prices, latest = {}, None
    db = g[b"AUCTIONATOR_PRICE_DATABASE"]
    if db is not None:
        for key, blob in db.items():
            realm = key.decode() if isinstance(key, bytes) else str(key)
            if realm.startswith("__") or not isinstance(blob, bytes):
                continue
            if config.AUCTION_REALM_KEY and realm != config.AUCTION_REALM_KEY:
                continue
            for raw_id, entry in cbor2.loads(blob).items():
                sid = raw_id.decode() if isinstance(raw_id, bytes) else str(raw_id)
                if not sid.isdigit() or not isinstance(entry, dict):
                    continue
                days = entry.get(b"a") or {}
                last = max((int(d) for d in days), default=None)
                day = AUCTIONATOR_EPOCH + dt.timedelta(days=last) if last is not None else None
                if day and (latest is None or day > latest):
                    latest = day
                prices[int(sid)] = {"min": entry.get(b"m"), "seen": days.get(str(last).encode()) if last else None,
                                    "day": day}
    vendor = {}
    cache = g[b"AUCTIONATOR_VENDOR_PRICE_CACHE"]
    if cache is not None:
        for k, v in cache.items():
            sk = k.decode() if isinstance(k, bytes) else str(k)
            if sk.isdigit():
                vendor[int(sk)] = v
    return prices, vendor, latest


# -- classification --------------------------------------------------------------------
def quest_uses(Q, snaps):
    """Per character with a snapshot: (log_needs, open_objectives), each {char: {itemID: questID}}.
    log_needs: items needed by quests in that character's log; open_objectives: items that are
    the objective of a quest the character has not completed and can take (race/class/faction)."""
    log_needs, open_obj = {}, {}
    for d, (snap, _) in snaps.items():
        char, ident = char_name(d), identity_of(d)
        done = set(snap.get("completedQuests") or [])
        in_log = {q.get("id") for q in snap.get("quests") or []}
        needs, opens = log_needs.setdefault(char, {}), open_obj.setdefault(char, {})
        for q in Q["quests"].values():
            if q["id"] in done or not fits_character(q, ident) or not is_horde_ok(Q, q, ident):
                continue
            for e in q["objectives"].get(3, []):
                iid = e[0] if isinstance(e, list) else e
                (needs if q["id"] in in_log else opens).setdefault(iid, q["id"])
                # The parts an objective is assembled from are needed too (pages of a manual).
                if q["id"] in in_log:
                    for part in config.ITEM_PARTS.get(iid, []):
                        needs.setdefault(part, q["id"])
    return log_needs, open_obj


def classify(r, Q, prices, vendor_cache, log_needs, open_obj):
    iid = r["id"]
    vendor = r["sell"] if r["sell"] is not None else vendor_cache.get(iid)
    ah = prices.get(iid) or {}
    ah_net = int(ah["min"] * (1 - config.AH_CUT)) if ah.get("min") else None
    r["vendor"], r["ah"], r["ah_net"] = vendor, ah, ah_net

    if iid in config.KEEP_ITEMS:
        return "KEEP", config.KEEP_ITEMS[iid]
    if r.get("type") in QUEST_TYPES:
        return "KEEP", "quest item"
    # Any character's quest log counts: unbound items can be mailed to whoever needs them.
    for char, needs in log_needs.items():
        if iid in needs:
            return "KEEP", f"{char} needs it for [{needs[iid]}] {quest_name(Q, needs[iid])}"
    # Bound items can only be turned in by the character holding them.
    for char in sorted(r["chars"]):
        if r["bound"] and iid in open_obj.get(char, {}):
            qid = open_obj[char][iid]
            return "TURN IN", f"{char}: [{qid}] {quest_name(Q, qid)}"
    if not r["bound"] and ah_net and ah_net > (vendor or 0):
        return "AUCTION", f"AH {money(ah['min'])} each ({ah.get('seen') or '?'} listed on {ah.get('day')})"
    if vendor:
        note = f"vendor {money(vendor)} each"
        if not r["bound"] and not ah:
            note += " (not seen on AH)"
        return "VENDOR", note
    if vendor == 0 and r.get("type") in CONSUMABLE_TYPES:
        req = r.get("reqLevel") or 0
        return "USE", "consumable with no sale value: use or open it" + (f" (requires level {req})" if req > 1 else "")
    if vendor == 0:
        return "NO VALUE", "vendor pays nothing" + ("" if r["bound"] else " and not seen on AH")
    if r["bound"]:
        return "NO VALUE", "bound, no vendor price: destroy if useless"
    return "UNKNOWN", "no AH or vendor data"


def characters_summary(snaps):
    """One line per known character: level, gold, free bag slots, snapshot/Syndicator coverage."""
    syn = syndicator_characters()
    names = {char_name(d): d for d in config.character_dirs()}
    print("Characters:")
    for char in sorted(set(names) | set(syn)):
        snap = snaps.get(names.get(char), ({}, {}))[0] if char in names else {}
        up = snap.get("upkeep") or {}
        money_cp = snap.get("money") if snap else (syn.get(char) or {}).get("money")
        bits = []
        if snap:
            bits.append(f"level {snap.get('level')}")
        if money_cp is not None:
            bits.append(money(money_cp))
        if up.get("freeSlots") is not None:
            full = " !! FULL" if up["freeSlots"] <= 2 else ""
            bits.append(f"{up['freeSlots']}/{up.get('totalSlots')} bag slots free{full}")
        src = []
        if snap:
            src.append(f"snapshot {snap.get('savedAt')}")
        if char in syn:
            src.append("Syndicator")
        print(f"  {char}: " + ", ".join(bits + [" + ".join(src) or "no data (log in once with the addons)"]))
    print()


def main():
    show_all = "--all" in sys.argv
    Q = load_q()
    snaps = snapshots()
    prices, vendor_cache, latest = load_auctionator()
    log_needs, open_obj = quest_uses(Q, snaps)
    rows = collect(snaps)
    characters_summary(snaps)

    age = (dt.date.today() - latest).days if latest else None
    print(f"Auctionator: {len(prices)} prices, latest scan {latest or 'never'}"
          + (f" ({age} days ago)" if age is not None else ""))
    if age is None or age > 2:
        print("  !! Prices are stale or missing: run an Auctionator full scan and /reload")
    owned = [r for r in rows.values() if r["id"] in prices]
    print(f"  {len(owned)} of your {len(rows)} distinct items have an AH price\n")

    groups = {}
    for r in rows.values():
        action, note = classify(r, Q, prices, vendor_cache, log_needs, open_obj)
        groups.setdefault(action, []).append((r, note))

    order = ["TURN IN", "AUCTION", "VENDOR", "USE", "KEEP", "NO VALUE", "UNKNOWN"]
    for action in order:
        items = groups.get(action, [])
        if not items:
            continue
        total = 0
        print(f"== {action} ({len(items)}) ==")

        def value(item):
            r = item[0]
            unit = r["ah_net"] if action == "AUCTION" else (r["vendor"] or 0)
            return (unit or 0) * sum(r["where"].values())

        priced = action in ("AUCTION", "VENDOR")
        for r, note in sorted(items, key=lambda it: (-value(it) if priced else 0, it[0]["name"] or "")):
            count = sum(r["where"].values())
            v = value((r, note))
            total += v
            where = ", ".join(f"{k} x{n}" for k, n in r["where"].items())
            if action == "UNKNOWN" and not show_all:
                continue
            worth = f"{money(v):>12}  " if priced else ""
            print(f"  {worth}  {r['name']} x{count} [{r['id']}] — {note} — {where}")
        if action in ("AUCTION", "VENDOR"):
            label = "after AH cut" if action == "AUCTION" else "at vendor"
            print(f"  total ≈ {money(total)} {label}")
        if action == "UNKNOWN" and not show_all:
            print("  (use --all to list them)")
        print()


if __name__ == "__main__":
    main()
