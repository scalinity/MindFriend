#!/usr/bin/env python3
"""
Add files to Xcode project.pbxproj
"""
import re
import os
import uuid

PROJECT_FILE = "MindFriendApp.xcodeproj/project.pbxproj"

# New files to add
NEW_FILES = [
    ("CopingKitModels.swift", "MindFriendApp/Core/CopingKitModels.swift"),
    ("CopingKitService.swift", "MindFriendApp/Core/Services/CopingKitService.swift"),
    ("CopingKitsViewModel.swift", "MindFriendApp/Features/CopingKits/CopingKitsViewModel.swift"),
    ("CopingKitsView.swift", "MindFriendApp/Features/CopingKits/CopingKitsView.swift"),
    ("CopingKitDetailView.swift", "MindFriendApp/Features/CopingKits/CopingKitDetailView.swift"),
    ("CopingKitStepView.swift", "MindFriendApp/Features/CopingKits/CopingKitStepView.swift"),
    ("CopingKitCompletionView.swift", "MindFriendApp/Features/CopingKits/CopingKitCompletionView.swift"),
]

def generate_id():
    """Generate a UUID-like ID for Xcode"""
    return str(uuid.uuid4()).upper()[:24]

def read_project():
    with open(PROJECT_FILE, 'r') as f:
        return f.read()

def write_project(content):
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

def add_file_references(content):
    """Add PBXFileReference entries"""
    # Find the end of PBXFileReference section
    pattern = r'(/\* End PBXFileReference section \*/)'

    new_refs = []
    for name, path in NEW_FILES:
        file_id = generate_id()
        new_ref = f'''\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'''
        new_refs.append(new_ref)

    new_section = "\n\t\t".join(new_refs) + "\n\t\t"
    replacement = new_section + r'\1'

    return re.sub(pattern, replacement, content)

def add_build_files(content):
    """Add PBXBuildFile entries"""
    pattern = r'(/\* End PBXBuildFile section \*/)'

    new_builds = []
    for name, path in NEW_FILES:
        file_id = generate_id()
        # Check if it's in Core or Features
        if "Core/" in path:
            target = "MindFriendApp"
        else:
            target = "MindFriendApp"

        new_build = f'''\t\t{file_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};'''
        new_builds.append(new_build)

    new_section = "\n\t\t".join(new_builds) + "\n\t\t"
    replacement = new_section + r'\1'

    return re.sub(pattern, replacement, content)

def add_to_groups(content):
    """Add files to appropriate PBXGroup sections"""
    # This is more complex - we need to add to the Core and Features groups
    # For simplicity, let's add them to the main group

    # Find a group section and add files there
    # We'll add them after Models.swift in the Core group

    pattern = r'(590C1A661399CE9EC2A66F1C /\* Models.swift \*[^}]+};)'

    for name, path in NEW_FILES:
        file_id = generate_id()
        new_entry = f'\t\t{file_id} /* {name} */,'
        content = re.sub(pattern, rf'\1\n\t\t{file_id} /* {name} */,', content)

    return content

def main():
    print("Adding CopingKit files to Xcode project...")

    content = read_project()

    # Add file references
    content = add_file_references(content)
    print("Added file references")

    # Add build files
    content = add_build_files(content)
    print("Added build files")

    # Add to groups (simplified - add to main group)
    # This is tricky in pbxproj, so we'll skip for now

    write_project(content)
    print(f"Updated {PROJECT_FILE}")

    print("\nFiles to add manually to Xcode:")
    for name, path in NEW_FILES:
        print(f"  - {path}")

if __name__ == "__main__":
    main()
