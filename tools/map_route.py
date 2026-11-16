"""Turn quests and waypoints into a numbered route drawn on the in-game world map.

Usage: map_route.py [--char NAME] [options] [STOP ...]

STOP is one of:
  ZONE:X,Y[=label]   a waypoint (ZONE is a zone ID or partial English/esMX name)
  QUESTID            the unfinished objectives of that quest and its turn-in
  turnin:QUESTID     only the turn-in of that quest
With no STOP, the route covers every logged quest that has something to do in --zone; a
turn-in is only included when the quest is complete or can be completed on that route.

Options:
  --zone ZONE     zone for quest stops and the no-STOP mode (default: where the character is)
  --optimize      reorder the stops by nearest neighbour from the character's position
                  (always on in the no-STOP mode). Without it, stops keep the order given,
                  with every turn-in moved to the end
  --loop          mark the route as a circuit
  --layer NAME    map layer to replace (default: route)
  --title TEXT    layer title (default: built from the zone)
  --clear         remove the layer instead of setting it
  --tomtom        print TomTom "/way" lines instead of a map layer
  --out FILE      append the map command to FILE (default: $WOW_AI_MAP_FILE, else stdout)
  --addon         write the route into the installed ForeverScout addon (Route.lua); after a
                  /reload, "/scout route" walks it with TomTom. With --clear it empties it

Output is one JSON map command per line, the format the wow-ai bridge reads from
$WOW_AI_MAP_FILE (https://github.com/chelinho139/wow-ai, docs/MAP.md): numbered pins joined by
lines, with a navigator arrow that walks from stop to stop. Objectives go first, turn-ins last.
"""
import json
import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402  (puts the repo root on sys.path for config)
import config  # noqa: E402
from common import (  # noqa: E402
    cluster, dist, load_q, load_snapshot, npc_name, object_name, objective_targets, player_pos,
    quest_name, resolve_zone, spawns_of, take_char_arg, zone_name,
)

# Stops closer than this (map percent) are shown as one pin with both labels.
MERGE_RADIUS = 2.5
# wow-ai keeps at most 400 points per layer; a route that long is not walkable anyway.
MAX_POINTS = 60
MAX_LABEL = 80
# Objective kind -> wow-ai pin kind.
PIN_KINDS = {"mob": "kill", "object": "object", "item": "loot"}


def ui_map_of(Q, zone):
    """uiMapID of a QuestieDB zone, or None. The author's verified pairs win."""
    for ui, z in config.MAPID_TO_ZONE.items():
        if z == zone:
            return ui
    candidates = sorted(ui for ui, (area, _) in Q["uimap"].items() if area == zone)
    return candidates[0] if candidates else None


def short_name(label):
    """Client-language half of an "English / esMX" label, to keep pin labels short."""
    return label.split(" / ")[-1]


def stop(zone, point, label, kind, phase):
    """phase 0 = do on the way (objectives, waypoints), 1 = turn-ins, visited last."""
    return {"zone": zone, "x": round(point[0], 1), "y": round(point[1], 1), "label": label,
            "kind": kind, "phase": phase}


def objective_stops(Q, q, log_quest, zone):
    """(stops, finishable). One stop per unfinished objective that has spawns in `zone`: the
    centre of its biggest spawn cluster. Objectives the snapshot marks done are skipped.
    `finishable` is False when an unfinished objective is elsewhere or has no known spawns,
    or when QuestieDB lists no objectives at all (explore, talk-to and event quests)."""
    done = [o.get("text") or "" for o in log_quest.get("objectives") or [] if o.get("done")]
    targets = objective_targets(Q, q)
    stops, finishable = [], bool(targets)
    for target in targets:
        name = short_name(target["label"])
        if any(name in text for text in done):
            continue
        points = target["points"].get(zone)
        if not points:
            finishable = False
            continue
        _, centre = cluster(points)[0]
        stops.append(stop(zone, centre, name, PIN_KINDS[target["kind"]], 0))
    return stops, finishable


def turnin_stops(Q, q, zone, near):
    """The turn-in NPC or object in `zone` nearest to `near` (first one found otherwise)."""
    best = None
    for kind, ids, namer in (("npc", q["end_npcs"], npc_name), ("obj", q["end_objects"], object_name)):
        for eid in ids or []:
            points = spawns_of(Q, kind, eid).get(zone)
            if not points:
                continue
            point = min(points, key=lambda p: dist(p, near)) if near else points[0]
            d = dist(point, near) if near else 0
            if best is None or d < best[0]:
                best = (d, point, short_name(namer(Q, eid)))
    if not best:
        return []
    return [stop(zone, best[1], f"{best[2]}: {short_name(quest_name(Q, q['id']))}", "turnin", 1)]


def quest_stops(Q, snap, qid, zone, near, turnin_only=False, strict=False):
    """Stops of one quest in `zone`. With `strict` (the no-STOP mode) the turn-in is only
    added when the quest is complete or can be completed on this route, so the route never
    ends on an NPC who has nothing to take yet."""
    q = Q["quests"].get(qid)
    if not q:
        sys.exit(f"Quest {qid} is not in QuestieDB")
    q = dict(q, id=qid)
    log_quest = next((lq for lq in snap.get("quests") or [] if lq.get("id") == qid), {})
    stops, finishable = [], True
    if not turnin_only and not log_quest.get("complete"):
        stops, finishable = objective_stops(Q, q, log_quest, zone)
    if strict and not finishable:
        return stops
    return stops + turnin_stops(Q, q, zone, near)


def parse_stop(Q, snap, arg, zone, near):
    if arg.lower().startswith("turnin:"):
        return quest_stops(Q, snap, int(arg.split(":", 1)[1]), zone, near, turnin_only=True)
    if arg.isdigit():
        return quest_stops(Q, snap, int(arg), zone, near)
    where, _, label = arg.partition("=")
    zone_token, sep, xy = where.rpartition(":")
    if not sep:
        sys.exit(f"Invalid stop (use ZONE:X,Y[=label], QUESTID or turnin:QUESTID): {arg}")
    try:
        x, y = (float(v) for v in xy.split(","))
    except ValueError:
        sys.exit(f"Invalid coordinates in stop: {arg}")
    return [stop(resolve_zone(Q, zone_token), (x, y), label or f"{x:g}, {y:g}", "poi", 0)]


def order_stops(stops, start, start_zone):
    """Nearest neighbour from `start` in `start_zone`, all phase-0 stops before any phase-1
    stop. Stops in another zone than the previous one are treated as far away, so a zone is
    finished first."""
    ordered, here, here_zone = [], start, start_zone
    for phase in (0, 1):
        pool = [s for s in stops if s["phase"] == phase]
        while pool:
            def cost(s):
                far = 0 if s["zone"] == here_zone else 1000
                return far + (dist((s["x"], s["y"]), here) if here else 0)
            nxt = min(pool, key=cost)
            pool.remove(nxt)
            ordered.append(nxt)
            here, here_zone = (nxt["x"], nxt["y"]), nxt["zone"]
    return ordered


def merge_stops(stops):
    """Fold a stop into the previous one when both sit on the same spot (one NPC taking three
    turn-ins becomes one pin), keeping the order. Every merged stop keeps its own text in
    `parts`; the pin label names the first two and counts the rest."""
    merged = []
    for s in stops:
        prev = merged[-1] if merged else None
        if prev and prev["zone"] == s["zone"] and dist((prev["x"], prev["y"]), (s["x"], s["y"])) <= MERGE_RADIUS:
            if s["label"] not in prev["parts"]:
                prev["parts"].append(s["label"])
            if s["kind"] == "turnin":
                prev["kind"] = "turnin"
        else:
            merged.append(dict(s, parts=[s["label"]]))
    for m in merged:
        # Name two parts when they fit, else one; the rest is a count (the console lists all).
        shown = 2 if len(" + ".join(m["parts"][:2])) <= MAX_LABEL - 20 else 1
        extra = len(m["parts"]) - shown
        m["label"] = " + ".join(m["parts"][:shown]) + (f" (+{extra} more)" if extra > 0 else "")
    return merged


def phase_order(stops):
    """Keep the given order but move turn-ins to the end, so the route does not run back to
    town between quests."""
    return sorted(stops, key=lambda s: s["phase"])


def to_command(Q, stops, layer, title, loop):
    points = []
    for i, s in enumerate(stops, 1):
        ui = ui_map_of(Q, s["zone"])
        if ui is None:
            sys.exit(f"No uiMapID known for {zone_name(Q, s['zone'])}: add it to config.MAPID_TO_ZONE")
        label = f"{i}. {s['label']}"
        if len(label) > MAX_LABEL:
            label = label[:MAX_LABEL - 1] + "…"
        points.append({"m": ui, "x": s["x"], "y": s["y"], "label": label, "kind": s["kind"]})
    return {"op": "set", "layer": layer, "title": title, "ordered": True, "loop": bool(loop), "points": points}


def describe(stops):
    """Console lines: every stop with everything merged into it."""
    lines = []
    for i, s in enumerate(stops, 1):
        lines.append(f"  {i}. ({s['x']:g}, {s['y']:g}) [{s['kind']}] {s['parts'][0]}")
        lines += [f"       + {part}" for part in s["parts"][1:]]
    return lines


ROUTE_FILE_HEADER = (
    '-- Route for "/scout route". tools/map_route.py --addon rewrites this file with the stops of a\n'
    "-- route; the game reads it again on every /reload. Empty until a route is written.\n"
)


def lua_string(text):
    """A Lua string literal. JSON escapes for quotes, backslashes and newlines are valid Lua
    too, and non-ASCII text is kept as UTF-8."""
    return json.dumps(str(text), ensure_ascii=False)


def to_lua(command, created_at):
    """Contents of the addon's Route.lua for a map command (None empties the route).
    `created_at` identifies the route, so the addon can tell a new one from a resumed one."""
    if not command or command.get("op") != "set":
        return ROUTE_FILE_HEADER + "ForeverScoutRoute = nil\n"
    lines = [ROUTE_FILE_HEADER + "ForeverScoutRoute = {",
             f"  title = {lua_string(command['title'])},",
             f"  createdAt = {lua_string(created_at)},",
             f"  loop = {'true' if command.get('loop') else 'false'},",
             "  points = {"]
    for p in command["points"]:
        lines.append(f"    {{ m = {int(p['m'])}, x = {p['x']:g}, y = {p['y']:g}, "
                     f"label = {lua_string(p['label'])}, kind = {lua_string(p['kind'])} }},")
    lines += ["  },", "}"]
    return "\n".join(lines) + "\n"


def write_addon_route(command):
    """Write Route.lua into the installed addon. Returns the path written."""
    folder = config.ADDONS_DIR / "ForeverScout"
    if not folder.is_dir():
        sys.exit(f"ForeverScout is not installed in {config.ADDONS_DIR}: install the addon first")
    path = folder / "Route.lua"
    existed = path.exists()
    path.write_text(to_lua(command, datetime.now().strftime("%Y-%m-%d %H:%M:%S")), encoding="utf-8")
    return path, existed


def to_tomtom(command):
    """TomTom waypoint lines, one per stop ("#<uiMapID>" selects the map)."""
    return [f"/way #{p['m']} {p['x']:g} {p['y']:g} {p['label']}" for p in command["points"]]


def take_option(args, name, has_value=True):
    if name not in args:
        return None if has_value else False
    i = args.index(name)
    if not has_value:
        del args[i]
        return True
    if i + 1 >= len(args):
        sys.exit(f"{name} needs a value")
    value = args[i + 1]
    del args[i:i + 2]
    return value


def main():
    take_char_arg()
    args = sys.argv[1:]
    if "-h" in args or "--help" in args:
        sys.exit(__doc__)
    layer = take_option(args, "--layer") or "route"
    title = take_option(args, "--title")
    out = take_option(args, "--out") or os.environ.get("WOW_AI_MAP_FILE")
    zone_arg = take_option(args, "--zone")
    optimize = take_option(args, "--optimize", False)
    loop = take_option(args, "--loop", False)
    tomtom = take_option(args, "--tomtom", False)
    clear = take_option(args, "--clear", False)
    addon = take_option(args, "--addon", False)
    unknown = [a for a in args if a.startswith("--")]
    if unknown:
        sys.exit(f"Unknown option: {unknown[0]}")

    if clear:
        command = {"op": "clear", "layer": layer}
    else:
        Q = load_q()
        snap, _ = load_snapshot()
        here_zone, x, y = player_pos(Q, snap)
        zone = resolve_zone(Q, zone_arg) if zone_arg else here_zone
        if zone is None:
            sys.exit("Cannot tell which zone the character is in: pass --zone")
        # Distances only make sense from the character when it stands in the route's zone.
        start = (x, y) if x is not None and zone == here_zone else None

        if args:
            stops = [s for arg in args for s in parse_stop(Q, snap, arg, zone, start)]
        else:
            optimize = True
            stops = [s for lq in snap.get("quests") or [] if lq.get("id") in Q["quests"]
                     for s in quest_stops(Q, snap, lq["id"], zone, start, strict=True)]
        if not stops:
            sys.exit(f"Nothing to route in {zone_name(Q, zone)}")
        stops = order_stops(stops, start, zone) if optimize else phase_order(stops)
        stops = merge_stops(stops)
        if len(stops) > MAX_POINTS:
            sys.exit(f"{len(stops)} stops is too many for one route (max {MAX_POINTS}): pick quests or a zone")
        command = to_command(Q, stops, layer, title or f"Route: {short_name(zone_name(Q, zone))}", loop)

    if tomtom:
        if clear:
            sys.exit("--clear has no TomTom equivalent: use /way reset all in game")
        print("\n".join(to_tomtom(command)))
        return
    if addon:
        path, existed = write_addon_route(None if clear else command)
        if clear:
            print(f"Route emptied -> {path}\n/reload in game to apply.")
        else:
            print(f"Route with {len(command['points'])} stops -> {path}")
            print("\n".join(describe(stops)))
            print("In game: /reload, then /scout route (needs TomTom). /scout route next moves on.")
        if not existed:
            print("Route.lua did not exist before: restart the game once so the client picks it up.")
        return
    line = json.dumps(command, ensure_ascii=False)
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        count = len(command.get("points") or [])
        print(f"Map layer '{layer}' " + ("cleared" if clear else f"set with {count} stops") + f" -> {out}")
        if not clear:
            print("\n".join(describe(stops)))
    else:
        print(line)


if __name__ == "__main__":
    main()
