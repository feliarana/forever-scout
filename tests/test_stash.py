"""Unit tests for tools/stash.py.

Run with: .venv/bin/python -m unittest discover -s tests -p "test_*.py"
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import stash  # noqa: E402

NAMES = {10: "Chapter 1", 11: "Page 1", 12: "Page 2", 20: "Linen Cloth", 30: "Bear Tongue"}
QUESTS = {
    1: {"objectives": {3: [[10, None, 0]]}},          # needs Chapter 1, made of pages 1 and 2
    2: {"objectives": {3: [[20, None, 0], 30]}},      # needs cloth and tongues
    3: {"objectives": {1: [[99]]}},                   # kill quest, no items
}
PARTS = {10: [11, 12]}


def lines(log, rows):
    return stash.quest_lines(log, QUESTS, rows, "Hunter", PARTS, lambda i: NAMES.get(i, str(i)))


class QuestLinesTest(unittest.TestCase):
    def test_items_in_bank_mail_or_an_alt_are_reported(self):
        rows = {20: {"where": {"Hunter:bags": 4, "Hunter:bank": 11, "Banker:bags": 68}},
                30: {"where": {"Hunter:bags": 2}}}
        out = lines([{"id": 2, "title": "Supplies"}], rows)
        self.assertEqual(out, ["[2] Supplies", "    Linen Cloth: Banker:bags x68, Hunter:bank x11"])

    def test_items_only_in_the_characters_bags_are_not_news(self):
        rows = {20: {"where": {"Hunter:bags": 4}}, 30: {"where": {"Hunter:bags": 2}}}
        self.assertEqual(lines([{"id": 2, "title": "Supplies"}], rows), [])

    def test_parts_of_an_objective_are_reported_with_what_is_missing(self):
        rows = {11: {"where": {"Hunter:mail": 3}}}
        out = lines([{"id": 1, "title": "The Lost Pages"}], rows)
        self.assertEqual(out[0], "[1] The Lost Pages")
        self.assertEqual(out[1], "    Chapter 1 is made from parts you hold: Page 1 (Hunter:mail x3) — still missing: Page 2")

    def test_all_parts_owned_says_to_assemble(self):
        rows = {11: {"where": {"Hunter:mail": 1}}, 12: {"where": {"Hunter:bags": 1}}}
        self.assertIn("all parts owned: assemble it", lines([{"id": 1, "title": "The Lost Pages"}], rows)[1])

    def test_complete_quests_kill_quests_and_unknown_quests_are_skipped(self):
        rows = {20: {"where": {"Hunter:bank": 11}}}
        log = [{"id": 2, "title": "Supplies", "complete": 1}, {"id": 3, "title": "Kill"}, {"id": 404, "title": "?"}]
        self.assertEqual(lines(log, rows), [])


class CoverageTest(unittest.TestCase):
    NOW = 1_000_000

    def test_no_syndicator_explains_what_to_install(self):
        self.assertIn("Syndicator", stash.coverage_lines({}, self.NOW, 5)[0])

    def test_counts_and_first_expiry(self):
        chars = {"Hunter": {"bank": 47, "mail": [self.NOW + 30 * 86400, self.NOW + 40 * 86400, None]}}
        out = stash.coverage_lines(chars, self.NOW, 5)
        self.assertEqual(out[0], "Hunter: bank 47 items, mail 3 items (first expires in 30 days)")
        self.assertIn("last time each was opened", out[-1])

    def test_mail_about_to_expire_is_flagged(self):
        chars = {"Banker": {"bank": 0, "mail": [self.NOW + 2 * 86400, self.NOW + 4 * 86400, self.NOW + 20 * 86400]}}
        self.assertEqual(stash.coverage_lines(chars, self.NOW, 5)[0],
                         "Banker: bank 0 items, mail 3 items — !! 2 mail item(s) expire within 2 day(s): collect them")

    def test_expired_mail_is_flagged(self):
        chars = {"Banker": {"bank": 0, "mail": [self.NOW - 10]}}
        self.assertIn("already expired", stash.coverage_lines(chars, self.NOW, 5)[0])


if __name__ == "__main__":
    unittest.main()
