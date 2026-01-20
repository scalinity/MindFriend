#!/usr/bin/env python3
"""
Script to add Therapy Integration files to Xcode project.
"""

import hashlib
import re
import shutil
from pathlib import Path

def generate_uuid():
    """Generate a unique 24-character hex ID for Xcode."""
    import uuid
    return uuid.uuid4().hex[:24].upper()

def add_files_to_project():
    """Add therapy integration Swift files to the Xcode project."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup the original file
    backup_path = project_path.with_suffix('.pbxproj.backup')
    shutil.copy2(project_path, backup_path)
    print(f"Created backup: {backup_path}")

    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()

    # Files to add
    files_to_add = [
        {
            'name': 'TherapyModels.swift',
            'path': 'MindFriendApp/Core/TherapyModels.swift',
            'group': 'Core'
        },
        {
            'name': 'TherapyIntegrationService.swift',
            'path': 'MindFriendApp/Networking/Services/TherapyIntegrationService.swift',
            'group': 'Services'
        },
        {
            'name': 'ConnectedTherapistsView.swift',
            'path': 'MindFriendApp/Features/Therapy/ConnectedTherapistsView.swift',
            'group': 'Therapy'
        },
        {
            'name': 'InviteTherapistView.swift',
            'path': 'MindFriendApp/Features/Therapy/InviteTherapistView.swift',
            'group': 'Therapy'
        },
        {
            'name': 'TherapistDetailView.swift',
            'path': 'MindFriendApp/Features/Therapy/TherapistDetailView.swift',
            'group': 'Therapy'
        },
        {
            'name': 'SharingSettingsView.swift',
            'path': 'MindFriendApp/Features/Therapy/SharingSettingsView.swift',
            'group': 'Therapy'
        },
        {
            'name': 'AssignmentsView.swift',
            'path': 'MindFriendApp/Features/Therapy/AssignmentsView.swift',
            'group': 'Therapy'
        },
        {
            'name': 'AssignmentDetailView.swift',
            'path': 'MindFriendApp/Features/Therapy/AssignmentDetailView.swift',
            'group': 'Therapy'
        },
    ]

    # Generate UUIDs for each file (2 per file: fileRef and buildFile)
    for file_info in files_to_add:
        file_info['fileRef'] = generate_uuid()
        file_info['buildFile'] = generate_uuid()

    # Find the PBXBuildFile section
    build_file_section = re.search(r'/\* Begin PBXBuildFile section \*/', content)
    if not build_file_section:
        print("ERROR: Could not find PBXBuildFile section")
        return False

    # Find where Models.swift is in PBXBuildFile (use as anchor)
    anchor_build_pattern = r'(\s+)([A-F0-9]{24}) /\* Models\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}) /\* Models\.swift \*/; \};'
    anchor_build_match = re.search(anchor_build_pattern, content)

    if not anchor_build_match:
        print("ERROR: Could not find Models.swift in PBXBuildFile section")
        return False

    indent = anchor_build_match.group(1)
    insert_pos = anchor_build_match.end()

    # Build the PBXBuildFile entries
    build_file_entries = []
    for file_info in files_to_add:
        entry = f'{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info["fileRef"]} /* {file_info["name"]} */; }};'
        build_file_entries.append(entry)

    # Insert PBXBuildFile entries
    content = content[:insert_pos] + '\n' + '\n'.join(build_file_entries) + content[insert_pos:]

    # Find the PBXFileReference section
    file_ref_section = re.search(r'/\* Begin PBXFileReference section \*/', content)
    if not file_ref_section:
        print("ERROR: Could not find PBXFileReference section")
        return False

    # Find where Models.swift is in PBXFileReference
    anchor_ref_pattern = r'(\s+)([A-F0-9]{24}) /\* Models\.swift \*/ = \{isa = PBXFileReference; [^}]+\};'
    anchor_ref_match = re.search(anchor_ref_pattern, content)

    if not anchor_ref_match:
        print("ERROR: Could not find Models.swift in PBXFileReference section")
        return False

    indent = anchor_ref_match.group(1)
    insert_pos = anchor_ref_match.end()

    # Build the PBXFileReference entries
    file_ref_entries = []
    for file_info in files_to_add:
        entry = f'{indent}{file_info["fileRef"]} /* {file_info["name"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info["name"]}; sourceTree = "<group>"; }};'
        file_ref_entries.append(entry)

    # Insert PBXFileReference entries
    content = content[:insert_pos] + '\n' + '\n'.join(file_ref_entries) + content[insert_pos:]

    # Find the Sources build phase (PBXSourcesBuildPhase)
    sources_phase_pattern = r'(\s+)([A-F0-9]{24}) /\* Models\.swift in Sources \*/,'
    sources_phase_match = re.search(sources_phase_pattern, content)

    if not sources_phase_match:
        print("ERROR: Could not find Models.swift in PBXSourcesBuildPhase section")
        return False

    indent = sources_phase_match.group(1)
    insert_pos = sources_phase_match.end()

    # Build the Sources build phase entries
    sources_entries = []
    for file_info in files_to_add:
        entry = f'{indent}{file_info["buildFile"]} /* {file_info["name"]} in Sources */,'
        sources_entries.append(entry)

    # Insert Sources build phase entries
    content = content[:insert_pos] + '\n' + '\n'.join(sources_entries) + content[insert_pos:]

    # Write the modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print("Successfully added files to Xcode project:")
    for file_info in files_to_add:
        print(f"  - {file_info['name']}")

    return True

if __name__ == '__main__':
    success = add_files_to_project()
    if success:
        print("\nProject file updated successfully!")
        print("Backup saved to: MindFriendApp.xcodeproj/project.pbxproj.backup")
    else:
        print("\nFailed to update project file!")
        exit(1)
