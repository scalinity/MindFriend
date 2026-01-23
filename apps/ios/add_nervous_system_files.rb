#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
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

# Files to add
files = [
  'MindFriendApp/Core/Models/NervousSystemModels.swift',
  'MindFriendApp/Core/Services/BehavioralPolyvagalTracker.swift',
  'MindFriendApp/Core/Services/CascadeDetector.swift',
  'MindFriendApp/Core/Services/PolyvagalClassifier.swift',
  'MindFriendApp/Core/Services/VoicePolyvagalExtractor.swift',
  'MindFriendApp/Core/Services/HRVPolyvagalExtractor.swift',
  'MindFriendApp/Core/Services/InterventionRecommender.swift',
  'MindFriendApp/Core/Services/NervousSystemStateEngine.swift'
]

files.each do |file_path|
  # Check if file is already in project
  if project.files.any? { |f| f.path == file_path }
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
