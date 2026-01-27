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

def file_exists_in_project?(project, filename)
  project.files.any? { |f| File.basename(f.path.to_s) == filename }
end

# Files to add to app target
app_files = [
  'MindFriendApp/Features/Generative/AudioPlayerViewModel.swift',
  'MindFriendApp/Features/Generative/GenerativeHomeView.swift',
  'MindFriendApp/Features/Generative/GeneratedMeditationView.swift',
  'MindFriendApp/Features/Generative/GeneratedStoryView.swift',
  'MindFriendApp/Features/Generative/VoicePreferencesView.swift',
  'MindFriendApp/Features/Generative/BackgroundSoundsSheet.swift',
  'MindFriendApp/Features/Generative/SleepTimerView.swift'
]

# Files to add to test target
test_files = [
  'MindFriendAppTests/GenerativeViewsTests.swift'
]

added_count = 0

app_files.each do |file_path|
  filename = File.basename(file_path)

  if file_exists_in_project?(project, filename)
    puts "Skipping (already exists): #{filename}"
    next
  end

  unless File.exist?(file_path)
    puts "Skipping (file not found): #{file_path}"
    next
  end

  group, fname = find_or_create_group(project, file_path)
  file_ref = group.new_reference(fname)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "Added to MindFriendApp: #{file_path}"
  added_count += 1
end

test_files.each do |file_path|
  filename = File.basename(file_path)

  if file_exists_in_project?(project, filename)
    puts "Skipping (already exists): #{filename}"
    next
  end

  unless File.exist?(file_path)
    puts "Skipping (file not found): #{file_path}"
    next
  end

  group, fname = find_or_create_group(project, file_path)
  file_ref = group.new_reference(fname)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  test_target.source_build_phase.add_file_reference(file_ref)

  puts "Added to MindFriendAppTests: #{file_path}"
  added_count += 1
end

project.save
puts "\nTotal files added: #{added_count}"
