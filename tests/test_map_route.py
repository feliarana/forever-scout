"""Unit tests for the pure parts of tools/map_route.py (no game files needed).

Run with: .venv/bin/python -m unittest discover -s tests -p "test_*.py"
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import map_route  # noqa: E402

# A tiny stand-in for the QuestieDB cache: zone 267 is uiMap 1424, zone 999 has no map.
Q = {"uimap": {1424: (267, "Hillsbrad Foothills"), 1500: (300, "Somewhere")},
     "zones": {267: "Hillsbrad Foothills", 300: "Somewhere", 999: "Nowhere"}, "zones_es": {}}


def stop(x, y, label, kind="kill", phase=0, zone=267):
    return map_route.stop(zone, (x, y), label, kind, phase)


class OrderTest(unittest.TestCase):
    def test_nearest_neighbour_with_turnins_last(self):
        stops = [stop(60, 20, "turn in", "turnin", 1), stop(80, 40, "far"), stop(55, 25, "near")]
        ordered = map_route.order_stops(stops, (50, 30), 267)
        self.assertEqual([s["label"] for s in ordered], ["near", "far", "turn in"])

    def test_a_zone_is_finished_before_moving_on(self):
        stops = [stop(50, 50, "other zone", zone=300), stop(90, 90, "same zone far"), stop(51, 51, "same zone near")]
        ordered = map_route.order_stops(stops, (50, 50), 267)
        self.assertEqual([s["label"] for s in ordered], ["same zone near", "same zone far", "other zone"])

    def test_phase_order_keeps_given_order_and_moves_turnins_to_the_end(self):
        stops = [stop(1, 1, "a"), stop(2, 2, "t1", "turnin", 1), stop(3, 3, "b"), stop(4, 4, "t2", "turnin", 1)]
        self.assertEqual([s["label"] for s in map_route.phase_order(stops)], ["a", "b", "t1", "t2"])


class MergeTest(unittest.TestCase):
    def test_same_spot_becomes_one_turnin_pin(self):
        stops = [stop(61.4, 19.1, "Lydon: Elixir of Agony", "turnin", 1),
                 stop(62.3, 20.4, "Darthalia: Dangerous!", "turnin", 1),
                 stop(61.4, 19.1, "Lydon: Elixir of Pain", "turnin", 1)]
        merged = map_route.merge_stops(stops)
        self.assertEqual(len(merged), 1)
        self.assertEqual(len(merged[0]["parts"]), 3)
        self.assertIn("(+1 more)", merged[0]["label"])
        self.assertLessEqual(len(merged[0]["label"]), map_route.MAX_LABEL)

    def test_distant_stops_and_other_zones_stay_apart(self):
        stops = [stop(10, 10, "a"), stop(40, 40, "b"), stop(40, 40, "c", zone=300)]
        self.assertEqual(len(map_route.merge_stops(stops)), 3)

    def test_identical_labels_are_not_repeated(self):
        merged = map_route.merge_stops([stop(10, 10, "Gray Bear"), stop(10.5, 10, "Gray Bear")])
        self.assertEqual(merged[0]["label"], "Gray Bear")


class CommandTest(unittest.TestCase):
    def test_command_matches_the_wow_ai_map_format(self):
        stops = map_route.merge_stops([stop(64.4, 61.3, "Mudsnout Blossoms", "loot"), stop(61.4, 19.1, "Lydon", "turnin", 1)])
        command = map_route.to_command(Q, stops, "route", "Route: Hillsbrad", loop=False)
        self.assertEqual(command["op"], "set")
        self.assertTrue(command["ordered"])
        self.assertEqual(command["points"][0], {"m": 1424, "x": 64.4, "y": 61.3, "label": "1. Mudsnout Blossoms", "kind": "loot"})
        self.assertEqual(command["points"][1]["label"], "2. Lydon")

    def test_long_labels_are_cut(self):
        stops = map_route.merge_stops([stop(1, 1, "x" * 300)])
        command = map_route.to_command(Q, stops, "route", "t", loop=True)
        self.assertEqual(len(command["points"][0]["label"]), map_route.MAX_LABEL)
        self.assertTrue(command["loop"])

    def test_a_zone_without_a_map_is_an_error(self):
        with self.assertRaises(SystemExit):
            map_route.to_command(Q, map_route.merge_stops([stop(1, 1, "a", zone=999)]), "route", "t", loop=False)

    def test_tomtom_lines(self):
        command = map_route.to_command(Q, map_route.merge_stops([stop(64.4, 61.0, "Blossoms", "loot")]), "route", "t", False)
        self.assertEqual(map_route.to_tomtom(command), ["/way #1424 64.4 61 1. Blossoms"])


class AddonRouteTest(unittest.TestCase):
    """Route.lua must be Lua the addon can read: it is executed here with a real Lua VM."""

    def load(self, source):
        import lupa
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua.execute(source)
        return lua.globals().TrailScoutRoute

    def test_route_file_round_trips_through_lua(self):
        stops = map_route.merge_stops([stop(64.4, 61.3, 'Flores "Morrobarro" \\ñ', "loot"),
                                       stop(61.4, 19.1, "Boticario Lydon: Elixir de agonía", "turnin", 1)])
        command = map_route.to_command(Q, stops, "route", "Route: Laderas de Trabalomas", loop=True)
        route = self.load(map_route.to_lua(command, "2026-11-16 09:00:00"))
        self.assertEqual(route.title, "Route: Laderas de Trabalomas")
        self.assertEqual(route.createdAt, "2026-11-16 09:00:00")
        self.assertTrue(route.loop)
        self.assertEqual(len(route.points), 2)
        first = route.points[1]
        self.assertEqual((first.m, first.x, first.y, first.kind), (1424, 64.4, 61.3, "loot"))
        self.assertEqual(first.label, '1. Flores "Morrobarro" \\ñ')

    def test_clearing_writes_an_empty_route(self):
        self.assertIsNone(self.load(map_route.to_lua(None, "x")))
        self.assertIsNone(self.load(map_route.to_lua({"op": "clear", "layer": "route"}, "x")))

    def test_the_addon_route_file_is_loadable(self):
        # Tracked as an empty placeholder; locally it may hold the last route written.
        path = Path(__file__).resolve().parent.parent / "addon" / "TrailScout" / "Route.lua"
        route = self.load(path.read_text(encoding="utf-8"))
        if route is not None:
            self.assertGreater(len(route.points), 0)


# -- chains ----------------------------------------------------------------------------
def quest(qid, **extra):
    base = {"id": qid, "name": f"Quest {qid}", "name_es": None, "level": 30, "req_level": 20, "races": 0,
            "classes": 0, "objectives": {}, "start_npcs": [], "start_objects": [], "end_npcs": [],
            "end_objects": [], "prereq_all": [], "prereq_any": [], "exclusive_to": [], "next": None,
            "xp": 2000, "xp_classic": None, "zone": 267, "flags": 0}
    base.update(extra)
    return base


def npc(name, x, y, level=30, rank=0, zone=267):
    return {"name": name, "name_es": None, "min_level": level, "max_level": level, "rank": rank,
            "spawns": {zone: [[x, y]]}, "faction": None}


# Town at (60, 20). Quest 1 is in the log (kill farmers, turn in at the Executor) and leads to
# quest 2 (kill peasants, same NPC), which leads to quest 3 whose target is in another zone.
# Quest 4 is a new quest of the zone; quest 5 is a new quest that is too low to bother with.
CQ = {
    "uimap": {1424: (267, "Hillsbrad Foothills")}, "zones": {267: "Hillsbrad Foothills", 400: "Elsewhere"},
    "zones_es": {}, "objects": {}, "items": {}, "drops": {},
    "npcs": {
        10: npc("Executor", 60, 20), 11: npc("Farmer", 30, 40), 12: npc("Peasant", 32, 44),
        13: npc("Far Target", 50, 50, zone=400), 14: npc("Apothecary", 61, 19), 15: npc("Bear", 55, 30),
        16: npc("Rat", 58, 22, level=5),
    },
    "quests": {
        1: quest(1, objectives={1: [[11]]}, start_npcs=[10], end_npcs=[10], next=2),
        2: quest(2, objectives={1: [[12]]}, start_npcs=[10], end_npcs=[10], prereq_all=[1], next=3),
        3: quest(3, objectives={1: [[13]]}, start_npcs=[10], end_npcs=[10], prereq_all=[2]),
        4: quest(4, objectives={1: [[15]]}, start_npcs=[14], end_npcs=[14]),
        5: quest(5, level=12, objectives={1: [[16]]}, start_npcs=[14], end_npcs=[14]),
    },
}
CSNAP = {"level": 30, "completedQuests": [], "quests": [
    {"id": 1, "title": "Quest 1", "objectives": [{"text": "0/6 Farmer", "have": 0, "need": 6, "done": False}]}]}


def roles(stops):
    return [(s["role"], s["quest"]) for s in stops]


class ChainPlanTest(unittest.TestCase):
    def setUp(self):
        import common
        self._identity = dict(common.IDENTITY)
        common.IDENTITY.update({"class": "HUNTER", "race": "Troll", "faction": "Horde"})

    def tearDown(self):
        import common
        common.IDENTITY.update(self._identity)

    def test_turn_ins_pull_in_the_quests_they_unlock(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), accept_new=False)
        self.assertEqual(roles(stops), [
            ("objective", 1), ("turnin", 1),
            ("accept", 2), ("objective", 2), ("turnin", 2),
            ("accept", 3)])
        accept3 = stops[-1]
        self.assertIn("continues elsewhere", accept3["label"], "quest 3's target is in another zone")
        self.assertEqual(stops[2]["needs"], {("turnin", 1)}, "a follow-up waits for the turn-in before it")
        self.assertTrue(stops[1]["unlocks"])

    def test_skipped_quests_are_left_out_with_what_they_unlock(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), accept_new=False, skip={2})
        self.assertEqual(roles(stops), [("objective", 1), ("turnin", 1)], "quest 3 is only reachable through 2")
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), skip={1})
        self.assertEqual({s["quest"] for s in stops}, {4}, "a skipped logged quest is not routed at all")

    def test_without_chains_only_the_log_is_routed(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), chains=False, accept_new=False)
        self.assertEqual(roles(stops), [("objective", 1), ("turnin", 1)])

    def test_new_quests_of_the_zone_are_picked_up_when_worth_their_xp(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), chains=False)
        picked = {s["quest"] for s in stops if s["role"] == "accept"}
        self.assertEqual(picked, {4}, "quest 5 is far below the character's level")

    def test_quests_already_done_or_in_the_log_are_not_picked_up(self):
        snap = dict(CSNAP, completedQuests=[4])
        stops = map_route.chain_plan(CQ, snap, 267, (60, 20), chains=False)
        self.assertEqual({s["quest"] for s in stops}, {1})


class ScheduleTest(unittest.TestCase):
    def setUp(self):
        import common
        self._identity = dict(common.IDENTITY)
        common.IDENTITY.update({"class": "HUNTER", "race": "Troll", "faction": "Horde"})

    def tearDown(self):
        import common
        common.IDENTITY.update(self._identity)

    def test_order_respects_dependencies_along_the_chain(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), accept_new=False)
        ordered, dropped = map_route.schedule(stops, (60, 20), 267, free_slots=5)
        self.assertEqual(dropped, [])
        order = roles(ordered)
        self.assertLess(order.index(("objective", 1)), order.index(("turnin", 1)))
        self.assertLess(order.index(("turnin", 1)), order.index(("accept", 2)))
        self.assertLess(order.index(("accept", 2)), order.index(("objective", 2)))
        self.assertLess(order.index(("objective", 2)), order.index(("turnin", 2)))
        self.assertLess(order.index(("turnin", 2)), order.index(("accept", 3)))

    def test_a_new_quest_next_to_the_start_is_accepted_first_when_the_log_has_room(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), chains=False)
        ordered, _ = map_route.schedule(stops, (60, 20), 267, free_slots=1)
        self.assertEqual(roles(ordered)[0], ("accept", 4))

    def test_with_a_full_log_a_new_quest_waits_for_a_turn_in_to_free_a_slot(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), chains=False)
        ordered, dropped = map_route.schedule(stops, (60, 20), 267, free_slots=0)
        order = roles(ordered)
        self.assertEqual(dropped, [])
        self.assertLess(order.index(("turnin", 1)), order.index(("accept", 4)))

    def test_a_follow_up_takes_the_slot_its_turn_in_frees(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), accept_new=False)
        ordered, dropped = map_route.schedule(stops, (60, 20), 267, free_slots=0)
        self.assertEqual(dropped, [])
        self.assertIn(("accept", 2), roles(ordered))

    def test_a_turn_in_that_unlocks_nothing_waits_for_nearby_work(self):
        town = dict(stop(60, 20, "town turn-in", "turnin", 1), role="turnin", quest=9, key=("turnin", 9), needs=set())
        near = dict(stop(70, 30, "work", "kill"), role="objective", quest=8, key=("objective", 8, 0), needs=set())
        ordered, _ = map_route.schedule([town, near], (60, 20), 267, free_slots=1)
        self.assertEqual([s["label"] for s in ordered], ["work", "town turn-in"])
        # ...but not when turning it in opens the next quest.
        town["unlocks"] = True
        ordered, _ = map_route.schedule([town, near], (60, 20), 267, free_slots=1)
        self.assertEqual([s["label"] for s in ordered], ["town turn-in", "work"])

    def test_merged_pins_keep_turn_in_and_follow_up_together(self):
        stops = map_route.chain_plan(CQ, CSNAP, 267, (60, 20), accept_new=False)
        ordered, _ = map_route.schedule(stops, (60, 20), 267, free_slots=5)
        merged = map_route.merge_stops(ordered)
        town = [m for m in merged if any("accept from Executor: Quest 2" in p for p in m["parts"])][0]
        self.assertTrue(any(p.startswith("Executor: Quest 1") for p in town["parts"]),
                        "turning in quest 1 and accepting quest 2 is one stop at the same NPC")
        self.assertEqual(town["kind"], "turnin")


class EliteMarkTest(unittest.TestCase):
    def test_a_stop_whose_every_source_is_elite_says_so(self):
        Q2 = dict(CQ, npcs={**CQ["npcs"], 20: npc("Guard", 70, 80, rank=1)})
        q = quest(7, objectives={1: [[20]]})
        stops, finishable = map_route.objective_stops(Q2, q, {}, 267)
        self.assertTrue(finishable)
        self.assertEqual(stops[0]["label"], "Guard (elite)")


if __name__ == "__main__":
    unittest.main()
