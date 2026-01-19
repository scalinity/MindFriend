#!/usr/bin/env python3
"""
Remove duplicate Voice file entries from Xcode project.
"""

import re
import shutil
from pathlib import Path
from collections import defaultdict

def remove_duplicates():
    """Remove duplicate Voice file build entries."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    backup_path = project_path.with_suffix('.pbxproj.backup_dedupe')
    shutil.copy2(project_path, backup_path)
    print(f"Created backup: {backup_path}")

    # Read content
    with open(project_path, 'r') as f:
        content = f.read()

    # Track which file references we keep
    kept_refs = {}
    file_patterns = [
        'VoiceServiceProtocol.swift',
        'VoiceCoordinator.swift',
        'VoiceWebSocketManager.swift',
        'VoiceAudioCapture.swift',
        'VoiceAudioPlayback.swift'
    ]

    # First pass: Find all PBXBuildFile entries for these files
    for filename in file_patterns:
        pattern = rf'([A-F0-9]{{24}}) /\* {filename} in Sources \*/ = {{isa = PBXBuildFile; fileRef = ([A-F0-9]{{24}}) /\* {filename} \*/; }};'
        matches = list(re.finditer(pattern, content))

        if len(matches) > 1:
            print(f"\nFound {len(matches)} duplicate entries for {filename}")
            # Keep only the first one
            kept_refs[filename] = {
                'buildFile': matches[0].group(1),
                'fileRef': matches[0].group(2)
            }

            # Remove all others
            for match in matches[1:]:
                print(f"  Removing buildFile: {match.group(1)}")
                content = content.replace(match.group(0), '')

    # Second pass: Find all PBXFileReference entries and remove duplicates
    for filename in file_patterns:
        pattern = rf'([A-F0-9]{{24}}) /\* {filename} \*/ = {{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = {filename}; sourceTree = "<group>"; }};'
        matches = list(re.finditer(pattern, content))

        if len(matches) > 1:
            print(f"\nFound {len(matches)} duplicate PBXFileReference entries for {filename}")
            # Keep the one that matches our kept buildFile
            kept_ref_id = kept_refs[filename]['fileRef']

            for match in matches:
                if match.group(1) != kept_ref_id:
                    print(f"  Removing fileRef: {match.group(1)}")
                    content = content.replace(match.group(0), '')

    # Third pass: Clean up duplicate entries in Sources build phase
    for filename in file_patterns:
        # Find all entries in build phases
        pattern = rf'\s+[A-F0-9]{{24}} /\* {filename} in Sources \*/,'
        matches = list(re.finditer(pattern, content))

        if len(matches) > 1:
            print(f"\nFound {len(matches)} entries in Sources build phase for {filename}")
            kept_id = kept_refs[filename]['buildFile']

            for match in matches:
                build_id = re.search(r'([A-F0-9]{24})', match.group(0)).group(1)
                if build_id != kept_id:
                    print(f"  Removing from build phase: {build_id}")
                    content = content.replace(match.group(0), '')

    # Write cleaned content
    with open(project_path, 'w') as f:
        f.write(content)

    print("\nDuplicates removed successfully!")
    return True

if __name__ == '__main__':
    success = remove_duplicates()
    if success:
        print("\nProject file cleaned!")
    else:
        print("\nFailed to clean project file!")
        exit(1)
