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
        return lua.globals().ForeverScoutRoute

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

    def test_the_tracked_placeholder_matches_an_empty_route(self):
        placeholder = Path(__file__).resolve().parent.parent / "addon" / "ForeverScout" / "Route.lua"
        self.assertEqual(placeholder.read_text(encoding="utf-8"), map_route.to_lua(None, "x"))


if __name__ == "__main__":
    unittest.main()
