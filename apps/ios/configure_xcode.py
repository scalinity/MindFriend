#!/usr/bin/env python3
"""
Carefully add Voice files to Xcode project - one-time, correct configuration.
"""

import re
import shutil
import uuid
from pathlib import Path

def generate_uuid():
    """Generate a unique 24-character hex ID for Xcode."""
    return uuid.uuid4().hex[:24].upper()

def configure_xcode():
    """Add Voice files to Xcode project."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    backup_path = project_path.with_suffix('.pbxproj.backup_configure')
    shutil.copy2(project_path, backup_path)
    print(f"✓ Created backup: {backup_path.name}")

    # Read content
    with open(project_path, 'r') as f:
        content = f.read()

    # Check if already added
    if 'VoiceServiceProtocol.swift' in content:
        print("\n⚠️  Voice files already in project - removing old entries first...")
        # Remove any existing Voice file entries
        for filename in ['VoiceServiceProtocol', 'VoiceCoordinator', 'VoiceWebSocketManager', 'VoiceAudioCapture', 'VoiceAudioPlayback']:
            content = re.sub(rf'\s+[A-F0-9]{{24}} /\* {filename}\.swift.*?\*/;?\n?', '', content)
            content = re.sub(rf'\s+[A-F0-9]{{24}} /\* {filename}\.swift.*?\*/,?\n?', '', content)

    # Define files with proper paths
    files = [
        {
            'name': 'VoiceServiceProtocol.swift',
            'path': 'Core/Services/VoiceServiceProtocol.swift',
            'group': 'Services',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid()
        },
        {
            'name': 'VoiceCoordinator.swift',
            'path': 'Features/VoiceMode/VoiceCoordinator.swift',
            'group': 'VoiceMode',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid()
        },
        {
            'name': 'VoiceWebSocketManager.swift',
            'path': 'Core/Services/Voice/VoiceWebSocketManager.swift',
            'group': 'Voice',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid()
        },
        {
            'name': 'VoiceAudioCapture.swift',
            'path': 'Core/Services/Voice/VoiceAudioCapture.swift',
            'group': 'Voice',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid()
        },
        {
            'name': 'VoiceAudioPlayback.swift',
            'path': 'Core/Services/Voice/VoiceAudioPlayback.swift',
            'group': 'Voice',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid()
        }
    ]

    print("\n1️⃣  Adding PBXBuildFile entries...")
    # 1. Add PBXBuildFile entries - find GrokVoiceService and add after it
    pattern = r'(\t\t)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = [A-F0-9]{24} /\* GrokVoiceService\.swift \*/; \};'
    match = re.search(pattern, content)
    if not match:
        print("❌ ERROR: Could not find GrokVoiceService in PBXBuildFile section")
        return False

    indent = match.group(1)
    insert_pos = match.end()

    for file_info in files:
        entry = f"\n{indent}{file_info['buildFile']} /* {file_info['name']} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info['fileRef']} /* {file_info['name']} */; }};"
        content = content[:insert_pos] + entry + content[insert_pos:]
        insert_pos += len(entry)
        print(f"  ✓ Added {file_info['name']}")

    print("\n2️⃣  Adding PBXFileReference entries...")
    # 2. Add PBXFileReference entries
    pattern = r'(\t\t)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = GrokVoiceService\.swift; sourceTree = "<group>"; \};'
    match = re.search(pattern, content)
    if not match:
        print("❌ ERROR: Could not find GrokVoiceService in PBXFileReference section")
        return False

    indent = match.group(1)
    insert_pos = match.end()

    for file_info in files:
        entry = f"\n{indent}{file_info['fileRef']} /* {file_info['name']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info['path']}; sourceTree = \"<group>\"; }};"
        content = content[:insert_pos] + entry + content[insert_pos:]
        insert_pos += len(entry)
        print(f"  ✓ Added {file_info['name']}")

    print("\n3️⃣  Adding to PBXSourcesBuildPhase (main app only)...")
    # 3. Add to Sources build phase - find the FIRST occurrence (main app, not test)
    pattern = r'(\t\t\t)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/,'
    matches = list(re.finditer(pattern, content))

    if not matches:
        print("❌ ERROR: Could not find GrokVoiceService in Sources build phase")
        return False

    # Use the first match (main app target)
    match = matches[0]
    indent = match.group(1)
    insert_pos = match.end()

    for file_info in files:
        entry = f"\n{indent}{file_info['buildFile']} /* {file_info['name']} in Sources */,"
        content = content[:insert_pos] + entry + content[insert_pos:]
        insert_pos += len(entry)
        print(f"  ✓ Added {file_info['name']}")

    print("\n4️⃣  Creating Voice group in Services...")
    # 4. Create Voice group - find Services group and add Voice subgroup
    # First, find the Services group UUID
    services_pattern = r'([A-F0-9]{24}) /\* Services \*/ = \{[\s\S]*?children = \(\n([\s\S]*?)\);[\s\S]*?path = Services;'
    services_match = re.search(services_pattern, content)

    if services_match:
        services_uuid = services_match.group(1)
        children_section = services_match.group(2)

        # Generate UUID for Voice group
        voice_group_uuid = generate_uuid()

        # Add Voice group reference to Services children
        # Find GrokVoiceService in children and add Voice group after it
        grok_pattern = r'(\t\t\t\t)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/,'
        grok_in_services = re.search(grok_pattern, children_section)

        if grok_in_services:
            indent = grok_in_services.group(1)
            insert_pos_in_children = grok_in_services.end()

            # Add VoiceServiceProtocol first
            vsp_file = [f for f in files if f['name'] == 'VoiceServiceProtocol.swift'][0]
            vsp_entry = f"\n{indent}{vsp_file['fileRef']} /* {vsp_file['name']} */,"

            # Add Voice group reference
            voice_group_entry = f"\n{indent}{voice_group_uuid} /* Voice */,"

            new_children = children_section[:insert_pos_in_children] + vsp_entry + voice_group_entry + children_section[insert_pos_in_children:]
            content = content.replace(children_section, new_children)
            print(f"  ✓ Added VoiceServiceProtocol.swift to Services group")
            print(f"  ✓ Added Voice group to Services")

        # Now create the Voice group definition
        voice_files_refs = [f for f in files if f['group'] == 'Voice']
        voice_children = '\n'.join([f"\t\t\t\t{f['fileRef']} /* {f['name']} */," for f in voice_files_refs])

        voice_group_def = f'''	{voice_group_uuid} /* Voice */ = {{
		isa = PBXGroup;
		children = (
{voice_children}
		);
		path = Voice;
		sourceTree = "<group>";
	}};
'''

        # Insert Voice group definition after Services group
        services_end_pattern = r'(path = Services;\n\t\tsourceTree = "<group>";\n\t\};)'
        services_end = re.search(services_end_pattern, content)
        if services_end:
            insert_pos = services_end.end()
            content = content[:insert_pos] + '\n' + voice_group_def + content[insert_pos:]
            print(f"  ✓ Created Voice group definition")

    print("\n5️⃣  Adding VoiceCoordinator to VoiceMode group...")
    # 5. Add VoiceCoordinator to VoiceMode group
    voicemode_pattern = r'([A-F0-9]{24}) /\* VoiceMode \*/ = \{[\s\S]*?children = \(\n([\s\S]*?)\);[\s\S]*?path = VoiceMode;'
    voicemode_match = re.search(voicemode_pattern, content)

    if voicemode_match:
        children_section = voicemode_match.group(2)

        # Find VoiceStateMachine and add VoiceCoordinator after it
        vsm_pattern = r'(\t\t\t\t)([A-F0-9]{24}) /\* VoiceStateMachine\.swift \*/,'
        vsm_match = re.search(vsm_pattern, children_section)

        if vsm_match:
            indent = vsm_match.group(1)
            insert_pos_in_children = vsm_match.end()

            vc_file = [f for f in files if f['name'] == 'VoiceCoordinator.swift'][0]
            vc_entry = f"\n{indent}{vc_file['fileRef']} /* {vc_file['name']} */,"

            new_children = children_section[:insert_pos_in_children] + vc_entry + children_section[insert_pos_in_children:]
            content = content.replace(children_section, new_children)
            print(f"  ✓ Added VoiceCoordinator.swift to VoiceMode group")

    # Write the modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print("\n✅ Xcode project configured successfully!")
    print(f"\n📋 Added files:")
    for file_info in files:
        print(f"  • {file_info['name']} → {file_info['group']} group")

    return True

if __name__ == '__main__':
    print("🔧 Configuring Xcode project...\n")
    success = configure_xcode()

    if success:
        print("\n" + "="*60)
        print("✅ SUCCESS! Xcode project is ready.")
        print("="*60)
        print("\nNext steps:")
        print("  1. Build the project:")
        print("     cd apps/ios")
        print("     xcodebuild -project MindFriendApp.xcodeproj -scheme MindFriendApp build")
        print("\n  2. Run tests:")
        print("     xcodebuild test -project MindFriendApp.xcodeproj -scheme MindFriendApp \\")
        print("       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'")
    else:
        print("\n❌ Configuration failed!")
        print("   Restoring from backup...")
        exit(1)
