#!/usr/bin/env python3
"""Derive each bundled recipe's raw C-slot `presetSettings` from its `settings` text.

Recipe cards show `settings`; camera writes use `presetSettings`. This script treats
the text as the source of truth and reports every raw field that disagrees with it.

    scripts/sync-catalog-presets.py            # list disagreements, exit 1 if any
    scripts/sync-catalog-presets.py --write    # rewrite presetSettings to match the text

Raw encodings follow CSlotPresetEncoder and docs/setting-to-ptp-map.md.
"""

import argparse
import json
import re
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "macos/Resources/recipes-data.json"

GRAIN = {"Off": 1, "Weak, Small": 2, "Strong, Small": 3, "Weak, Large": 4, "Strong, Large": 5}
EFFECT = {"Off": 1, "Weak": 2, "Strong": 3}
DYNAMIC_RANGE = {"Auto": 0xFFFF, "DR100": 100, "DR200": 200, "DR400": 400}
HIGH_ISO_NR = {-4: 0x8000, -3: 0x7000, -2: 0x4000, -1: 0x3000, 0: 0x2000, 1: 0x1000, 2: 0x0000, 3: 0x6000, 4: 0x5000}
WHITE_BALANCE = {
    "Auto": 2,
    "Daylight": 4,
    "Incandescent": 6,
    "Fluorescent 1": 0x8001,
    "Fluorescent 2": 0x8002,
    "Fluorescent 3": 0x8003,
    "Shade": 0x8006,
    "Ambience Priority": 0x8021,
}
COLOR_TEMPERATURE = 0x8007
TONES = {"highlight": "highlightTone", "shadow": "shadowTone", "color": "color", "sharpness": "sharpness", "clarity": "clarity"}
WB_PATTERN = re.compile(r"^(?P<mode>[^,]+),\s*(?P<red>[+-]?\d+) Red & (?P<blue>[+-]?\d+) Blue$")
KELVIN_PATTERN = re.compile(r"^(\d{4,5})K$")


class TextError(ValueError):
    pass


def lookup(table, text, field):
    if text not in table:
        raise TextError(f"{field}: no raw value for {text!r}")
    return table[text]


def tenths(text, field):
    try:
        value = float(text)
    except ValueError as error:
        raise TextError(f"{field}: {text!r} is not a number") from error
    if round(value * 10) != value * 10 or round(value * 10) % 5:
        raise TextError(f"{field}: {text!r} is not a half step")
    return round(value * 10)


def required_text(text, key):
    if key not in text:
        raise TextError(f"{key}: missing from settings")
    return text[key]


def film_simulation(recipe):
    if recipe["filmSimEnum"] is None:
        raise TextError("filmSimulation: filmSimEnum is missing")
    return recipe["filmSimEnum"]


def white_balance(text):
    wb = WB_PATTERN.match(required_text(text, "whiteBalance"))
    if not wb:
        raise TextError(f"whiteBalance: cannot parse {text['whiteBalance']!r}")
    kelvin = KELVIN_PATTERN.match(wb["mode"])
    fields = {"wbShiftRed": int(wb["red"]), "wbShiftBlue": int(wb["blue"])}
    if kelvin:
        fields.update(whiteBalance=COLOR_TEMPERATURE, colorTemp=int(kelvin[1]))
    else:
        fields["whiteBalance"] = lookup(WHITE_BALANCE, wb["mode"], "whiteBalance")
    return fields


def expected_preset(recipe):
    """Returns ({key: raw value}, [errors]) so one bad field does not hide the others."""
    text = recipe["settings"]
    derivations = {
        "filmSimulation": lambda: film_simulation(recipe),
        "dynamicRange": lambda: lookup(DYNAMIC_RANGE, required_text(text, "dynamicRange"), "dynamicRange"),
        "grainEffect": lambda: lookup(GRAIN, required_text(text, "grainEffect"), "grainEffect"),
        "colorChromeEffect": lambda: lookup(EFFECT, required_text(text, "colorChromeEffect"), "colorChromeEffect"),
        "colorChromeFxBlue": lambda: lookup(EFFECT, required_text(text, "colorChromeFxBlue"), "colorChromeFxBlue"),
        "highIsoNr": lambda: lookup(HIGH_ISO_NR, int(required_text(text, "highIsoNr")), "highIsoNr"),
    }
    for text_key, raw_key in TONES.items():
        if text_key in text:
            derivations[raw_key] = lambda text_key=text_key: tenths(text[text_key], text_key)

    preset, errors = {}, []
    for key, derive in derivations.items():
        try:
            preset[key] = derive()
        except TextError as error:
            errors.append((key, error))
    try:
        preset.update(white_balance(text))
    except TextError as error:
        errors.append(("whiteBalance", error))
    return preset, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write", action="store_true", help="rewrite presetSettings to match the text")
    parser.add_argument("--fields", help="comma-separated presetSettings keys to check (default: all)")
    args = parser.parse_args()
    fields = set(args.fields.split(",")) if args.fields else None

    catalog = json.loads(CATALOG.read_text())
    problems = unreadable = 0
    for recipe in catalog["recipes"]:
        expected, errors = expected_preset(recipe)
        for key, error in errors:
            if not fields or key in fields:
                print(f"{recipe['id']}: {error}")
                unreadable += 1
        preset = recipe["presetSettings"]
        for key, value in expected.items():
            if fields and key not in fields:
                continue
            current = preset.get(key)
            if current is None or current != value:
                print(f"{recipe['id']}: {key} {current} -> {value}")
                problems += 1
                preset[key] = value

    if args.write:
        CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False))
        print(f"Rewrote {problems} field(s) in {CATALOG.name}")
        return 1 if unreadable else 0
    return 1 if problems or unreadable else 0


if __name__ == "__main__":
    sys.exit(main())
