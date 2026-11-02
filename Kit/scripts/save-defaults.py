#!/usr/bin/env python3
"""Run: make save-defaults

Copies the settings saved on this Mac into the defaults a fresh install starts with.
Anything tied to this Mac is left out, and saved settings always win over these.
"""
from pathlib import Path
import plistlib
import subprocess

DOMAIN = "io.github.grandleaf.Gaugebar"
TARGET = Path(__file__).resolve().parents[2] / "Stats/Supporting Files/DefaultSettings.plist"

SKIP_PREFIXES = ("NS", "sensor_", "LaunchAtLogin")
SKIP_KEYS = {"pause", "runAtLoginInitialized"}


def main():
    raw = subprocess.check_output(["defaults", "export", DOMAIN, "-"])
    saved = plistlib.loads(raw)
    settings = {key: value for key, value in saved.items()
                if key not in SKIP_KEYS and not key.startswith(SKIP_PREFIXES)}
    # The first-run presets would replace these settings.
    settings["setupProcess"] = True
    with TARGET.open("wb") as file:
        plistlib.dump(settings, file, sort_keys=True)
    print(f"Saved {len(settings)} settings to {TARGET.relative_to(TARGET.parents[2])}")


if __name__ == "__main__":
    main()
