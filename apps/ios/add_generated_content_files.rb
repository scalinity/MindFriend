#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

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

# New GeneratedContent files to add
files_to_add = [
  "MindFriendApp/Features/GeneratedContent/GeneratedContentModels.swift",
  "MindFriendApp/Features/GeneratedContent/GeneratedContentService.swift",
  "MindFriendApp/Features/GeneratedContent/ContentRequestView.swift",
  "MindFriendApp/Features/GeneratedContent/ContentLibraryView.swift",
  "MindFriendApp/Features/GeneratedContent/ContentPlayerView.swift",
  "MindFriendApp/Features/GeneratedContent/VoicePreferencesView.swift"
]

files_to_add.each do |file_path|
  # Check if file already exists in project
  basename = File.basename(file_path)
  existing = project.files.find { |f| File.basename(f.path.to_s) == basename }

  if existing
    puts "Already exists: #{file_path}"
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
