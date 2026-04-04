#!/usr/bin/env python3
"""
Release script for ChattyLittleNpc projects.
Reads version from .toc file, creates git tag, and creates GitHub release.

Usage:
    python release.py           # Dry run - shows what would happen
    python release.py --create  # Actually create tag and release
"""

import os
import re
import subprocess
import sys
import argparse


def find_toc_file():
    """Find the .toc file in the current directory or subdirectories."""
    # First check current directory
    for file in os.listdir('.'):
        if file.endswith('.toc'):
            return file
    
    # Check immediate subdirectories (for repo root)
    for item in os.listdir('.'):
        if os.path.isdir(item):
            for file in os.listdir(item):
                if file.endswith('.toc'):
                    return os.path.join(item, file)
    
    return None


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
    args = parser.parse_args()

    # Find .toc file
    toc_path = find_toc_file()
    if not toc_path:
        print("Error: No .toc file found in current directory or subdirectories")
        sys.exit(1)
    
    print(f"Found .toc file: {toc_path}")

    # Get version
    version = get_version_from_toc(toc_path)
    if not version:
        print("Error: Could not find ## Version in .toc file")
        sys.exit(1)
    
    addon_name = get_addon_name_from_toc(toc_path)
    tag_name = f"{args.tag_prefix}{version}"
    
    print(f"Addon: {addon_name}")
    print(f"Version: {version}")
    print(f"Tag: {tag_name}")
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
        print(f"  gh release create {tag_name} --title \"{addon_name} {version}\" --generate-notes")
        return

    # Create and push tag
    print()
    print("Creating tag...")
    run_command(['git', 'tag', tag_name])
    
    print("Pushing tag...")
    run_command(['git', 'push', 'origin', tag_name])
    
    print("Creating GitHub release...")
    run_command([
        'gh', 'release', 'create', tag_name,
        '--title', f"{addon_name} {version}",
        '--generate-notes'
    ])
    
    print()
    print(f"Done! Release {tag_name} created.")
    print("The GitHub Actions workflow will now build and attach the addon ZIP.")


if __name__ == '__main__':
    main()
