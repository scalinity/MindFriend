#!/usr/bin/env python3
import re, shutil, uuid
from pathlib import Path

project_path = Path("MindFriendApp.xcodeproj/project.pbxproj")
shutil.copy2(project_path, project_path.with_suffix('.pbxproj.backup_flowlayout'))

with open(project_path, 'r') as f:
    content = f.read()

file_ref = uuid.uuid4().hex[:24].upper()
build_file = uuid.uuid4().hex[:24].upper()

# Add PBXBuildFile
pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/ = \{isa = PBXBuildFile'
match = re.search(pattern, content)
if match:
    indent = match.group(1)
    insert_pos = content.find(';', match.end()) + 1
    entry = f'\n{indent}{build_file} /* FlowLayout.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* FlowLayout.swift */; }};'
    content = content[:insert_pos] + entry + content[insert_pos:]
    
# Add PBXFileReference
pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift \*/ = \{isa = PBXFileReference'
match = re.search(pattern, content)
if match:
    indent = match.group(1)
    insert_pos = content.find(';', match.end()) + 1
    entry = f'\n{indent}{file_ref} /* FlowLayout.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FlowLayout.swift; sourceTree = "<group>"; }};'
    content = content[:insert_pos] + entry + content[insert_pos:]

# Add to Sources
pattern = r'([\t ]+)([A-F0-9]{24}) /\* GrokVoiceService\.swift in Sources \*/,'
matches = list(re.finditer(pattern, content))
if matches:
    match = matches[0]
    indent = match.group(1)
    insert_pos = match.end()
    entry = f'\n{indent}{build_file} /* FlowLayout.swift in Sources */,'
    content = content[:insert_pos] + entry + content[insert_pos:]

with open(project_path, 'w') as f:
    f.write(content)

print(f"✅ Added FlowLayout.swift to project")
print(f"   FileRef: {file_ref}")
print(f"   BuildFile: {build_file}")
