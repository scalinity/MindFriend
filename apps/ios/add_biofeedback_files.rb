#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }
watch_target = project.targets.find { |t| t.name == 'MindFriendWatch' }

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

# Biofeedback files to add to MindFriendApp target
app_files = [
  "MindFriendApp/Features/Biofeedback/BiofeedbackModels.swift",
  "MindFriendApp/Features/Biofeedback/BiofeedbackService.swift",
  "MindFriendApp/Features/Biofeedback/BiofeedbackExerciseView.swift",
  "MindFriendApp/Features/Biofeedback/AdaptiveBreathingView.swift",
  "MindFriendApp/Features/Biofeedback/SessionSummaryView.swift",
  "MindFriendApp/Features/Biofeedback/BiofeedbackSettingsView.swift",
  "MindFriendApp/Features/Biofeedback/HealthKit/HeartRateMonitor.swift",
  "MindFriendApp/Features/Biofeedback/Engine/AdaptationEngine.swift"
]

# Watch files
watch_files = [
  "MindFriendWatch/HeartRateStreamer.swift"
]

# Test files
test_files = [
  "MindFriendAppTests/BiofeedbackTests.swift"
]

added_count = 0

# Add app files
app_files.each do |file_path|
  basename = File.basename(file_path)
  next if file_exists_in_project?(project, basename)
  next unless File.exist?(file_path)

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "Added to MindFriendApp: #{file_path}"
  added_count += 1
end

# Add watch files
watch_files.each do |file_path|
  basename = File.basename(file_path)
  next if file_exists_in_project?(project, basename)
  next unless File.exist?(file_path)
  next unless watch_target

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  watch_target.source_build_phase.add_file_reference(file_ref)

  puts "Added to MindFriendWatch: #{file_path}"
  added_count += 1
end

# Add test files
test_files.each do |file_path|
  basename = File.basename(file_path)
  next if file_exists_in_project?(project, basename)
  next unless File.exist?(file_path)

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  test_target.source_build_phase.add_file_reference(file_ref)

  puts "Added to MindFriendAppTests: #{file_path}"
  added_count += 1
end

project.save
puts "\nTotal files added: #{added_count}"
