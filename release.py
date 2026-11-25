#!/usr/bin/env python3
"""
Release script for ChattyLittleNpc projects.
Reads version from .toc file, creates git tag, and creates GitHub release.

Usage:
    python release.py                          # Dry run - shows what would happen
    python release.py --create                 # Create a release tag (default: release)
    python release.py --create --type beta     # Create a beta tag (e.g. v1.0.0-beta)
    python release.py --create --type alpha    # Create an alpha tag (e.g. v1.0.0-alpha)
"""

import os
import re
import subprocess
import sys
import argparse


# The main addon's .toc, and the load-on-demand modules shipped beside it.
# All of them must carry the same ## Version.
MAIN_TOC = os.path.join('ChattyLittleNpc', 'ChattyLittleNpc.toc')
MODULE_TOCS = [
    os.path.join('ChattyLittleNpc_Collector', 'ChattyLittleNpc_Collector.toc'),
    os.path.join('ChattyLittleNpc_Tools', 'ChattyLittleNpc_Tools.toc'),
]


def find_toc_file():
    """Return the main addon's .toc path, or None if it is missing."""
    return MAIN_TOC if os.path.isfile(MAIN_TOC) else None


def get_version_from_toc(toc_path):
    """Extract version from .toc file."""
    with open(toc_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    match = re.search(r'^## Version:\s*(.+)$', content, re.MULTILINE)
    if match:
        return match.group(1).strip()
    return None


def get_addon_name_from_toc(toc_path):
    """Extract addon name from .toc filename."""
    return os.path.splitext(os.path.basename(toc_path))[0]


def run_command(cmd, check=True, capture=False):
    """Run a shell command."""
    print(f"  Running: {' '.join(cmd)}")
    if capture:
        result = subprocess.run(cmd, check=check, capture_output=True, text=True)
        return result.stdout.strip()
    else:
        subprocess.run(cmd, check=check)
        return None


def check_gh_cli():
    """Check if GitHub CLI is installed and authenticated."""
    try:
        subprocess.run(['gh', '--version'], capture_output=True, check=True)
        subprocess.run(['gh', 'auth', 'status'], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def tag_exists(tag_name):
    """Check if a tag already exists."""
    result = subprocess.run(['git', 'tag', '-l', tag_name], capture_output=True, text=True)
    return tag_name in result.stdout


def main():
    parser = argparse.ArgumentParser(description='Create release from .toc version')
    parser.add_argument('--create', action='store_true', help='Actually create tag and release (default is dry run)')
    parser.add_argument('--force', action='store_true', help='Delete existing tag if it exists')
    parser.add_argument('--tag-prefix', default='v', help='Prefix for tag name (default: v)')
    parser.add_argument('--type', dest='release_type', choices=['release', 'beta', 'alpha'], default='release',
                        help='Release type: release (default), beta, or alpha. Appends -beta/-alpha suffix to tag.')
    args = parser.parse_args()

    # Find .toc file
    toc_path = find_toc_file()
    if not toc_path:
        print(f"Error: {MAIN_TOC} not found (run release.py from the repo root)")
        sys.exit(1)
    
    print(f"Found .toc file: {toc_path}")

    # Get version
    version = get_version_from_toc(toc_path)
    if not version:
        print("Error: Could not find ## Version in .toc file")
        sys.exit(1)
    
    mismatched = []
    for module_toc in MODULE_TOCS:
        module_version = get_version_from_toc(module_toc) if os.path.isfile(module_toc) else None
        if module_version != version:
            mismatched.append(f"{module_toc}: {module_version or 'missing'}")
    if mismatched:
        print(f"Error: module versions don't match {toc_path} ({version}):")
        for line in mismatched:
            print(f"  {line}")
        sys.exit(1)

    addon_name = get_addon_name_from_toc(toc_path)
    tag_suffix = f"-{args.release_type}" if args.release_type != 'release' else ''
    tag_name = f"{args.tag_prefix}{version}{tag_suffix}"
    
    print(f"Addon: {addon_name}")
    print(f"Version: {version}")
    print(f"Tag: {tag_name}")
    print(f"Release type: {args.release_type}")
    print()

    # Check prerequisites
    if not check_gh_cli():
        print("Error: GitHub CLI (gh) is not installed or not authenticated")
        print("Install: https://cli.github.com/")
        print("Authenticate: gh auth login")
        sys.exit(1)

    # Check if tag exists
    if tag_exists(tag_name):
        if args.force:
            print(f"Tag {tag_name} exists - will delete and recreate")
            if args.create:
                run_command(['git', 'tag', '-d', tag_name])
                run_command(['git', 'push', 'origin', '--delete', tag_name], check=False)
        else:
            print(f"Error: Tag {tag_name} already exists. Use --force to delete and recreate.")
            sys.exit(1)

    if not args.create:
        print("DRY RUN - use --create to actually create tag and release")
        print()
        print("Would run:")
        print(f"  git tag {tag_name}")
        print(f"  git push origin {tag_name}")
        prerelease_flag = " --prerelease" if args.release_type != 'release' else ""
        print(f"  gh release create {tag_name} --title \"{addon_name} {version}\" --generate-notes{prerelease_flag}")
        return

    # Create and push tag
    print()
    print("Creating tag...")
    run_command(['git', 'tag', tag_name])
    
    print("Pushing tag...")
    run_command(['git', 'push', 'origin', tag_name])
    
    print("Creating GitHub release...")
    gh_cmd = [
        'gh', 'release', 'create', tag_name,
        '--title', f"{addon_name} {version}",
        '--generate-notes'
    ]
    if args.release_type != 'release':
        gh_cmd.append('--prerelease')
    run_command(gh_cmd)
    
    print()
    print(f"Done! Release {tag_name} created.")
    print("The GitHub Actions workflow will now build and attach the addon ZIP.")


if __name__ == '__main__':
    main()
