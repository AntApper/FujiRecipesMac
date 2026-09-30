import contextlib
import copy
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "sync-catalog-presets.py"
SPEC = importlib.util.spec_from_file_location("sync_catalog_presets", SCRIPT)
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


def recipe_fixture():
    return {
        "id": "fixture",
        "filmSimEnum": 11,
        "settings": {
            "filmSimulation": "Classic Chrome",
            "dynamicRange": "DR100",
            "grainEffect": "Off",
            "colorChromeEffect": "Off",
            "colorChromeFxBlue": "Off",
            "highIsoNr": "-4",
            "whiteBalance": "Daylight, +1 Red & -2 Blue",
            "highlight": "-1",
            "shadow": "+0.5",
            "color": "+2",
            "sharpness": "-1",
            "clarity": "0",
        },
        "presetSettings": {
            "filmSimulation": 11,
            "dynamicRange": 100,
            "grainEffect": 1,
            "colorChromeEffect": 1,
            "colorChromeFxBlue": 1,
            "highIsoNr": 32768,
            "whiteBalance": 4,
            "wbShiftRed": 1,
            "wbShiftBlue": -2,
            "highlightTone": -10,
            "shadowTone": 5,
            "color": 20,
            "sharpness": -10,
            "clarity": 0,
            "unknownFutureField": 4242,
        },
    }


class SyncCatalogPresetsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="fujirecipes-catalog-fixture-")
        self.addCleanup(directory.cleanup)
        self.catalog = Path(directory.name) / "catalog.json"

    def run_sync(self, recipe, *args):
        self.catalog.write_text(json.dumps({"recipes": [recipe]}, indent=2, ensure_ascii=False))
        original = self.catalog.read_bytes()
        output = io.StringIO()
        with patch.object(SYNC, "CATALOG", self.catalog), contextlib.redirect_stdout(output):
            result = SYNC.main(list(args))
        saved = json.loads(self.catalog.read_text())["recipes"][0]
        return result, saved, output.getvalue(), original

    def test_removed_optional_sources_remove_only_their_known_raw_keys(self):
        recipe = recipe_fixture()
        for key in ("highlight", "shadow", "color", "sharpness", "clarity"):
            del recipe["settings"][key]
        expected = copy.deepcopy(recipe["presetSettings"])
        for key in ("highlightTone", "shadowTone", "color", "sharpness", "clarity"):
            del expected[key]

        result, saved, output, _ = self.run_sync(recipe, "--write")

        self.assertEqual(result, 0)
        self.assertEqual(saved["presetSettings"], expected)
        self.assertIn("clarity 0 -> removed", output)
        self.assertIn("Rewrote 5 field(s)", output)
        removed_keys = [line.split(": ")[1].split()[0] for line in output.splitlines() if " -> removed" in line]
        self.assertEqual(removed_keys, sorted(removed_keys))

    def test_check_reports_absent_optional_source_without_writing(self):
        recipe = recipe_fixture()
        del recipe["settings"]["clarity"]

        result, saved, output, original = self.run_sync(recipe)

        self.assertEqual(result, 1)
        self.assertIn("clarity 0 -> removed", output)
        self.assertEqual(self.catalog.read_bytes(), original)
        self.assertEqual(saved, recipe)

    def test_fields_restrict_both_removals_and_updates(self):
        recipe = recipe_fixture()
        del recipe["settings"]["clarity"]
        del recipe["settings"]["shadow"]
        recipe["presetSettings"]["highlightTone"] = 20
        recipe["presetSettings"]["color"] = 0
        expected = copy.deepcopy(recipe["presetSettings"])
        del expected["clarity"]
        expected["color"] = 20

        result, saved, output, _ = self.run_sync(recipe, "--write", "--fields", "clarity,color")

        self.assertEqual(result, 0)
        self.assertEqual(saved["presetSettings"], expected)
        self.assertNotIn("shadowTone", output)
        self.assertNotIn("highlightTone", output)

    def test_unknown_selected_field_is_neither_updated_nor_removed(self):
        recipe = recipe_fixture()
        del recipe["settings"]["clarity"]
        recipe["presetSettings"]["colorTemp"] = 6500

        result, saved, _, _ = self.run_sync(recipe, "--write", "--fields", "unknownFutureField")

        self.assertEqual(result, 0)
        self.assertEqual(saved, recipe)

    def test_parse_errors_keep_existing_raw_values(self):
        recipe = recipe_fixture()
        recipe["settings"]["clarity"] = "unrecognized tone"
        recipe["settings"]["highIsoNr"] = "unrecognized NR"
        recipe["settings"]["whiteBalance"] = "unrecognized white balance"
        recipe["presetSettings"]["colorTemp"] = 6500

        result, saved, output, _ = self.run_sync(recipe, "--write")

        self.assertEqual(result, 1)
        self.assertEqual(saved, recipe)
        self.assertIn("clarity:", output)
        self.assertIn("highIsoNr:", output)
        self.assertIn("whiteBalance:", output)
        self.assertNotIn(" -> removed", output)

    def test_parse_error_does_not_block_an_independent_optional_removal(self):
        recipe = recipe_fixture()
        recipe["settings"]["clarity"] = "unrecognized tone"
        del recipe["settings"]["shadow"]
        expected = copy.deepcopy(recipe["presetSettings"])
        del expected["shadowTone"]

        result, saved, _, _ = self.run_sync(recipe, "--write")

        self.assertEqual(result, 1)
        self.assertEqual(saved["presetSettings"], expected)

    def test_successful_non_kelvin_white_balance_removes_stale_temperature(self):
        recipe = recipe_fixture()
        recipe["presetSettings"]["colorTemp"] = 6500
        expected = copy.deepcopy(recipe["presetSettings"])
        del expected["colorTemp"]

        result, saved, output, _ = self.run_sync(recipe, "--write")

        self.assertEqual(result, 0)
        self.assertEqual(saved["presetSettings"], expected)
        self.assertIn("colorTemp 6500 -> removed", output)

    def test_kelvin_temperature_update_respects_selection(self):
        recipe = recipe_fixture()
        recipe["settings"]["whiteBalance"] = "5600K, +3 Red & -4 Blue"
        recipe["presetSettings"]["colorTemp"] = 6500
        expected = copy.deepcopy(recipe["presetSettings"])
        expected["colorTemp"] = 5600

        result, saved, _, _ = self.run_sync(recipe, "--write", "--fields", "colorTemp")

        self.assertEqual(result, 0)
        self.assertEqual(saved["presetSettings"], expected)

    def test_missing_required_source_retains_the_existing_raw_field(self):
        recipe = recipe_fixture()
        del recipe["settings"]["dynamicRange"]

        result, saved, output, _ = self.run_sync(recipe, "--write")

        self.assertEqual(result, 1)
        self.assertEqual(saved, recipe)
        self.assertIn("dynamicRange: missing from settings", output)

    def test_unselected_parse_errors_do_not_fail_a_selected_update(self):
        recipe = recipe_fixture()
        recipe["settings"]["whiteBalance"] = "unrecognized mode"
        recipe["presetSettings"]["colorTemp"] = 6500
        recipe["presetSettings"]["color"] = 0
        expected = copy.deepcopy(recipe["presetSettings"])
        expected["color"] = 20

        result, saved, output, _ = self.run_sync(recipe, "--write", "--fields", "color")

        self.assertEqual(result, 0)
        self.assertEqual(saved["presetSettings"], expected)
        self.assertNotIn("whiteBalance:", output)


if __name__ == "__main__":
    unittest.main()
