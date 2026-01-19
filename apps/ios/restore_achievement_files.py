#!/usr/bin/env python3
"""
Re-add Achievement files to the main app target (they were accidentally removed).
"""

import re
import shutil
from pathlib import Path

def restore_achievements():
    """Restore Achievement files to Xcode project."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    backup_path = project_path.with_suffix('.pbxproj.backup_achievements')
    shutil.copy2(project_path, backup_path)
    print(f"✓ Created backup: {backup_path.name}")

    # Read content
    with open(project_path, 'r') as f:
        content = f.read()

    # Achievement files with UUIDs from backup
    files = [
        {'name': 'AchievementModels.swift', 'fileRef': '08C259709AD456D7F6E78980', 'buildFile': 'A3EE341DBF3431675011E3EA'},
        {'name': 'AchievementService.swift', 'fileRef': '8BFEAFFBA5736CC9172A7564', 'buildFile': '1DA666D60C73D3138CCD761A'},
        {'name': 'AchievementsView.swift', 'fileRef': '2CAC252F4CDB5E56CA6E5ACD', 'buildFile': '214F9CA89B7A0DA8EB602A1D'},
        {'name': 'BadgeEarnedView.swift', 'fileRef': '43C82E57CC19E06D9AB8F1B1', 'buildFile': 'D4D177E865651A197CE13108'},
    ]

    print("\n1️⃣  Adding PBXBuildFile entries...")
    # Find a good anchor point - use AppDelegate or another early file
    pattern = r'([\t ]+)([A-F0-9]{24}) /\* AppDelegate\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}) /\* AppDelegate\.swift \*/; \};'
    match = re.search(pattern, content)

    if match:
        indent = match.group(1)
        insert_pos = match.end()
        for file_info in files:
            entry = f'\n{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info["fileRef"]} /* {file_info["name"]} */; }};'
            content = content[:insert_pos] + entry + content[insert_pos:]
            insert_pos += len(entry)
        print(f"  ✓ Added {len(files)} PBXBuildFile entries")
    else:
        print("  ⚠️  Using fallback anchor")
        # Try GrokVoiceService as anchor
        pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/ = \{isa = PBXBuildFile'
        match = re.search(pattern, content)
        if match:
            indent = match.group(1)
            insert_pos = match.end()
            # Find the end of this line
            line_end = content.find(';', insert_pos) + 1
            for file_info in files:
                entry = f'\n{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info["fileRef"]} /* {file_info["name"]} */; }};'
                content = content[:line_end] + entry + content[line_end:]
                line_end += len(entry)
            print(f"  ✓ Added {len(files)} PBXBuildFile entries (fallback)")

    print("\n2️⃣  Adding PBXFileReference entries...")
    pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = GrokVoiceService\.swift; sourceTree = "<group>"; \};'
    match = re.search(pattern, content)

    if match:
        indent = match.group(1)
        insert_pos = match.end()
        for file_info in files:
            entry = f'\n{indent}{file_info["fileRef"]} /* {file_info["name"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info["name"]}; sourceTree = "<group>"; }};'
            content = content[:insert_pos] + entry + content[insert_pos:]
            insert_pos += len(entry)
        print(f"  ✓ Added {len(files)} PBXFileReference entries")
    else:
        print("  ❌ Could not find anchor for PBXFileReference")
        return False

    print("\n3️⃣  Adding to Sources build phase (main app only)...")
    # Find the main app's Sources phase (first occurrence of GrokVoiceService in Sources)
    pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/,'
    matches = list(re.finditer(pattern, content))

    if matches:
        # Use first match (main app)
        match = matches[0]
        indent = match.group(1)
        insert_pos = match.end()
        for file_info in files:
            entry = f'\n{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */,'
            content = content[:insert_pos] + entry + content[insert_pos:]
            insert_pos += len(entry)
        print(f"  ✓ Added {len(files)} files to Sources build phase")
    else:
        print("  ❌ Could not find Sources build phase")
        return False

    # Write modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print("\n✅ Achievement files restored successfully!")
    print("\nRestored files:")
    for file_info in files:
        print(f"  • {file_info['name']}")

    return True

if __name__ == '__main__':
    print("🔧 Restoring Achievement files to Xcode project...\n")
    success = restore_achievements()

    if success:
        print("\n" + "="*60)
        print("✅ SUCCESS! Achievement files restored.")
        print("="*60)
        print("\nNow rebuild the project.")
    else:
        print("\n❌ Failed to restore Achievement files!")
        exit(1)
