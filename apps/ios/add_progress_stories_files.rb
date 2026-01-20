#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
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

# Progress Stories feature files
files_to_add = [
  "MindFriendApp/Features/ProgressStories/StoryCardView.swift",
  "MindFriendApp/Features/ProgressStories/ProgressStoryViewModel.swift",
  "MindFriendApp/Features/ProgressStories/ProgressStoryViewer.swift",
  "MindFriendApp/Features/ProgressStories/CircleShareSheet.swift"
]

files_to_add.each do |file_path|
  basename = File.basename(file_path)

  # Check if file already exists in project
  if project.files.any? { |f| File.basename(f.path.to_s) == basename }
    puts "Skipping (already in project): #{file_path}"
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
puts "Project saved successfully!"

# Add preview card file
preview_file = "MindFriendApp/Features/ProgressStories/ProgressStoryPreviewCard.swift"
basename = File.basename(preview_file)

unless project.files.any? { |f| File.basename(f.path.to_s) == basename }
  group, filename = find_or_create_group(project, preview_file)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{preview_file}"
end

project.save
puts "Preview card added successfully!"
