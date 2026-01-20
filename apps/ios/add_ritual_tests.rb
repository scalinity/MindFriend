#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project_path = 'apps/ios/MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }
unless test_target
  puts "MindFriendAppTests target not found!"
  exit 1
end

# Find the Tests group
tests_group = project.main_group.children.find { |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == 'MindFriendAppTests'
}

unless tests_group
  puts "MindFriendAppTests group not found!"
  exit 1
end

# Files to add
files_to_add = [
  'apps/ios/MindFriendAppTests/RitualModelsTests.swift',
  'apps/ios/MindFriendAppTests/RitualServiceTests.swift',
  'apps/ios/MindFriendAppTests/RitualSessionViewModelTests.swift'
]

files_to_add.each do |file_path|
  filename = File.basename(file_path)

  # Check if already in project
  existing = test_target.source_build_phase.files.find { |f|
    f.file_ref && File.basename(f.file_ref.path.to_s) == filename
  }

  if existing
    puts "Skipping #{filename} - already in project"
    next
  end

  # Add file reference
  file_ref = tests_group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  # Add to build phase
  test_target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{filename}"
end

project.save
puts "Done!"
