#!/usr/bin/env python3
"""
Add Voice files to Xcode project - clean, single add only to main app target.
"""

import re
import shutil
import uuid
from pathlib import Path

def generate_uuid():
    """Generate a unique 24-character hex ID for Xcode."""
    return uuid.uuid4().hex[:24].upper()

def add_voice_files():
    """Add Voice files to the Xcode project."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    backup_path = project_path.with_suffix('.pbxproj.backup_final')
    shutil.copy2(project_path, backup_path)
    print(f"Created backup: {backup_path}")

    # Read content
    with open(project_path, 'r') as f:
        content = f.read()

    # Files to add
    voice_files = [
        {'name': 'VoiceServiceProtocol.swift', 'path': 'Core/Services', 'fileRef': generate_uuid(), 'buildFile': generate_uuid()},
        {'name': 'VoiceCoordinator.swift', 'path': 'Features/VoiceMode', 'fileRef': generate_uuid(), 'buildFile': generate_uuid()},
        {'name': 'VoiceWebSocketManager.swift', 'path': 'Core/Services/Voice', 'fileRef': generate_uuid(), 'buildFile': generate_uuid()},
        {'name': 'VoiceAudioCapture.swift', 'path': 'Core/Services/Voice', 'fileRef': generate_uuid(), 'buildFile': generate_uuid()},
        {'name': 'VoiceAudioPlayback.swift', 'path': 'Core/Services/Voice', 'fileRef': generate_uuid(), 'buildFile': generate_uuid()},
    ]

    # 1. Add PBXBuildFile entries (after GrokVoiceService)
    pattern = r'(\s+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/; \};'
    match = re.search(pattern, content)
    if not match:
        print("ERROR: Could not find GrokVoiceService.swift in PBXBuildFile section")
        return False

    indent = match.group(1)
    insert_pos = match.end()
    build_file_entries = []
    for file_info in voice_files:
        entry = f'\n{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info["fileRef"]} /* {file_info["name"]} */; }};'
        build_file_entries.append(entry)

    content = content[:insert_pos] + ''.join(build_file_entries) + content[insert_pos:]

    # 2. Add PBXFileReference entries (after GrokVoiceService)
    pattern = r'(\s+)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = GrokVoiceService\.swift; sourceTree = "<group>"; \};'
    match = re.search(pattern, content)
    if not match:
        print("ERROR: Could not find GrokVoiceService.swift in PBXFileReference section")
        return False

    indent = match.group(1)
    insert_pos = match.end()
    file_ref_entries = []
    for file_info in voice_files:
        entry = f'\n{indent}{file_info["fileRef"]} /* {file_info["name"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info["name"]}; sourceTree = "<group>"; }};'
        file_ref_entries.append(entry)

    content = content[:insert_pos] + ''.join(file_ref_entries) + content[insert_pos:]

    # 3. Add to MAIN APP Sources build phase (NOT test target)
    # Find the Sources build phase that contains the main app files (GrokVoiceService)
    # We need to find the build phase, then add our files after GrokVoiceService
    pattern = r'(\s+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/,'
    matches = list(re.finditer(pattern, content))

    # The FIRST match should be the main app target (before the test target)
    if not matches:
        print("ERROR: Could not find GrokVoiceService.swift in Sources build phase")
        return False

    match = matches[0]  # Take the first one (main app)
    indent = match.group(1)
    insert_pos = match.end()
    sources_entries = []
    for file_info in voice_files:
        entry = f'\n{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */,'
        sources_entries.append(entry)

    content = content[:insert_pos] + ''.join(sources_entries) + content[insert_pos:]

    print(f"\nAdded {len(voice_files)} Voice files to Xcode project:")
    for file_info in voice_files:
        print(f"  - {file_info['name']}")

    # Write modified content
    with open(project_path, 'w') as f:
        f.write(content)

    return True

if __name__ == '__main__':
    success = add_voice_files()
    if success:
        print("\nProject file updated successfully!")
    else:
        print("\nFailed to update project file!")
        exit(1)
