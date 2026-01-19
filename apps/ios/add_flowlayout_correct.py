#!/usr/bin/env python3
"""Add FlowLayout.swift to Xcode project correctly."""

import re
import shutil
import uuid
from pathlib import Path

def add_flowlayout():
    project_path = Path("MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    shutil.copy2(project_path, project_path.with_suffix('.pbxproj.backup_flowlayout_v2'))
    print("✓ Created backup")

    with open(project_path, 'r') as f:
        content = f.read()

    file_ref = uuid.uuid4().hex[:24].upper()
    build_file = uuid.uuid4().hex[:24].upper()

    print(f"\nGenerated UUIDs:")
    print(f"  FileRef:   {file_ref}")
    print(f"  BuildFile: {build_file}")

    # 1. Add PBXBuildFile entry (after GrokVoiceService)
    pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = [A-F0-9]{24} /\* GrokVoiceService\.swift \*/; \};'
    match = re.search(pattern, content)
    if match:
        indent = match.group(1)
        insert_pos = match.end()
        entry = f'\n{indent}{build_file} /* FlowLayout.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* FlowLayout.swift */; }};'
        content = content[:insert_pos] + entry + content[insert_pos:]
        print("\n✓ Added PBXBuildFile entry")
    else:
        print("\n❌ Could not find GrokVoiceService in PBXBuildFile section")
        return False

    # 2. Add PBXFileReference entry (after GrokVoiceService)
    pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = GrokVoiceService\.swift; sourceTree = "<group>"; \};'
    match = re.search(pattern, content)
    if match:
        indent = match.group(1)
        insert_pos = match.end()
        entry = f'\n{indent}{file_ref} /* FlowLayout.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FlowLayout.swift; sourceTree = "<group>"; }};'
        content = content[:insert_pos] + entry + content[insert_pos:]
        print("✓ Added PBXFileReference entry")
    else:
        print("❌ Could not find GrokVoiceService in PBXFileReference section")
        return False

    # 3. Add to Sources build phase (first occurrence = main app)
    pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/,'
    matches = list(re.finditer(pattern, content))
    if matches:
        match = matches[0]
        indent = match.group(1)
        insert_pos = match.end()
        entry = f'\n{indent}{build_file} /* FlowLayout.swift in Sources */,'
        content = content[:insert_pos] + entry + content[insert_pos:]
        print("✓ Added to Sources build phase")
    else:
        print("❌ Could not find GrokVoiceService in Sources phase")
        return False

    # 4. Create Views group and add to Core
    views_group_uuid = "VIEWSGRP01493347E53EC5C77"

    # Add Views group reference to Core children (after Extensions)
    pattern = r'(E07BD077743F197383217159 /\* Core \*/ = \{[\s\S]*?children = \([\s\S]*?)(3EE683BCB5BF2C0266169127 /\* Extensions \*/,)'
    match = re.search(pattern, content)
    if match:
        entry = f"\n\t\t\t\t{views_group_uuid} /* Views */,"
        insert_pos = match.end(2)
        content = content[:insert_pos] + entry + content[insert_pos:]
        print("✓ Added Views group to Core")
    else:
        print("⚠️  Could not add Views to Core (continuing anyway)")

    # Create Views group definition
    views_group_def = f'''\t{views_group_uuid} /* Views */ = {{
\t\tisa = PBXGroup;
\t\tchildren = (
\t\t\t\t{file_ref} /* FlowLayout.swift */,
\t\t);
\t\tpath = Views;
\t\tsourceTree = "<group>";
\t}};
'''

    # Insert after Extensions group
    pattern = r'(3EE683BCB5BF2C0266169127 /\* Extensions \*/ = \{[\s\S]*?sourceTree = "<group>";[\s\S]*?\};)'
    match = re.search(pattern, content)
    if match:
        insert_pos = match.end(1)
        content = content[:insert_pos] + '\n' + views_group_def + content[insert_pos:]
        print("✓ Created Views group definition")
    else:
        print("❌ Could not create Views group")
        return False

    # Write modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print("\n✅ FlowLayout.swift added successfully!")
    return True

if __name__ == '__main__':
    print("🔧 Adding FlowLayout.swift to Xcode project...\n")
    success = add_flowlayout()

    if success:
        print("\n" + "="*60)
        print("✅ SUCCESS! FlowLayout.swift is now in the project.")
        print("="*60)
    else:
        print("\n❌ Failed to add FlowLayout.swift!")
        exit(1)
