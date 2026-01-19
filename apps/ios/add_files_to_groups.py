#!/usr/bin/env python3
"""
Add Voice files to existing Xcode project groups.
Simple approach: add files to their parent groups.
"""

import re
import shutil
from pathlib import Path

def add_to_groups():
    """Add Voice files to appropriate PBXGroup children arrays."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    backup_path = project_path.with_suffix('.pbxproj.backup_groups')
    shutil.copy2(project_path, backup_path)
    print(f"✓ Created backup: {backup_path.name}")

    # Read content
    with open(project_path, 'r') as f:
        content = f.read()

    # File references (already in project.pbxproj)
    voice_files = {
        'VoiceServiceProtocol.swift': '60418A4AA355420291C65815',
        'VoiceCoordinator.swift': 'D5080539168C40C7A52261C4',
        'VoiceWebSocketManager.swift': '46938BB0F51347729AF9099B',
        'VoiceAudioCapture.swift': '2C9EF470938C4B0BAA62606D',
        'VoiceAudioPlayback.swift': '03E223AF44DB41EF97780875'
    }

    print("\n1️⃣  Adding VoiceServiceProtocol to Services group...")
    # Find Services group and add VoiceServiceProtocol after GrokVoiceService
    pattern = r'(D1E2F3A405162738495A6B8C /\* Services \*/ = \{[\s\S]*?children = \([\s\S]*?)(A1B2C3D4E5F60718293A4B5D /\* GrokVoiceService\.swift \*/,)'

    match = re.search(pattern, content)
    if match:
        vsp_entry = f"\n\t\t\t\t{voice_files['VoiceServiceProtocol.swift']} /* VoiceServiceProtocol.swift */,"
        insert_pos = match.end(2)
        content = content[:insert_pos] + vsp_entry + content[insert_pos:]
        print("  ✓ Added VoiceServiceProtocol.swift to Services group")
    else:
        print("  ❌ Could not find Services group")
        return False

    print("\n2️⃣  Adding VoiceCoordinator to VoiceMode group...")
    # Find VoiceMode group and add VoiceCoordinator after VoiceStateMachine
    pattern = r'(VCMDGRP001493347E53EC5C762 /\* VoiceMode \*/ = \{[\s\S]*?children = \([\s\S]*?)(VCSM001493347E53EC5C762 /\* VoiceStateMachine\.swift \*/,)'

    match = re.search(pattern, content)
    if match:
        vc_entry = f"\n\t\t\t\t{voice_files['VoiceCoordinator.swift']} /* VoiceCoordinator.swift */,"
        insert_pos = match.end(2)
        content = content[:insert_pos] + vc_entry + content[insert_pos:]
        print("  ✓ Added VoiceCoordinator.swift to VoiceMode group")
    else:
        print("  ❌ Could not find VoiceMode group")
        return False

    print("\n3️⃣  Adding Voice subgroup with WebSocket/Audio files...")
    # Create Voice group and add to Services
    voice_group_uuid = "VCEGRP001493347E53EC5C77"  # Fixed UUID for Voice group

    # Add Voice group reference to Services children (after VoiceServiceProtocol)
    pattern = r'(D1E2F3A405162738495A6B8C /\* Services \*/ = \{[\s\S]*?children = \([\s\S]*?60418A4AA355420291C65815 /\* VoiceServiceProtocol\.swift \*/,)'

    match = re.search(pattern, content)
    if match:
        voice_group_ref = f"\n\t\t\t\t{voice_group_uuid} /* Voice */,"
        insert_pos = match.end(1)
        content = content[:insert_pos] + voice_group_ref + content[insert_pos:]
        print("  ✓ Added Voice group reference to Services")
    else:
        print("  ⚠️  Could not add Voice group to Services (continuing anyway)")

    # Create Voice group definition (after Services group closes)
    voice_group_def = f'''\t{voice_group_uuid} /* Voice */ = {{
\t\tisa = PBXGroup;
\t\tchildren = (
\t\t\t\t{voice_files['VoiceWebSocketManager.swift']} /* VoiceWebSocketManager.swift */,
\t\t\t\t{voice_files['VoiceAudioCapture.swift']} /* VoiceAudioCapture.swift */,
\t\t\t\t{voice_files['VoiceAudioPlayback.swift']} /* VoiceAudioPlayback.swift */,
\t\t);
\t\tpath = Voice;
\t\tsourceTree = "<group>";
\t}};
'''

    # Insert after Services group definition
    pattern = r'(D1E2F3A405162738495A6B8C /\* Services \*/ = \{[\s\S]*?sourceTree = "<group>";[\s\S]*?\};)'

    match = re.search(pattern, content)
    if match:
        insert_pos = match.end(1)
        content = content[:insert_pos] + '\n' + voice_group_def + content[insert_pos:]
        print("  ✓ Created Voice group definition")
    else:
        print("  ❌ Could not create Voice group")
        return False

    # Write modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print("\n✅ Files added to groups successfully!")
    return True

if __name__ == '__main__':
    print("🔧 Adding Voice files to Xcode project groups...\n")
    success = add_to_groups()

    if success:
        print("\n" + "="*60)
        print("✅ SUCCESS! Voice files added to project structure.")
        print("="*60)
        print("\nNext: Build the project")
        print("  cd apps/ios")
        print("  xcodebuild -project MindFriendApp.xcodeproj -scheme MindFriendApp build")
    else:
        print("\n❌ Failed to add files to groups!")
        print("   Backup saved at: project.pbxproj.backup_groups")
        exit(1)
