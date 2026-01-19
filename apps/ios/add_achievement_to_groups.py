#!/usr/bin/env python3
"""
Add Achievement files to their proper groups in Xcode.
"""

import re
import shutil
from pathlib import Path

def add_to_groups():
    """Add Achievement files to appropriate PBXGroup children arrays."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    backup_path = project_path.with_suffix('.pbxproj.backup_achievement_groups')
    shutil.copy2(project_path, backup_path)
    print(f"✓ Created backup: {backup_path.name}")

    # Read content
    with open(project_path, 'r') as f:
        content = f.read()

    print("\n1️⃣  Adding AchievementModels.swift to Core group...")
    # Add after PersonalizationModels
    pattern = r'(E07BD077743F197383217159 /\* Core \*/ = \{[\s\S]*?children = \([\s\S]*?)(26FCB1C4877346F08793DAE3 /\* PersonalizationModels\.swift \*/,)'

    match = re.search(pattern, content)
    if match:
        entry = f"\n\t\t\t\t08C259709AD456D7F6E78980 /* AchievementModels.swift */,"
        insert_pos = match.end(2)
        content = content[:insert_pos] + entry + content[insert_pos:]
        print("  ✓ Added AchievementModels.swift to Core group")
    else:
        print("  ⚠️  Could not find Core group")

    print("\n2️⃣  Adding AchievementService.swift to Services group...")
    # Add to Services group (D1E2F3A405162738495A6B8C)
    # Find the Services group and add after HealthKitService
    pattern = r'(D1E2F3A405162738495A6B8C /\* Services \*/ = \{[\s\S]*?children = \([\s\S]*?)(HKSVC01493347E53EC5C762 /\* HealthKitService\.swift \*/,)'

    match = re.search(pattern, content)
    if match:
        entry = f"\n\t\t\t\t8BFEAFFBA5736CC9172A7564 /* AchievementService.swift */,"
        insert_pos = match.end(2)
        content = content[:insert_pos] + entry + content[insert_pos:]
        print("  ✓ Added AchievementService.swift to Services group")
    else:
        print("  ⚠️  Could not find Services group")

    print("\n3️⃣  Creating Achievements group...")
    # Create Achievements group
    achievements_group_uuid = "2D2D57BC75095CB3DE6AE15A"  # Original UUID

    # Find Features group and add Achievements reference
    pattern = r'(35264B9E5E5375C2F72528A7 /\* Features \*/ = \{[\s\S]*?children = \([\s\S]*?)(CHLNG01493347E53EC5C762 /\* Challenges \*/,)'

    match = re.search(pattern, content)
    if match:
        entry = f"\n\t\t\t\t{achievements_group_uuid} /* Achievements */,"
        insert_pos = match.end(2)
        content = content[:insert_pos] + entry + content[insert_pos:]
        print("  ✓ Added Achievements group reference to Features")
    else:
        print("  ⚠️  Could not add Achievements to Features (will create standalone)")

    # Create Achievements group definition
    achievements_group_def = f'''\t{achievements_group_uuid} /* Achievements */ = {{
\t\tisa = PBXGroup;
\t\tchildren = (
\t\t\t\t2CAC252F4CDB5E56CA6E5ACD /* AchievementsView.swift */,
\t\t\t\t43C82E57CC19E06D9AB8F1B1 /* BadgeEarnedView.swift */,
\t\t);
\t\tpath = Achievements;
\t\tsourceTree = "<group>";
\t}};
'''

    # Insert after Services group
    pattern = r'(D1E2F3A405162738495A6B8C /\* Services \*/ = \{[\s\S]*?sourceTree = "<group>";[\s\S]*?\};)'

    match = re.search(pattern, content)
    if match:
        insert_pos = match.end(1)
        content = content[:insert_pos] + '\n' + achievements_group_def + content[insert_pos:]
        print("  ✓ Created Achievements group definition")
    else:
        print("  ❌ Could not create Achievements group")
        return False

    # Write modified content
    with open(project_path, 'w') as f:
        f.write(content)

    print("\n✅ Achievement files added to groups!")
    return True

if __name__ == '__main__':
    print("🔧 Adding Achievement files to groups...\n")
    success = add_to_groups()

    if success:
        print("\n" + "="*60)
        print("✅ SUCCESS! Files organized in project structure.")
        print("="*60)
    else:
        print("\n❌ Failed!")
        exit(1)
