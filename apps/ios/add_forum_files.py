#!/usr/bin/env python3
"""
Add Community Forums files to Xcode project.
Adds ForumModels.swift, ForumService.swift, and 7 Forum views to proper locations.
"""

import re
import uuid
import sys

PROJECT_FILE = "MindFriendApp.xcodeproj/project.pbxproj"

# Files to add with their group paths
FILES_TO_ADD = [
    {
        "name": "ForumModels.swift",
        "path": "MindFriendApp/Core/ForumModels.swift",
        "group_path": ["MindFriendApp", "Core"]
    },
    {
        "name": "ForumService.swift",
        "path": "MindFriendApp/Networking/Services/ForumService.swift",
        "group_path": ["MindFriendApp", "Networking", "Services"]
    },
    {
        "name": "ForumHomeView.swift",
        "path": "MindFriendApp/Features/Forums/ForumHomeView.swift",
        "group_path": ["MindFriendApp", "Features", "Forums"]
    },
    {
        "name": "BoardView.swift",
        "path": "MindFriendApp/Features/Forums/BoardView.swift",
        "group_path": ["MindFriendApp", "Features", "Forums"]
    },
    {
        "name": "ThreadView.swift",
        "path": "MindFriendApp/Features/Forums/ThreadView.swift",
        "group_path": ["MindFriendApp", "Features", "Forums"]
    },
    {
        "name": "ComposeThreadView.swift",
        "path": "MindFriendApp/Features/Forums/ComposeThreadView.swift",
        "group_path": ["MindFriendApp", "Features", "Forums"]
    },
    {
        "name": "ComposeReplyView.swift",
        "path": "MindFriendApp/Features/Forums/ComposeReplyView.swift",
        "group_path": ["MindFriendApp", "Features", "Forums"]
    },
    {
        "name": "ReportView.swift",
        "path": "MindFriendApp/Features/Forums/ReportView.swift",
        "group_path": ["MindFriendApp", "Features", "Forums"]
    },
    {
        "name": "ModeratorDashboardView.swift",
        "path": "MindFriendApp/Features/Forums/ModeratorDashboardView.swift",
        "group_path": ["MindFriendApp", "Features", "Forums"]
    }
]


def generate_uuid():
    """Generate a 24-character hex UUID like Xcode uses."""
    return uuid.uuid4().hex.upper()[:24]


def find_group_id(content, group_path):
    """Find the group ID for a given path."""
    current_id = None

    for group_name in group_path:
        if current_id is None:
            # Find root group
            pattern = rf'([A-F0-9]{{24}}) /\* {re.escape(group_name)} \*/ = \{{[^}}]*isa = PBXGroup;'
            match = re.search(pattern, content)
        else:
            # Find child group within parent
            parent_section = re.search(
                rf'{current_id} /\* .* \*/ = \{{.*?children = \((.*?)\);.*?isa = PBXGroup;.*?\}};',
                content,
                re.DOTALL
            )
            if not parent_section:
                return None

            children_section = parent_section.group(1)
            pattern = rf'([A-F0-9]{{24}}) /\* {re.escape(group_name)} \*/,'
            match = re.search(pattern, children_section)

        if not match:
            return None
        current_id = match.group(1)

    return current_id


def create_group(content, parent_id, group_name):
    """Create a new group under parent."""
    new_group_id = generate_uuid()

    # Add group definition
    group_section_start = content.find("/* Begin PBXGroup section */")
    group_section_end = content.find("/* End PBXGroup section */")

    new_group_def = f"""\t\t{new_group_id} /* {group_name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tpath = {group_name};
\t\t\tsourceTree = "<group>";
\t\t}};
"""

    content = content[:group_section_end] + new_group_def + content[group_section_end:]

    # Add to parent's children
    parent_pattern = rf'({parent_id} /\* .* \*/ = \{{.*?children = \()(.*?)(\);.*?isa = PBXGroup;.*?\}};)'

    def add_child(match):
        return match.group(1) + match.group(2) + f"\n\t\t\t\t{new_group_id} /* {group_name} */," + match.group(3)

    content = re.sub(parent_pattern, add_child, content, flags=re.DOTALL)

    return content, new_group_id


def add_file_to_project(content, file_info, target_id):
    """Add a file to the project."""
    file_ref_id = generate_uuid()
    build_file_id = generate_uuid()

    # 1. Add PBXBuildFile entry
    build_file_section = content.find("/* Begin PBXBuildFile section */")
    build_file_end = content.find("/* End PBXBuildFile section */")

    new_build_file = f"\t\t{build_file_id} /* {file_info['name']} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {file_info['name']} */; }};\n"

    content = content[:build_file_end] + new_build_file + content[build_file_end:]

    # 2. Add PBXFileReference entry
    file_ref_section = content.find("/* Begin PBXFileReference section */")
    file_ref_end = content.find("/* End PBXFileReference section */")

    new_file_ref = f"\t\t{file_ref_id} /* {file_info['name']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info['name']}; sourceTree = \"<group>\"; }};\n"

    content = content[:file_ref_end] + new_file_ref + content[file_ref_end:]

    # 3. Add to group
    group_id = find_group_id(content, file_info['group_path'])

    if not group_id:
        # Need to create Forums group
        if "Forums" in file_info['group_path']:
            features_id = find_group_id(content, ["MindFriendApp", "Features"])
            if features_id:
                content, group_id = create_group(content, features_id, "Forums")

        if not group_id:
            print(f"Warning: Could not find or create group for {file_info['name']}")
            return content

    group_pattern = rf'({group_id} /\* .* \*/ = \{{.*?children = \()(.*?)(\);.*?isa = PBXGroup;.*?\}};)'

    def add_file_to_group(match):
        return match.group(1) + match.group(2) + f"\n\t\t\t\t{file_ref_id} /* {file_info['name']} */," + match.group(3)

    content = re.sub(group_pattern, add_file_to_group, content, flags=re.DOTALL)

    # 4. Add to PBXSourcesBuildPhase
    sources_pattern = rf'({target_id}.*?PBXSourcesBuildPhase.*?files = \()(.*?)(\);)'

    def add_to_sources(match):
        return match.group(1) + match.group(2) + f"\n\t\t\t\t{build_file_id} /* {file_info['name']} in Sources */," + match.group(3)

    content = re.sub(sources_pattern, add_to_sources, content, flags=re.DOTALL)

    return content


def main():
    print("Reading project.pbxproj...")

    try:
        with open(PROJECT_FILE, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: {PROJECT_FILE} not found. Run this script from apps/ios/")
        sys.exit(1)

    # Find MindFriendApp target ID
    target_match = re.search(r'([A-F0-9]{24}) /\* MindFriendApp \*/ = \{[^}]*isa = PBXNativeTarget;', content)
    if not target_match:
        print("Error: Could not find MindFriendApp target")
        sys.exit(1)

    target_id = target_match.group(1)
    print(f"Found MindFriendApp target: {target_id}")

    # Remove any existing Forum file references (in case they were added incorrectly)
    print("\nRemoving any existing Forum file references...")
    for file_info in FILES_TO_ADD:
        # Remove from PBXBuildFile
        content = re.sub(
            rf'\t\t[A-F0-9]{{24}} /\* {re.escape(file_info["name"])} in Sources \*/ = \{{.*?\}};\n',
            '',
            content
        )
        # Remove from PBXFileReference
        content = re.sub(
            rf'\t\t[A-F0-9]{{24}} /\* {re.escape(file_info["name"])} \*/ = \{{.*?\}};\n',
            '',
            content
        )

    # Add each file
    print("\nAdding Forum files to project...")
    for file_info in FILES_TO_ADD:
        print(f"  Adding {file_info['name']} to {'/'.join(file_info['group_path'])}...")
        content = add_file_to_project(content, file_info, target_id)

    # Write back
    print("\nWriting project.pbxproj...")
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

    print("\n✅ Successfully added all Forum files to Xcode project!")
    print("\nFiles added:")
    for file_info in FILES_TO_ADD:
        print(f"  - {file_info['name']}")
    print("\nReopen Xcode to see the changes.")


if __name__ == "__main__":
    main()
