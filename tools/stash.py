"""What the account holds outside the character's bags (bank, mail, other characters) and how
it helps the quest log. Pure functions that return lines of text, used by analyze.py.

`rows` is the result of common.collect_items(): {itemID: {"where": {"Char:place": count}}}
with place in bags, bank or mail. Bank and mail come from the Syndicator addon.
"""


def _held(rows, item_id, skip=None):
    """{"Char:place": count} for an item, without the `skip` location."""
    where = (rows.get(item_id) or {}).get("where") or {}
    return {loc: n for loc, n in where.items() if loc != skip and n}


def _fmt(held):
    return ", ".join(f"{loc} x{n}" for loc, n in sorted(held.items()))


def quest_lines(log, quests, rows, main, parts, name_of):
    """Lines for quest items found away from `main`'s bags, and for objectives assembled from
    parts. `log` is the snapshot quest list, `quests` the QuestieDB quests, `parts` is
    config.ITEM_PARTS, `name_of(itemID)` a display name."""
    lines = []
    own_bags = f"{main}:bags"
    for lq in log or []:
        q = quests.get(lq.get("id"))
        if not q or lq.get("complete"):
            continue
        found = []
        for entry in (q.get("objectives") or {}).get(3, []):
            item_id = entry[0] if isinstance(entry, list) else entry
            elsewhere = _held(rows, item_id, skip=own_bags)
            if elsewhere:
                found.append(f"    {name_of(item_id)}: {_fmt(elsewhere)}")
            pieces = parts.get(item_id) or []
            owned = {p: _held(rows, p) for p in pieces}
            if any(owned.values()):
                have = "; ".join(f"{name_of(p)} ({_fmt(h)})" for p, h in owned.items() if h)
                missing = [name_of(p) for p, h in owned.items() if not h]
                tail = f" — still missing: {', '.join(missing)}" if missing else " — all parts owned: assemble it"
                found.append(f"    {name_of(item_id)} is made from parts you hold: {have}{tail}")
        if found:
            lines.append(f"[{lq.get('id')}] {lq.get('title')}")
            lines += found
    return lines


def coverage_lines(characters, now, warn_days):
    """One line per character Syndicator knows: how much sits in bank and mail, and mail that
    is about to expire. `characters` is {name: {"bank": n, "mail": [expiry epoch | None]}}."""
    if not characters:
        return ["Bank and mail: no data. Install the Syndicator addon, open the bank and the mailbox "
                "once with each character, then /reload."]
    lines = []
    for name in sorted(characters):
        data = characters[name]
        mail = data.get("mail") or []
        line = f"{name}: bank {data.get('bank') or 0} items, mail {len(mail)} items"
        expiries = sorted(e for e in mail if e)
        if expiries:
            days = (expiries[0] - now) / 86400
            if days < 0:
                line += " — !! some mail has already expired"
            elif days <= warn_days:
                soon = sum(1 for e in expiries if (e - now) / 86400 <= warn_days)
                line += f" — !! {soon} mail item(s) expire within {max(0, int(days))} day(s): collect them"
            else:
                line += f" (first expires in {int(days)} days)"
        lines.append(line)
    lines.append("Bank and mail are as of the last time each was opened in game.")
    return lines
