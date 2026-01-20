#!/usr/bin/env python3
import sys
import uuid

def generate_uuid():
    """Generate a 24-character uppercase hex string like Xcode uses"""
    return uuid.uuid4().hex.upper()[:24]

def add_files_to_pbxproj(pbxproj_path, files_to_add):
    """Add files to Xcode project.pbxproj"""
    with open(pbxproj_path, 'r') as f:
        content = f.read()
    
    # Generate UUIDs for each file
    file_refs = {}
    build_files = {}
    
    for file_path, group_name in files_to_add:
        file_name = file_path.split('/')[-1]
        file_ref_uuid = generate_uuid()
        build_file_uuid = generate_uuid()
        
        file_refs[file_path] = {
            'uuid': file_ref_uuid,
            'build_uuid': build_file_uuid,
            'name': file_name,
            'group': group_name
        }
    
    # Find the PBXBuildFile section
    pbx_build_file_marker = "/* Begin PBXBuildFile section */"
    pbx_build_file_end = "/* End PBXBuildFile section */"
    
    # Find the PBXFileReference section
    pbx_file_ref_marker = "/* Begin PBXFileReference section */"
    pbx_file_ref_end = "/* End PBXFileReference section */"
    
    # Find the PBXSourcesBuildPhase section
    pbx_sources_marker = "/* Begin PBXSourcesBuildPhase section */"
    
    # Add PBXBuildFile entries
    build_file_pos = content.find(pbx_build_file_marker) + len(pbx_build_file_marker)
    build_file_entries = "\n"
    for file_path, info in file_refs.items():
        build_file_entries += f"\t\t{info['build_uuid']} /* {info['name']} in Sources */ = {{isa = PBXBuildFile; fileRef = {info['uuid']} /* {info['name']} */; }};\n"
    
    content = content[:build_file_pos] + build_file_entries + content[build_file_pos:]
    
    # Add PBXFileReference entries
    file_ref_pos = content.find(pbx_file_ref_marker) + len(pbx_file_ref_marker)
    file_ref_entries = "\n"
    for file_path, info in file_refs.items():
        relative_path = file_path.replace('MindFriendApp/', '')
        file_ref_entries += f"\t\t{info['uuid']} /* {info['name']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {info['name']}; sourceTree = \"<group>\"; }};\n"
    
    content = content[:file_ref_pos] + file_ref_entries + content[file_ref_pos:]
    
    # Find PBXSourcesBuildPhase and add build file references
    sources_section_start = content.find(pbx_sources_marker)
    # Find the files = ( section within PBXSourcesBuildPhase
    files_marker_pos = content.find("files = (", sources_section_start)
    if files_marker_pos != -1:
        # Find the end of the files array
        files_end_pos = content.find(");", files_marker_pos)
        
        # Add our build file references
        build_ref_entries = ""
        for file_path, info in file_refs.items():
            build_ref_entries += f"\t\t\t\t{info['build_uuid']} /* {info['name']} in Sources */,\n"
        
        content = content[:files_end_pos] + build_ref_entries + content[files_end_pos:]
    
    # Add files to appropriate groups
    # Find Core group
    core_group_marker = "/* Core */ = {"
    core_group_pos = content.find(core_group_marker)
    if core_group_pos != -1:
        # Find children array in Core group
        children_pos = content.find("children = (", core_group_pos)
        children_end = content.find(");", children_pos)
        
        core_entries = ""
        for file_path, info in file_refs.items():
            if info['group'] == 'Core':
                core_entries += f"\t\t\t\t{info['uuid']} /* {info['name']} */,\n"
        
        if core_entries:
            content = content[:children_end] + core_entries + content[children_end:]
    
    # Find Services group
    services_group_marker = "/* Services */ = {"
    services_group_pos = content.find(services_group_marker)
    if services_group_pos != -1:
        children_pos = content.find("children = (", services_group_pos)
        children_end = content.find(");", children_pos)
        
        services_entries = ""
        for file_path, info in file_refs.items():
            if info['group'] == 'Services':
                services_entries += f"\t\t\t\t{info['uuid']} /* {info['name']} */,\n"
        
        if services_entries:
            content = content[:children_end] + services_entries + content[children_end:]
    
    # Find Extensions group
    extensions_group_marker = "/* Extensions */ = {"
    extensions_group_pos = content.find(extensions_group_marker)
    if extensions_group_pos != -1:
        children_pos = content.find("children = (", extensions_group_pos)
        children_end = content.find(");", children_pos)
        
        extensions_entries = ""
        for file_path, info in file_refs.items():
            if info['group'] == 'Extensions':
                extensions_entries += f"\t\t\t\t{info['uuid']} /* {info['name']} */,\n"
        
        if extensions_entries:
            content = content[:children_end] + extensions_entries + content[children_end:]
    
    # Write back
    with open(pbxproj_path, 'w') as f:
        f.write(content)
    
    print(f"✅ Added {len(file_refs)} files to Xcode project")
    for file_path in file_refs:
        print(f"  - {file_path}")

if __name__ == "__main__":
    pbxproj_path = "MindFriendApp.xcodeproj/project.pbxproj"
    
    files_to_add = [
        ("MindFriendApp/Core/PhotoMoodModels.swift", "Core"),
        ("MindFriendApp/Core/Services/PhotoMoodService.swift", "Services"),
        ("MindFriendApp/Core/Extensions/UIImage+Privacy.swift", "Extensions"),
    ]
    
    add_files_to_pbxproj(pbxproj_path, files_to_add)
