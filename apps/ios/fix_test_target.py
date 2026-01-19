#!/usr/bin/env python3
"""
Remove Programs view files from test target's Sources build phase.
"""

import re
import shutil
from pathlib import Path

def fix_test_target():
    """Remove Programs files from test target."""

    project_path = Path("/Users/danny/Documents/Codez/Apps/MindFriend/apps/ios/MindFriendApp.xcodeproj/project.pbxproj")

    # Backup
    backup_path = project_path.with_suffix('.pbxproj.backup_test_fix')
    shutil.copy2(project_path, backup_path)
    print(f"Created backup: {backup_path}")

    # Read content
    with open(project_path, 'r') as f:
        lines = f.readlines()

    # Find the test target's Sources build phase
    # It's the section that contains test files AND Programs files
    in_sources_phase = False
    phase_start = -1
    phase_lines = []
    result_lines = []
    sources_phases_found = 0

    for i, line in enumerate(lines):
        if 'Begin PBXSourcesBuildPhase' in line:
            in_sources_phase = True
            phase_start = i
            phase_lines = [line]
        elif 'End PBXSourcesBuildPhase' in line:
            phase_lines.append(line)
            in_sources_phase = False
            sources_phases_found += 1

            # Check if this phase contains test files
            phase_content = ''.join(phase_lines)
            is_test_phase = 'Tests.swift in Sources' in phase_content
            has_programs = 'ProgramsLibraryView.swift in Sources' in phase_content

            if is_test_phase and has_programs:
                print(f"Found test Sources build phase at line {phase_start}")
                print("Removing Programs files from this phase...")

                # Filter out Programs view files
                filtered_lines = []
                for phase_line in phase_lines:
                    if any(pattern in phase_line for pattern in [
                        'ProgramsLibraryView.swift in Sources',
                        'ProgramDetailView.swift in Sources',
                        'ProgramDayView.swift in Sources',
                        'EnrollmentSheet.swift in Sources',
                        'EvidenceBadge.swift in Sources'
                    ]):
                        print(f"  Removing: {phase_line.strip()}")
                        continue
                    filtered_lines.append(phase_line)

                result_lines.extend(filtered_lines)
            else:
                result_lines.extend(phase_lines)

            phase_lines = []
        elif in_sources_phase:
            phase_lines.append(line)
        else:
            result_lines.append(line)

    # Write modified content
    with open(project_path, 'w') as f:
        f.writelines(result_lines)

    print(f"\nFixed! Processed {sources_phases_found} Sources build phases")
    print("Programs view files removed from test target")
    return True

if __name__ == '__main__':
    success = fix_test_target()
    if success:
        print("\nProject file updated successfully!")
    else:
        print("\nFailed to update project file!")
        exit(1)
