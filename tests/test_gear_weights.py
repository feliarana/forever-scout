"""Tests for the bag-upgrade check in tools/analyze.py: which weights it uses and what a
class can wear."""
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import common  # noqa: E402,F401  (puts the repo root on the path for config)
import analyze  # noqa: E402
import config  # noqa: E402


class GearWeightsTest(unittest.TestCase):
    def test_config_weights_win_over_the_snapshot(self):
        snap = {"weights": {"source": "class default", "role": "ranged", "values": {"agi": 1}}}
        with mock.patch.object(config, "STAT_WEIGHTS", {"HUNTER": {"agi": 2.33}}):
            weights, addon_keys, source = analyze.gear_weights(snap, "HUNTER")
        self.assertEqual(weights, {"agi": 2.33})
        self.assertFalse(addon_keys)
        self.assertEqual(source, "config.STAT_WEIGHTS")

    def test_other_classes_use_the_weights_the_addon_saved(self):
        snap = {"weights": {"source": "class default", "role": "healer", "values": {"heal": 1}}}
        with mock.patch.object(config, "STAT_WEIGHTS", {"HUNTER": {"agi": 2.33}}):
            weights, addon_keys, source = analyze.gear_weights(snap, "PRIEST")
            none = analyze.gear_weights({}, "PRIEST")
        self.assertEqual(weights, {"heal": 1})
        self.assertTrue(addon_keys)
        self.assertEqual(source, "addon, class default: healer")
        self.assertEqual(none, (None, False, None))

    def test_weapon_dps_follows_the_source_of_the_weights(self):
        bow = {"slot": "INVTYPE_RANGED", "stats": {"dps": 10, "agi": 2}}
        sword = {"slot": "INVTYPE_WEAPON", "stats": {"dps": 10, "agi": 2}}
        # config.py: "dps" is the ranged weapon only.
        self.assertEqual(analyze.score(bow, {"dps": 14, "agi": 1}), 142)
        self.assertEqual(analyze.score(sword, {"dps": 14, "agi": 1}), 2)
        # Addon: "dps" is melee, "rdps" is ranged.
        addon = {"dps": 3, "rdps": 14, "agi": 1}
        self.assertEqual(analyze.score(bow, addon, addon_keys=True), 142)
        self.assertEqual(analyze.score(sword, addon, addon_keys=True), 32)

    def test_armor_follows_the_class_and_level(self):
        self.assertTrue(analyze.wearable("Mail", "WARRIOR", 30))
        self.assertFalse(analyze.wearable("Plate", "WARRIOR", 39))
        self.assertTrue(analyze.wearable("Placas", "PALADIN", 40))
        self.assertFalse(analyze.wearable("Malla", "HUNTER", 30))
        self.assertFalse(analyze.wearable("Cuero", "PRIEST", 60))
        self.assertFalse(analyze.wearable("Shields", "DRUID", 60))
        self.assertTrue(analyze.wearable("Escudos", "SHAMAN", 10))
        self.assertTrue(analyze.wearable("Miscellaneous", "MAGE", 10))


if __name__ == "__main__":
    unittest.main()
