#!/usr/bin/env python3
"""
Deploy script for ChattyLittleNpc.
Copies the addon folder into the selected WoW version's Interface/AddOns directory.

Usage:
    python deploy.py
"""

import os
import sys
import shutil

WOW_ROOT = r"D:\Games\World of Warcraft"

# Human-readable labels for known WoW version folders
VERSION_LABELS = {
    "_retail_":      "Retail (The War Within / Midnight)",
    "_classic_":     "Classic (Cataclysm / Mists)",
    "_classic_era_": "Classic Era (Season of Discovery)",
    "_anniversary_": "Classic Anniversary",
    "_ptr_":         "PTR (Public Test Realm)",
    "_xptr_":        "xPTR",
    "_beta_":        "Beta",
}

ADDONS_RELATIVE = os.path.join("Interface", "AddOns")


def find_addon_source():
    """Return the absolute path to the ChattyLittleNpc addon folder."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidate = os.path.join(script_dir, "ChattyLittleNpc")
    if os.path.isdir(candidate):
        toc = os.path.join(candidate, "ChattyLittleNpc.toc")
        if os.path.isfile(toc):
            return candidate
    print("ERROR: Could not find ChattyLittleNpc/ folder next to this script.")
    sys.exit(1)


def discover_versions(wow_root):
    """
    Scan wow_root for version folders that contain Interface/AddOns.
    Returns a list of (folder_name, addons_path, label) sorted by folder name.
    """
    versions = []
    if not os.path.isdir(wow_root):
        print(f"ERROR: WoW root not found at: {wow_root}")
        sys.exit(1)

    for entry in sorted(os.listdir(wow_root)):
        full_path = os.path.join(wow_root, entry)
        if not os.path.isdir(full_path):
            continue
        addons_path = os.path.join(full_path, ADDONS_RELATIVE)
        if os.path.isdir(addons_path):
            label = VERSION_LABELS.get(entry, entry)
            versions.append((entry, addons_path, label))

    return versions


def prompt_version(versions):
    """Print a numbered menu and return the chosen (folder_name, addons_path, label)."""
    print()
    print("Available WoW versions:")
    print()
    for i, (folder, addons_path, label) in enumerate(versions, start=1):
        print(f"  [{i}] {label}")
        print(f"       {addons_path}")
    print()

    while True:
        raw = input(f"Select version [1-{len(versions)}]: ").strip()
        if raw.isdigit():
            choice = int(raw)
            if 1 <= choice <= len(versions):
                return versions[choice - 1]
        print(f"  Please enter a number between 1 and {len(versions)}.")


def deploy(source_dir, addons_dir, addon_name):
    """Copy source_dir into addons_dir/<addon_name>, replacing any existing copy."""
    dest = os.path.join(addons_dir, addon_name)

    if os.path.exists(dest):
        print(f"\nRemoving existing: {dest}")
        shutil.rmtree(dest)

    print(f"Copying: {source_dir}")
    print(f"     to: {dest}")
    shutil.copytree(source_dir, dest)
    print("\nDone.")


def main():
    source_dir = find_addon_source()
    addon_name = os.path.basename(source_dir)

    print(f"Addon source : {source_dir}")
    print(f"WoW root     : {WOW_ROOT}")

    versions = discover_versions(WOW_ROOT)
    if not versions:
        print("ERROR: No WoW version folders with Interface/AddOns found.")
        sys.exit(1)

    folder, addons_dir, label = prompt_version(versions)

    print(f"\nDeploying to: {label}  ({addons_dir})")
    confirm = input("Confirm? [y/N]: ").strip().lower()
    if confirm != "y":
        print("Aborted.")
        sys.exit(0)

    deploy(source_dir, addons_dir, addon_name)


if __name__ == "__main__":
    main()
