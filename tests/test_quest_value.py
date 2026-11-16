"""Unit tests for tools/quest_value.py: the XP-per-minute estimate.

Run with: .venv/bin/python -m unittest discover -s tests -p "test_*.py"
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import quest_value as qv  # noqa: E402

# A tiny quest database: zone 267 (uiMap 1424), one kill quest, one drop quest, one elsewhere.
Q = {
    "zones": {267: "Hillsbrad Foothills", 400: "Thousand Needles"}, "zones_es": {},
    "uimap": {1424: (267, "Hillsbrad Foothills"), 1441: (400, "Thousand Needles")},
    "npcs": {
        1: {"name": "Quest Giver", "name_es": None, "min_level": 30, "max_level": 30, "rank": 0, "spawns": {267: [[60, 20]]}},
        2: {"name": "Farmer", "name_es": None, "min_level": 28, "max_level": 28, "rank": 0, "spawns": {267: [[30, 40], [31, 41]]}},
        3: {"name": "Gray Bear", "name_es": None, "min_level": 21, "max_level": 22, "rank": 0, "spawns": {267: [[55, 30]]}},
        4: {"name": "Harpy", "name_es": None, "min_level": 30, "max_level": 30, "rank": 0, "spawns": {400: [[20, 20]]}},
        5: {"name": "Elite Guard", "name_es": None, "min_level": 30, "max_level": 30, "rank": 1, "spawns": {267: [[70, 80]]}},
        6: {"name": "Elder", "name_es": None, "min_level": 30, "max_level": 30, "rank": 0, "spawns": {400: [[45, 50]]}},
    },
    "objects": {}, "items": {900: {"name": "Bear Tongue", "name_es": None, "npcs": [3], "objects": []}},
    "drops": {900: {3: 50.0}},
    "quests": {
        10: {"id": 10, "name": "Quest 10", "name_es": None, "level": 30, "xp": 2000, "xp_classic": None, "objectives": {1: [[2]]}, "end_npcs": [1], "end_objects": []},
        11: {"id": 11, "name": "Quest 11", "name_es": None, "level": 22, "xp": 800, "xp_classic": None, "objectives": {3: [[900]]}, "end_npcs": [1], "end_objects": []},
        12: {"id": 12, "name": "Quest 12", "name_es": None, "level": 30, "xp": 2400, "xp_classic": None, "objectives": {1: [[4]]}, "end_npcs": [6], "end_objects": []},
        13: {"id": 13, "name": "Quest 13", "name_es": None, "level": 30, "xp": 3000, "xp_classic": None, "objectives": {1: [[5]]}, "end_npcs": [1], "end_objects": []},
        14: {"id": 14, "name": "Quest 14", "name_es": None, "level": 30, "xp": 1000, "xp_classic": None, "objectives": {}, "end_npcs": [1], "end_objects": []},
    },
}
SIZES = {1424: {"w": 3200, "h": 2100}}
UI_MAP = {267: 1424, 400: 1441}.get
START = (267, (60.0, 20.0))


def log(qid, text, have, need, **extra):
    return dict({"id": qid, "title": f"Quest {qid}", "objectives": [{"text": text, "have": have, "need": need, "done": False}]}, **extra)


class FormulaTest(unittest.TestCase):
    def test_gray_level_follows_the_classic_table(self):
        self.assertEqual([qv.gray_level(n) for n in (5, 10, 30, 40, 60)], [0, 4, 22, 31, 51])

    def test_mob_xp(self):
        self.assertEqual(qv.mob_xp(30, 30), 195)            # 45 + 5 * level
        self.assertEqual(qv.mob_xp(30, 32), 215)            # +5% per level above
        self.assertEqual(qv.mob_xp(30, 40), 234)            # capped at +20%
        self.assertEqual(qv.mob_xp(30, 22), 0)              # gray
        self.assertGreater(qv.mob_xp(30, 30), qv.mob_xp(30, 26))
        self.assertEqual(qv.mob_xp(30, 30, elite=True), 390)

    def test_kill_time_grows_with_level_and_elites(self):
        self.assertEqual(qv.kill_seconds(30, 30), qv.KILL_SEC)
        self.assertGreater(qv.kill_seconds(30, 33), qv.kill_seconds(30, 30))
        self.assertEqual(qv.kill_seconds(30, 1), qv.KILL_SEC_RANGE[0])
        self.assertEqual(qv.kill_seconds(30, 30, elite=True), qv.KILL_SEC * qv.ELITE_FACTOR)

    def test_legs_use_the_measured_zone_size(self):
        seconds, crossed, measured = qv.leg_seconds((267, (10, 50)), (267, (60, 50)), SIZES, UI_MAP)
        self.assertAlmostEqual(seconds, 0.5 * 3200 / qv.RUN_YPS)
        self.assertTrue(measured and not crossed)
        self.assertEqual(qv.leg_seconds((267, (1, 1)), (400, (1, 1)), SIZES, UI_MAP)[:2], (qv.OTHER_ZONE_SEC, True))
        self.assertFalse(qv.leg_seconds((400, (1, 1)), (400, (2, 2)), SIZES, UI_MAP)[2], "unmeasured zone")
        self.assertEqual(qv.leg_seconds(None, (267, (1, 1)), SIZES, UI_MAP)[0], 0)


class EstimateTest(unittest.TestCase):
    def test_kill_quest_counts_remaining_kills_and_their_xp(self):
        e = qv.estimate(Q, Q["quests"][10], log(10, "4/10 Farmer", 4, 10), 30, START, SIZES, UI_MAP)
        self.assertEqual(e["kills"], 6)
        self.assertEqual(e["kill_xp"], 6 * qv.mob_xp(30, 28))
        self.assertEqual(e["quest_xp"], 2000)
        self.assertAlmostEqual(e["xp_per_minute"], (2000 + e["kill_xp"]) / e["minutes"])
        self.assertEqual(e["notes"], [])

    def test_drop_quest_divides_by_the_drop_rate_and_gray_mobs_give_no_xp(self):
        e = qv.estimate(Q, Q["quests"][11], log(11, "2/10 Bear Tongue", 2, 10), 30, START, SIZES, UI_MAP)
        self.assertEqual(e["kills"], 16)          # 8 tongues at 50%
        self.assertEqual(e["kill_xp"], 0)         # level 21-22 bears are gray at 30

    def test_the_clients_quest_xp_wins_over_the_database(self):
        e = qv.estimate(Q, Q["quests"][10], log(10, "0/10 Farmer", 0, 10, xp=1234), 30, START, SIZES, UI_MAP)
        self.assertEqual(e["quest_xp"], 1234)

    def test_a_complete_quest_is_only_the_walk_to_the_turn_in(self):
        e = qv.estimate(Q, Q["quests"][10], {"id": 10, "complete": 1, "objectives": []}, 30, (267, (30.0, 40.0)), SIZES, UI_MAP)
        self.assertEqual(e["kills"], 0)
        self.assertGreater(e["minutes"], 1)

    def test_elites_are_flagged_and_slower(self):
        e = qv.estimate(Q, Q["quests"][13], log(13, "0/5 Elite Guard", 0, 5), 30, START, SIZES, UI_MAP)
        self.assertIn("elite", e["notes"])
        self.assertEqual(e["kill_xp"], 5 * 390)

    def test_quests_without_objective_data_or_database_entry_are_not_timed(self):
        e = qv.estimate(Q, Q["quests"][14], {"id": 14, "objectives": []}, 30, START, SIZES, UI_MAP)
        self.assertIsNone(e["minutes"])
        self.assertIn("no objective data", e["notes"])
        e = qv.estimate(Q, None, {"id": 99999, "xp": 2300}, 30, START, SIZES, UI_MAP)
        self.assertIsNone(e["minutes"])
        self.assertEqual(e["quest_xp"], 2300)

    def test_an_unmatched_objective_assumes_one_and_says_so(self):
        e = qv.estimate(Q, Q["quests"][10], {"id": 10, "objectives": [{"text": "something else"}]}, 30, START, SIZES, UI_MAP)
        self.assertEqual(e["kills"], 1)
        self.assertIn("count assumed 1", e["notes"])


class EnglishClientTest(unittest.TestCase):
    """Objective progress is read from the snapshot text, which is in the client's language."""

    def setUp(self):
        import common
        self.common, self._spanish = common, common.SPANISH_CLIENT
        self.Q = dict(Q, npcs=dict(Q["npcs"]))
        self.Q["npcs"][2] = dict(Q["npcs"][2], name_es="Granjero")

    def tearDown(self):
        self.common.SPANISH_CLIENT = self._spanish

    def test_english_text_matches_on_an_english_client(self):
        self.common.use_locale("enUS")
        e = qv.estimate(self.Q, self.Q["quests"][10], log(10, "4/10 Farmer", 4, 10), 30, START, SIZES, UI_MAP)
        self.assertEqual(e["kills"], 6)
        self.assertEqual(e["notes"], [])

    def test_spanish_text_matches_on_a_spanish_client(self):
        self.common.use_locale("esMX")
        e = qv.estimate(self.Q, self.Q["quests"][10], log(10, "4/10 Granjero", 4, 10), 30, START, SIZES, UI_MAP)
        self.assertEqual(e["kills"], 6)
        self.assertEqual(e["notes"], [])


class RankTest(unittest.TestCase):
    def test_local_quests_first_then_other_zones_then_untimed(self):
        snap = {"level": 30, "location": {"mapID": 1424, "x": 60.0, "y": 20.0}, "mapSizes": SIZES, "quests": [
            log(12, "0/5 Harpy", 0, 5), {"id": 14, "title": "No data", "objectives": []},
            log(11, "2/10 Bear Tongue", 2, 10), log(10, "4/10 Farmer", 4, 10)]}
        rows = qv.rank(Q, snap, UI_MAP)
        self.assertEqual([lq["id"] for lq, _ in rows], [10, 11, 12, 14])
        self.assertEqual(rows[2][1]["elsewhere"], 400)
        self.assertNotIn("in another zone", rows[2][1]["notes"], "the trip to another zone is not guessed")
        text = "\n".join(qv.lines(Q, rows))
        self.assertIn("-- in other zones", text)
        self.assertIn("cannot be timed: no objective data", text)


if __name__ == "__main__":
    unittest.main()
