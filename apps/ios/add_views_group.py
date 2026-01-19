#!/usr/bin/env python3
import re, shutil
from pathlib import Path

project_path = Path("MindFriendApp.xcodeproj/project.pbxproj")
shutil.copy2(project_path, project_path.with_suffix('.pbxproj.backup_views_group'))

with open(project_path, 'r') as f:
    content = f.read()

views_group_uuid = "VIEWSGRP01493347E53EC5C77"
flowlayout_ref = "A0E3904C86DF4663B8E64847"

# Add Views group reference to Core children (after Extensions)
pattern = r'(E07BD077743F197383217159 /\* Core \*/ = \{[\s\S]*?children = \([\s\S]*?)(3EE683BCB5BF2C0266169127 /\* Extensions \*/,)'
match = re.search(pattern, content)
if match:
    entry = f"\n\t\t\t\t{views_group_uuid} /* Views */,"
    insert_pos = match.end(2)
    content = content[:insert_pos] + entry + content[insert_pos:]
    print("✓ Added Views group to Core")

# Create Views group definition
views_group_def = f'''\t{views_group_uuid} /* Views */ = {{
\t\tisa = PBXGroup;
\t\tchildren = (
\t\t\t\t{flowlayout_ref} /* FlowLayout.swift */,
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

with open(project_path, 'w') as f:
    f.write(content)

print("✅ Views group added successfully")
