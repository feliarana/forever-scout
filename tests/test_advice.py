"""Unit tests for tools/advice.py.

Run with: .venv/bin/python -m unittest discover -s tests -p "test_*.py"
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import advice  # noqa: E402


def tree(spent, available, cap, nodes, tree_id=None, currency=1):
    return {"treeID": tree_id, "currencies": [{"id": currency, "spent": spent, "available": available, "max": cap}],
            "nodes": nodes}


def node(name, rank, cap, can_buy=False, desc=None, y=0):
    return {"name": name, "rank": rank, "max": cap, "canBuy": can_buy or None, "desc": desc, "x": 0, "y": y}


class TalentTest(unittest.TestCase):
    def test_unspent_points_list_what_can_take_them_with_descriptions(self):
        snap = {"talents": {"trees": [tree(20, 1, 21, [
            node("Ferocity", 0, 5, True, "Increases the critical strike chance of your pet by 3%.", y=2),
            node("Endurance Training", 3, 5, True, y=1),
            node("Bestial Wrath", 0, 1, False),
            node("Unleashed Fury", 5, 5, True),  # maxed: nothing left to buy
        ])]}, "traitSystems": []}
        lines = advice.talent_lines(snap)
        self.assertEqual(lines[0], "Class talents: 20 spent of 21 — !! 1 unspent")
        self.assertIn("    - Endurance Training 3/5", lines)
        self.assertIn("    - Ferocity 0/5: Increases the critical strike chance of your pet by 3%.", lines)
        self.assertLess(lines.index("    - Endurance Training 3/5"), lines.index(
            "    - Ferocity 0/5: Increases the critical strike chance of your pet by 3%."), "top row first")
        self.assertFalse(any("Bestial Wrath" in line or "Unleashed Fury" in line for line in lines))

    def test_no_points_is_one_quiet_line(self):
        snap = {"talents": {"trees": [tree(21, 0, 21, [node("Ferocity", 5, 5)])]}, "traitSystems": []}
        self.assertEqual(advice.talent_lines(snap)[0], "Class talents: 21 spent of 21, no points to spend")

    def test_perk_systems_are_reported_by_name(self):
        # As the Forever client reports it: an unnamed system 45 whose three trees share one
        # currency, plus an empty tree.
        snap = {"talents": {"trees": []}, "traitSystems": [{"systemID": 45, "name": "", "trees": [
            {"treeID": 1118, "currencies": {}, "nodes": []},
            tree(2, 3, 5, [node("Overtime", 0, 5, True, "More skill-ups.")], tree_id=1187, currency=4225),
            tree(2, 3, 5, [node("Well Rested", 0, 5, True, "Rested lasts longer.")], tree_id=1188, currency=4225),
            tree(2, 3, 5, [node("Unknown", 0, 1)], tree_id=1189, currency=4225)]}]}
        lines = advice.talent_lines(snap)
        self.assertEqual(lines[0], "Legacy points: 2 spent of 5 earned — !! 3 unspent")
        self.assertIn("    - Overtime 0/5 [Professions]: More skill-ups.", lines)
        self.assertIn("    - Well Rested 0/5 [Adventure]: Rested lasts longer.", lines)
        self.assertFalse(any("Unknown" in line for line in lines))

    def test_missing_perk_data_says_why(self):
        self.assertIn("addon is older", advice.talent_lines({"talents": {"trees": []}})[-1])
        self.assertIn("reported none", advice.talent_lines({"talents": {"trees": []}, "traitSystems": []})[-1])
        empty = {"talents": {"trees": []}, "traitSystems": [{"systemID": 45, "trees": [{"treeID": 1118, "nodes": []}]}]}
        self.assertIn("reported none", advice.talent_lines(empty)[-1], "a system without readable nodes is no data")

    def test_long_descriptions_are_cut(self):
        snap = {"talents": {"trees": [tree(0, 1, 5, [node("Wordy", 0, 1, True, "x" * 400)])]}, "traitSystems": []}
        line = advice.talent_lines(snap)[2]
        self.assertLessEqual(len(line), len("    - Wordy 0/1: ") + advice.MAX_DESC)


class ProfessionTest(unittest.TestCase):
    def test_skinning_reach_follows_the_classic_rule(self):
        self.assertEqual(advice.skinning_max_level(1), 10)
        self.assertEqual(advice.skinning_max_level(50), 15)
        self.assertEqual(advice.skinning_max_level(100), 20)
        self.assertEqual(advice.skinning_max_level(182), 36)

    def test_cap_warnings(self):
        snap = {"skills": [{"name": "First Aid", "rank": 141, "max": 150},
                           {"name": "Cooking", "rank": 75, "max": 75},
                           {"name": "Leatherworking", "rank": 72, "max": 150}]}
        lines = "\n".join(advice.profession_lines(snap))
        self.assertIn("First Aid 141/150 — 9 from the cap", lines)
        self.assertIn("Cooking 75/75 — !! at the cap", lines)
        self.assertIn("Leatherworking 72/150\n", lines + "\n")

    def test_skill_up_recipes_are_listed_orange_first(self):
        snap = {"skills": [{"name": "Peletería", "rank": 72, "max": 150}],
                "recipes": {"Peletería": {"at": "2026-11-15 20:19", "list": [
                    {"name": "Gray thing", "color": 3}, {"name": "Yellow cloak", "color": 1},
                    {"name": "Orange bracers", "color": 0}, {"name": "Green boots", "color": 2}]}}}
        lines = advice.profession_lines(snap)
        self.assertEqual(lines[1], "    skill-up recipes as of 2026-11-15 20:19: orange: Orange bracers; yellow: Yellow cloak")

    def test_only_gray_and_green_recipes_means_new_recipes_are_needed(self):
        snap = {"skills": [{"name": "Cooking", "rank": 60, "max": 75}],
                "recipes": {"Cooking": {"at": "x", "list": [{"name": "Old stew", "color": "trivial"}]}}}
        self.assertIn("new recipes needed", advice.profession_lines(snap)[1])

    def test_gathering_skills_ignore_recipe_lists(self):
        snap = {"skills": [{"name": "Desuello", "rank": 120, "max": 150}, {"name": "Pesca", "rank": 5, "max": 75}],
                "recipes": {"Pesca": {"at": "x", "list": [{"name": "Wool Bandage", "color": 1}]}}}
        lines = advice.profession_lines(snap, level=30)
        self.assertEqual(len(lines), 2)
        self.assertIn("skins mobs up to level 24 (Classic rule) !! below your level 30", lines[0])

    def test_a_crafting_skill_without_captured_recipes_asks_for_them(self):
        lines = advice.profession_lines({"skills": [{"name": "Tailoring", "rank": 40, "max": 75}]})
        self.assertIn("open the profession window once", lines[1])


if __name__ == "__main__":
    unittest.main()
