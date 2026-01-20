#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }

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

# Files to add
files_to_add = [
  # Core models
  "MindFriendApp/Core/CompanionMemoryModels.swift",
  # Service
  "MindFriendApp/Networking/Services/CompanionMemoryService.swift",
  # Memory feature views
  "MindFriendApp/Features/Memory/CompanionMemoryView.swift",
  "MindFriendApp/Features/Memory/EditMemorySheet.swift",
  "MindFriendApp/Features/Memory/DailyIntentBanner.swift",
  "MindFriendApp/Features/Memory/SetIntentSheet.swift",
  "MindFriendApp/Features/Memory/MemoryUsageIndicator.swift",
]

files_to_add.each do |file_path|
  # Check if file exists
  unless File.exist?(file_path)
    puts "SKIP (not found): #{file_path}"
    next
  end

  # Check if already in project
  basename = File.basename(file_path)
  already_exists = project.files.any? { |f| File.basename(f.path.to_s) == basename }

  if already_exists
    puts "SKIP (exists): #{file_path}"
    next
  end

  # Add to project
  is_test = file_path.include?("Tests")
  target = is_test ? test_target : app_target

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

project.save
puts "\nProject saved successfully!"
