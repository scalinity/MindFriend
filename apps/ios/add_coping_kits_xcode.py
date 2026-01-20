#!/usr/bin/env python3
"""
Add files to Xcode project.pbxproj using proper XML parsing
"""
import re
import uuid
import sys

PROJECT_FILE = "/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj"

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
    """Generate a UUID-like ID for Xcode (24 characters)"""
    return str(uuid.uuid4()).upper()[:24]

def add_file_reference(content, name, path):
    """Add PBXFileReference entry"""
    file_id = generate_id()
    new_ref = f'''\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'''

    # Find end of PBXFileReference section and insert
    pattern = r'(/\* End PBXFileReference section \*/)'
    content = re.sub(pattern, f"{new_ref}\n\t\t\\1", content)
    return content, file_id

def add_build_file(content, name, file_id):
    """Add PBXBuildFile entry"""
    new_build = f'''\t\t{file_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};'''

    # Find end of PBXBuildFile section and insert
    pattern = r'(/\* End PBXBuildFile section \*/)'
    content = re.sub(pattern, f"{new_build}\n\t\t\\1", content)
    return content

def add_to_sources_phase(content, file_id):
    """Add file to Sources build phase"""
    new_entry = f'\t\t\t\t{file_id} /* {file_id} */,'

    # Find the Sources phase and add after existing entries
    pattern = r'(/\* Begin PBXSourcesBuildPhase section \*/.*?)/\*/ End PBXSourcesBuildPhase section \*/'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        insert_point = match.end(1)
        content = content[:insert_point] + f"\n\t\t\t{new_entry}" + content[insert_point:]
    return content

def main():
    print("Reading project file...")
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    print("Adding files to project...")

    for name, path in NEW_FILES:
        # Check if file exists
        import os
        full_path = f"/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/{path}"
        if not os.path.exists(full_path):
            print(f"  Skipping {name} - file not found")
            continue

        # Add file reference
        content, file_id = add_file_reference(content, name, path)
        print(f"  Added file reference: {name} ({file_id})")

        # Add build file
        content = add_build_file(content, name, file_id)
        print(f"  Added build file: {name}")

        # Add to sources phase
        content = add_to_sources_phase(content, file_id)
        print(f"  Added to sources phase: {name}")

    print("Writing project file...")
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

    print(f"\nUpdated {PROJECT_FILE}")
    print("\nNext steps:")
    print("1. Open Xcode")
    print("2. Clean Build Folder (Cmd+Shift+K)")
    print("3. Build (Cmd+B)")
    print("4. Test on simulator")

if __name__ == "__main__":
    main()
