#!/usr/bin/env python3
"""
Script to add CrashReporterTests.swift to Xcode project test target.
"""

import re
import shutil
import uuid
from pathlib import Path

def generate_uuid():
    """Generate a unique 24-character hex ID for Xcode."""
    return uuid.uuid4().hex[:24].upper()

def add_crash_reporter_tests_to_project():
    """Add CrashReporterTests.swift to the Xcode project test target."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup the current file
    backup_path = project_path.with_name('project.pbxproj.backup4')
    shutil.copy2(project_path, backup_path)
    print(f"Created backup: {backup_path}")

    # Read the project file
    with open(project_path, 'r') as f:
        content = f.read()

    # Generate UUIDs for CrashReporterTests.swift
    file_ref_uuid = generate_uuid()
    build_file_uuid = generate_uuid()
    file_name = 'CrashReporterTests.swift'

    # 1. Add PBXBuildFile entry (find any test file to use as reference)
    # Look for ModelsTests.swift which should exist
    build_file_pattern = r'(\s+)([A-F0-9]{24}) /\* ModelsTests\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24}) /\* ModelsTests\.swift \*/; \};'
    build_file_match = re.search(build_file_pattern, content)

    if not build_file_match:
        print("ERROR: Could not find ModelsTests.swift in PBXBuildFile section")
        return False

    indent = build_file_match.group(1)
    insert_pos = build_file_match.end()

    build_file_entry = f'{indent}{build_file_uuid} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* {file_name} */; }};'
    content = content[:insert_pos] + '\n' + build_file_entry + content[insert_pos:]

    # 2. Add PBXFileReference entry (after ModelsTests.swift)
    file_ref_pattern = r'(\s+)([A-F0-9]{24}) /\* ModelsTests\.swift \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = ModelsTests\.swift; sourceTree = \"<group>\"; \};'
    file_ref_match = re.search(file_ref_pattern, content)

    if not file_ref_match:
        print("ERROR: Could not find ModelsTests.swift in PBXFileReference section")
        return False

    indent = file_ref_match.group(1)
    insert_pos = file_ref_match.end()

    file_ref_entry = f'{indent}{file_ref_uuid} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = \"<group>\"; }};'
    content = content[:insert_pos] + '\n' + file_ref_entry + content[insert_pos:]

    # 3. Add to MindFriendAppTests group (find the UUID for ModelsTests.swift and add after it)
    # First, get the UUID from the file reference we found
    models_tests_uuid = file_ref_match.group(2)

    # Find it in the group children array
    group_pattern = f'({models_tests_uuid} /\\* ModelsTests\\.swift \\*/,)'
    group_match = re.search(group_pattern, content)

    if not group_match:
        print("ERROR: Could not find ModelsTests.swift in MindFriendAppTests group")
        return False

    insert_pos = group_match.end()
    # Get the indentation by looking at the line
    line_start = content.rfind('\n', 0, group_match.start()) + 1
    line_text = content[line_start:group_match.start()]
    indent = re.match(r'(\s*)', line_text).group(1)

    group_entry = f'\n{indent}{file_ref_uuid} /* {file_name} */,'
    content = content[:insert_pos] + group_entry + content[insert_pos:]

    # 4. Add to test target's PBXSourcesBuildPhase (after ModelsTests.swift)
    sources_pattern = r'(\s+)([A-F0-9]{24}) /\* ModelsTests\.swift in Sources \*/,'
    sources_match = re.search(sources_pattern, content)

    if not sources_match:
        print("ERROR: Could not find ModelsTests.swift in PBXSourcesBuildPhase")
        return False

    indent = sources_match.group(1)
    insert_pos = sources_match.end()

    sources_entry = f'\n{indent}{build_file_uuid} /* {file_name} in Sources */,'
    content = content[:insert_pos] + sources_entry + content[insert_pos:]

    # Write the modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print(f"\nSuccessfully added {file_name} to Xcode test target!")
    print(f"  - File Reference UUID: {file_ref_uuid}")
    print(f"  - Build File UUID: {build_file_uuid}")
    print(f"  - Added to MindFriendAppTests group")

    return True

if __name__ == '__main__':
    success = add_crash_reporter_tests_to_project()
    if success:
        print("\nProject file updated successfully!")
        print("Backup saved to: MindFriendApp.xcodeproj/project.pbxproj.backup4")
    else:
        print("\nFailed to update project file!")
        exit(1)
