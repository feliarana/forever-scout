"""Unit tests for the helpers that use what the game client reports about a logged quest.

Run with: .venv/bin/python -m unittest discover -s tests -p "test_*.py"
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import common  # noqa: E402

Q = {"uimap": {1420: (85, "Tirisfal Glades"), 1424: (267, "Hillsbrad Foothills")},
     "zones": {85: "Tirisfal Glades", 267: "Hillsbrad Foothills"}, "zones_es": {85: "Claros de Tirisfal"}}
DB_QUEST = {"id": 549, "level": 22, "xp": 1750, "xp_classic": None}


class QuestXpTest(unittest.TestCase):
    def test_the_clients_number_wins(self):
        self.assertEqual(common.quest_xp_text(DB_QUEST, {"id": 549, "xp": 700}, 30), "700 XP")

    def test_a_quest_missing_from_the_database_uses_the_client(self):
        self.assertEqual(common.quest_xp_text(None, {"id": 92421, "xp": 1850}, 30), "1850 XP")

    def test_without_client_data_the_database_estimate_is_used(self):
        self.assertEqual(common.quest_xp_text(DB_QUEST, {"id": 549}, 30), "700 XP (40%)")

    def test_no_source_at_all_is_a_question_mark(self):
        self.assertEqual(common.quest_xp_text(None, {"id": 92421}, 30), "XP ?")
        self.assertEqual(common.quest_xp_text(None, None, 30), "XP ?")


class ClientPlacesTest(unittest.TestCase):
    def test_waypoint_of_a_complete_quest_is_its_turn_in(self):
        lq = {"id": 1, "complete": 1, "waypoint": {"mapID": 1420, "x": 65.2, "y": 60.2}}
        self.assertEqual(common.client_places(Q, lq),
                         ["turn-in (game waypoint): Tirisfal Glades / Claros de Tirisfal 65.2,60.2"])

    def test_waypoint_of_an_unfinished_quest_is_the_next_step(self):
        lq = {"id": 1, "waypoint": {"mapID": 1424, "x": 30.0, "y": 40.0}}
        self.assertEqual(common.client_places(Q, lq)[0], "next step (game waypoint): Hillsbrad Foothills 30.0,40.0")

    def test_the_recorded_giver_is_reported_as_the_players_own_record(self):
        lq = {"id": 1, "giver": {"name": "Morbin Lightbane", "mapID": 1420, "x": 58.1, "y": 89.5, "at": "2026-11-16 10:00"}}
        self.assertEqual(common.client_places(Q, lq), [
            "accepted from Morbin Lightbane: Tirisfal Glades / Claros de Tirisfal 58.1,89.5 "
            "(your own record, 2026-11-16 10:00)"])

    def test_an_accept_without_an_npc_and_an_unknown_map(self):
        lq = {"id": 1, "giver": {"mapID": 9999, "x": 1.0, "y": 2.0, "at": "x"}}
        self.assertIn("accepted from no NPC (item or object): map 9999 1.0,2.0", common.client_places(Q, lq)[0])

    def test_nothing_known_gives_no_lines(self):
        self.assertEqual(common.client_places(Q, {"id": 1}), [])
        self.assertEqual(common.client_places(Q, None), [])


class MergeHistoryTest(unittest.TestCase):
    """History of the addon's older names is merged into the current one."""

    def test_lists_concatenate_maps_merge_and_xp_adds_up(self):
        old = {"deaths": [{"at": "a"}], "flights": {"Orgrimmar": 1}, "xpTotal": 100}
        new = {"deaths": [{"at": "b"}], "flights": {"Tarren Mill": 1}, "xpTotal": 50}
        merged = common._merge_history(old, new)
        self.assertEqual([d["at"] for d in merged["deaths"]], ["a", "b"])
        self.assertEqual(set(merged["flights"]), {"Orgrimmar", "Tarren Mill"})
        self.assertEqual(merged["xpTotal"], 150)

    def test_an_empty_table_in_the_new_addon_does_not_wipe_older_entries(self):
        # A freshly renamed addon saves its empty lists as empty Lua tables, read as {}.
        old = {"deaths": [{"at": "a"}], "levelUps": [{"level": 30}], "flights": {"Orgrimmar": 1}}
        new = {"deaths": {}, "levelUps": {}, "flights": {}, "runs": {}}
        merged = common._merge_history(old, new)
        self.assertEqual(len(merged["deaths"]), 1)
        self.assertEqual(len(merged["levelUps"]), 1)
        self.assertEqual(merged["flights"], {"Orgrimmar": 1})
        self.assertEqual(merged["runs"], {})

    def test_one_profession_opened_today_keeps_the_others_from_the_history(self):
        hist = {"recipes": {"Cooking": {"at": "2026-11-15 20:18", "list": [{"name": "Roast"}]},
                            "Leatherworking": {"at": "2026-11-15 20:19", "list": []}},
                "flights": {"Orgrimmar": 1}}
        db = {"recipes": {"Leatherworking": {"at": "2026-11-19 09:26", "list": [{"name": "Bracers"}]}}}
        common.fill_from_history(db, hist)
        self.assertEqual(set(db["recipes"]), {"Cooking", "Leatherworking"})
        self.assertEqual(db["recipes"]["Leatherworking"]["at"], "2026-11-19 09:26")
        self.assertEqual(db["flights"], {"Orgrimmar": 1})


class ClientLanguageTest(unittest.TestCase):
    """Names follow the game client: 'English / Spanish' on a Spanish client, English alone
    on any other, and objective texts are matched against what that client shows."""

    def setUp(self):
        self._spanish = common.SPANISH_CLIENT

    def tearDown(self):
        common.SPANISH_CLIENT = self._spanish

    def test_spanish_clients_see_both_names(self):
        for locale in ("esMX", "esES"):
            common.use_locale(locale)
            self.assertEqual(common.both("Gray Bear", "Oso gris"), "Gray Bear / Oso gris")
            self.assertEqual(common.client_name(common.both("Gray Bear", "Oso gris")), "Oso gris")

    def test_other_clients_see_the_english_name_only(self):
        for locale in ("enUS", "enGB", "deDE"):
            common.use_locale(locale)
            self.assertEqual(common.both("Gray Bear", "Oso gris"), "Gray Bear")
            self.assertEqual(common.client_name(common.both("Gray Bear", "Oso gris")), "Gray Bear")

    def test_a_missing_or_equal_translation_never_breaks_a_name(self):
        common.use_locale("esMX")
        self.assertEqual(common.both("Kamari", "Kamari"), "Kamari")
        self.assertEqual(common.both("Kamari", None), "Kamari")
        self.assertEqual(common.both(None, "Oso gris"), "Oso gris")
        self.assertEqual(common.both(None, None), "?")

    def test_an_unknown_locale_keeps_the_current_choice(self):
        common.use_locale("enUS")
        common.use_locale(None)
        self.assertFalse(common.SPANISH_CLIENT)


if __name__ == "__main__":
    unittest.main()
