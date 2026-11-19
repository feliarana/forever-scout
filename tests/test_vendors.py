"""Quest items that are bought, not looted: the vendor is the place to go.

Run with: .venv/bin/python -m unittest discover -s tests -p "test_*.py"
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import common  # noqa: E402
import map_route  # noqa: E402

Q = {
    "uimap": {1424: (267, "Hillsbrad Foothills")}, "zones": {267: "Hillsbrad Foothills"}, "zones_es": {},
    "objects": {}, "drops": {900: {3: 40}},
    "npcs": {
        1: {"name": "Derak Nightfall", "name_es": None, "min_level": 30, "max_level": 30, "rank": 0,
            "spawns": {267: [[63.1, 19.4]]}, "faction": "H"},
        2: {"name": "Alliance Grocer", "name_es": None, "min_level": 30, "max_level": 30, "rank": 0,
            "spawns": {267: [[50.0, 58.0]]}, "faction": "A"},
        3: {"name": "Snapjaw", "name_es": None, "min_level": 30, "max_level": 31, "rank": 0,
            "spawns": {267: [[63.8, 35.6]]}, "faction": None},
    },
    "items": {
        900: {"name": "Turtle Meat", "name_es": None, "npcs": [3], "objects": [], "vendors": [1]},
        901: {"name": "Soothing Spices", "name_es": None, "npcs": [], "objects": [], "vendors": [2, 1]},
    },
}
QUEST = {"id": 7321, "objectives": {1: [], 2: [], 3: [[900], [901]]}}


class VendorTargetTest(unittest.TestCase):
    def setUp(self):
        self._identity = dict(common.IDENTITY)
        common.IDENTITY.update({"faction": "Horde"})

    def tearDown(self):
        common.IDENTITY.update(self._identity)

    def test_an_item_nothing_drops_is_placed_at_its_own_faction_vendor(self):
        meat, spices = common.objective_targets(Q, QUEST)
        self.assertTrue(spices["bought"])
        self.assertEqual(spices["points"], {267: [(63.1, 19.4)]})
        self.assertEqual([s["label"] for s in spices["sources"]], ["Derak Nightfall"])
        self.assertEqual(common.fmt_source(spices["sources"][0]), "Derak Nightfall (vendor)")
        self.assertEqual(common.vendors_in(Q, spices, 267), [("Derak Nightfall", (63.1, 19.4))])

    def test_an_item_that_also_drops_keeps_its_stop_on_the_drop(self):
        meat, _ = common.objective_targets(Q, QUEST)
        self.assertFalse(meat["bought"])
        self.assertEqual(meat["points"], {267: [(63.8, 35.6)]})
        self.assertEqual([s["kind"] for s in meat["sources"]], ["npc", "vendor"])

    def test_the_route_gets_a_buy_stop_naming_the_vendor(self):
        stops, finishable = map_route.objective_stops(Q, QUEST, {}, 267)
        self.assertTrue(finishable)
        self.assertEqual([(s["label"], s["kind"]) for s in stops],
                         [("Turtle Meat", "loot"), ("Buy Soothing Spices (Derak Nightfall)", "buy")])


if __name__ == "__main__":
    unittest.main()
