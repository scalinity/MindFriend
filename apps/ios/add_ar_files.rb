#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
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

def file_exists_in_project?(project, filename)
  project.files.any? { |f| File.basename(f.path.to_s) == filename }
end

# AR feature files to add
ar_files = [
  "MindFriendApp/Core/ARExerciseModels.swift",
  "MindFriendApp/Core/Services/ARCapabilityService.swift",
  "MindFriendApp/Features/AR/ARExerciseService.swift",
  "MindFriendApp/Features/AR/ARSceneView.swift",
  "MindFriendApp/Features/AR/ARExerciseListView.swift",
  "MindFriendApp/Features/AR/BreathingOrbARView.swift",
  "MindFriendApp/Features/AR/Grounding541ARView.swift",
  "MindFriendApp/Features/AR/SafeSpaceARView.swift",
  "MindFriendApp/Features/AR/BreathingOrbFallbackView.swift",
  "MindFriendApp/Features/AR/Grounding541FallbackView.swift"
]

# Test files to add
test_files = [
  "MindFriendAppTests/ARExerciseTests.swift"
]

# Add app files
ar_files.each do |file_path|
  filename = File.basename(file_path)
  next if file_exists_in_project?(project, filename)

  group, fname = find_or_create_group(project, file_path)
  file_ref = group.new_reference(fname)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)
  puts "Added to MindFriendApp: #{file_path}"
end

# Add test files
test_files.each do |file_path|
  filename = File.basename(file_path)
  next if file_exists_in_project?(project, filename)

  group, fname = find_or_create_group(project, file_path)
  file_ref = group.new_reference(fname)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  test_target.source_build_phase.add_file_reference(file_ref)
  puts "Added to MindFriendAppTests: #{file_path}"
end

project.save
puts "\nXcode project updated successfully!"
