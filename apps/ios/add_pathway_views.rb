#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main app target
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

unless app_target
  puts "Error: Could not find MindFriendApp target"
  exit 1
end

# Helper to find or create group hierarchy
def find_or_create_group(project, path_components)
  current_group = project.main_group

  path_components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == component
    }

    if child
      current_group = child
    else
      current_group = current_group.new_group(component, component)
    end
  end

  current_group
end

# Files to add
files_to_add = [
  {
    path: 'MindFriendApp/Features/Transitions/Components/PathwayCard.swift',
    groups: ['MindFriendApp', 'Features', 'Transitions', 'Components']
  },
  {
    path: 'MindFriendApp/Features/Transitions/PhaseProgressView.swift',
    groups: ['MindFriendApp', 'Features', 'Transitions']
  },
  {
    path: 'MindFriendApp/Features/Transitions/PathwayCompletionView.swift',
    groups: ['MindFriendApp', 'Features', 'Transitions']
  }
]

added_count = 0

files_to_add.each do |file_info|
  file_path = file_info[:path]

  # Check if file already exists in project
  existing_file = project.files.find { |f| f.path == File.basename(file_path) }

  if existing_file
    puts "⚠️  File already in project: #{file_path}"
    next
  end

  # Check if file exists on disk
  unless File.exist?(file_path)
    puts "❌ File not found on disk: #{file_path}"
    next
  end

  # Find or create the group
  group = find_or_create_group(project, file_info[:groups])

  # Add file reference
  file_ref = group.new_reference(File.basename(file_path))
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  # Add to build phase
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "✅ Added: #{file_path}"
  added_count += 1
end

# Save the project
project.save

puts "\n📦 Summary: Added #{added_count} files to Xcode project"
puts "Project saved: #{project_path}"
