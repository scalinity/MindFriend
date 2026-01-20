#!/usr/bin/env ruby
# Script to add all Creator feature files to the Xcode project

require 'xcodeproj'
require 'pathname'

# Paths
PROJECT_PATH = 'MindFriendApp.xcodeproj'
CREATOR_FILES = [
  'MindFriendApp/Core/Models/CreatorModels.swift',
  'MindFriendApp/Features/Creator/CreatorService.swift',
  'MindFriendApp/Features/Creator/CreatorDashboardView.swift',
  'MindFriendApp/Features/Creator/CreatorApplicationView.swift',
  'MindFriendApp/Features/Creator/CreatorMarketplaceView.swift',
  'MindFriendApp/Features/Creator/PublicCreatorProfileView.swift',
  'MindFriendApp/Features/Creator/CreatorContentPlayerView.swift'
]

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

def add_file_to_project(project, file_path, target_name)
  # Check if file already exists in project
  basename = File.basename(file_path)
  existing = project.files.find { |f| File.basename(f.path) == basename }
  if existing
    puts "Skipping #{file_path} (already in project)"
    return
  end

  is_test = file_path.include?('Tests')
  target = project.targets.find { |t| t.name == target_name }

  unless target
    puts "Target #{target_name} not found!"
    return
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

# Main
puts "Opening project: #{PROJECT_PATH}"
project = Xcodeproj::Project.open(PROJECT_PATH)

CREATOR_FILES.each do |file_path|
  add_file_to_project(project, file_path, 'MindFriendApp')
end

project.save
puts "\nProject saved successfully!"
