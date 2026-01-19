#!/usr/bin/env python3
"""
Script to add new Swift files to Xcode project with proper group structure.
"""

import re
import shutil
import uuid
from pathlib import Path

def generate_uuid():
    """Generate a unique 24-character hex ID for Xcode."""
    return uuid.uuid4().hex[:24].upper()

def find_group_uuid(content, group_name_pattern):
    """Find the UUID of a group by its name or path."""
    # Search for: someUUID /* GroupName */ = {
    pattern = rf'([A-F0-9]{{24}}) /\* {group_name_pattern} \*/ = \{{'
    match = re.search(pattern, content)
    if match:
        return match.group(1)
    return None

def add_files_to_project():
    """Add new Swift files to the Xcode project."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup the original file
    backup_path = project_path.with_suffix('.pbxproj.backup2')
    shutil.copy2(project_path, backup_path)
    print(f"Created backup: {backup_path}")

    # Restore from original backup
    original_backup = project_path.with_suffix('.pbxproj.backup')
    if original_backup.exists():
        shutil.copy2(original_backup, project_path)
        print("Restored from original backup")

    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()

    # Files to add with their target groups
    files_to_add = [
        {
            'name': 'VoiceServiceProtocol.swift',
            'group': 'Services',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid(),
        },
        {
            'name': 'VoiceCoordinator.swift',
            'group': 'VoiceMode',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid(),
        },
    ]

    # Voice subdirectory files
    voice_files = [
        {
            'name': 'VoiceWebSocketManager.swift',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid(),
        },
        {
            'name': 'VoiceAudioCapture.swift',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid(),
        },
        {
            'name': 'VoiceAudioPlayback.swift',
            'fileRef': generate_uuid(),
            'buildFile': generate_uuid(),
        },
    ]

    # Create Voice group UUID
    voice_group_uuid = generate_uuid()

    # 1. Add PBXBuildFile entries
    build_file_pattern = r'(\s+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/; \};'
    build_file_match = re.search(build_file_pattern, content)

    if not build_file_match:
        print("ERROR: Could not find GrokVoiceService.swift in PBXBuildFile section")
        return False

    indent = build_file_match.group(1)
    insert_pos = build_file_match.end()

    all_files = files_to_add + voice_files
    build_file_entries = []
    for file_info in all_files:
        entry = f'{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info["fileRef"]} /* {file_info["name"]} */; }};'
        build_file_entries.append(entry)

    content = content[:insert_pos] + '\n' + '\n'.join(build_file_entries) + content[insert_pos:]

    # 2. Add PBXFileReference entries
    file_ref_pattern = r'(\s+)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = GrokVoiceService\.swift; sourceTree = "<group>"; \};'
    file_ref_match = re.search(file_ref_pattern, content)

    if not file_ref_match:
        print("ERROR: Could not find GrokVoiceService.swift in PBXFileReference section")
        return False

    indent = file_ref_match.group(1)
    insert_pos = file_ref_match.end()

    file_ref_entries = []
    for file_info in all_files:
        entry = f'{indent}{file_info["fileRef"]} /* {file_info["name"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info["name"]}; sourceTree = "<group>"; }};'
        file_ref_entries.append(entry)

    content = content[:insert_pos] + '\n' + '\n'.join(file_ref_entries) + content[insert_pos:]

    # 3. Add to Services group
    services_group_pattern = r'(children = \(\n)(\s+)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/,'
    services_group_match = re.search(services_group_pattern, content)

    if not services_group_match:
        print("ERROR: Could not find Services group children")
        return False

    indent = services_group_match.group(2)
    insert_pos = services_group_match.end()

    # Add VoiceServiceProtocol and Voice group to Services
    services_entries = []
    for file_info in files_to_add:
        if file_info['group'] == 'Services':
            services_entries.append(f'{indent}{file_info["fileRef"]} /* {file_info["name"]} */,')

    # Add Voice group reference
    services_entries.append(f'{indent}{voice_group_uuid} /* Voice */,')

    content = content[:insert_pos] + '\n' + '\n'.join(services_entries) + content[insert_pos:]

    # 4. Create Voice group before Services group ends
    voice_group_entry = f'''		{voice_group_uuid} /* Voice */ = {{
			isa = PBXGroup;
			children = (
				{voice_files[0]["fileRef"]} /* {voice_files[0]["name"]} */,
				{voice_files[1]["fileRef"]} /* {voice_files[1]["name"]} */,
				{voice_files[2]["fileRef"]} /* {voice_files[2]["name"]} */,
			);
			path = Voice;
			sourceTree = "<group>";
		}};
'''

    # Find end of Services group and insert Voice group definition
    services_end_pattern = r'(\s+path = Services;\n\s+sourceTree = "<group>";\n\s+\};)'
    services_end_match = re.search(services_end_pattern, content)

    if services_end_match:
        insert_pos = services_end_match.end()
        content = content[:insert_pos] + '\n' + voice_group_entry + content[insert_pos:]

    # 5. Add VoiceCoordinator to VoiceMode group
    voice_mode_pattern = r'(children = \(\n)(\s+)([A-F0-9]{24}) /\* VoiceStateMachine\.swift \*/,'
    voice_mode_match = re.search(voice_mode_pattern, content)

    if voice_mode_match:
        indent = voice_mode_match.group(2)
        insert_pos = voice_mode_match.end()

        for file_info in files_to_add:
            if file_info['group'] == 'VoiceMode':
                entry = f'\n{indent}{file_info["fileRef"]} /* {file_info["name"]} */,'
                content = content[:insert_pos] + entry + content[insert_pos:]
                insert_pos += len(entry)

    # 6. Add to Sources build phase
    sources_phase_pattern = r'(\s+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/,'
    sources_phase_match = re.search(sources_phase_pattern, content)

    if not sources_phase_match:
        print("ERROR: Could not find GrokVoiceService.swift in PBXSourcesBuildPhase section")
        return False

    indent = sources_phase_match.group(1)
    insert_pos = sources_phase_match.end()

    sources_entries = []
    for file_info in all_files:
        entry = f'{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */,'
        sources_entries.append(entry)

    content = content[:insert_pos] + '\n' + '\n'.join(sources_entries) + content[insert_pos:]

    # Write the modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print("\nSuccessfully added files to Xcode project:")
    for file_info in files_to_add:
        print(f"  - {file_info['name']} (in {file_info['group']} group)")
    for file_info in voice_files:
        print(f"  - {file_info['name']} (in Voice group)")

    return True

if __name__ == '__main__':
    success = add_files_to_project()
    if success:
        print("\nProject file updated successfully!")
        print("Backup saved to: MindFriendApp.xcodeproj/project.pbxproj.backup2")
    else:
        print("\nFailed to update project file!")
        exit(1)
