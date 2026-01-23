#!/usr/bin/env ruby
require 'xcodeproj'

# Open the Xcode project
project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the test target
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }

unless test_target
  puts "Error: Could not find MindFriendAppTests target"
  exit 1
end

# Helper function to find or create group hierarchy
def find_or_create_group(project, path_components)
  current_group = project.main_group

  path_components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }

    if child
      current_group = child
    else
      current_group = current_group.new_group(component, component)
    end
  end

  current_group
end

# Journey test files to add
test_files = [
  'MindFriendAppTests/Features/Journey/NarrativeListViewModelTests.swift',
  'MindFriendAppTests/Features/Journey/NarrativeDetailViewModelTests.swift',
  'MindFriendAppTests/Features/Journey/NarrativePreferencesViewModelTests.swift'
]

test_files.each do |file_path|
  # Check if file exists on disk
  unless File.exist?(file_path)
    puts "Warning: File not found: #{file_path}"
    next
  end

  # Check if already in project
  existing_file = project.files.find { |f| f.path.to_s.end_with?(File.basename(file_path)) }
  if existing_file
    puts "Skipping (already in project): #{file_path}"
    next
  end

  # Parse path components
  components = file_path.split('/')
  filename = components.pop

  # Find or create group
  group = find_or_create_group(project, components)

  # Add file reference
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  # Add to test target's sources build phase
  test_target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

# Save the project
project.save

puts "\nTest files added successfully!"
puts "Run 'xcodebuild test -scheme MindFriendApp' to run the tests."
