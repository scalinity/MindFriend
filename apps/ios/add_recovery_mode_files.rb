#!/usr/bin/env ruby
# Add Recovery Mode feature files to Xcode project

require 'xcodeproj'
require 'pathname'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

def find_or_create_group(project, file_path)
  components = Pathname.new(file_path).each_filename.to_a
  filename = components.pop

  current_group = project.main_group
  components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }
    current_group = child || current_group.new_group(component, component)
  end

  [current_group, filename]
end

def file_exists_in_project?(project, filename)
  project.files.any? { |f| File.basename(f.path.to_s) == filename }
end

# Files to add
files_to_add = [
  "MindFriendApp/Features/Home/RecoveryModeHomeView.swift",
  "MindFriendApp/Features/Profile/RecoveryModeSettingsView.swift"
]

files_to_add.each do |file_path|
  basename = File.basename(file_path)

  if file_exists_in_project?(project, basename)
    puts "Skipping (already exists): #{file_path}"
    next
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

project.save
puts "\nProject saved successfully!"
