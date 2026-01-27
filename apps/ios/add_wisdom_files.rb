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

def add_file_to_project(project, target, file_path)
  # Check if file already exists in project
  basename = File.basename(file_path)
  if project.files.any? { |f| File.basename(f.path.to_s) == basename }
    puts "Skipped (exists): #{file_path}"
    return
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

# Community Wisdom Engine files
wisdom_files = [
  "MindFriendApp/Core/WisdomModels.swift",
  "MindFriendApp/Core/Services/WisdomService.swift",
  "MindFriendApp/Features/Community/WisdomFeedView.swift",
  "MindFriendApp/Features/Community/WisdomPrivacyView.swift",
  "MindFriendApp/Features/Community/StrategiesBrowserView.swift",
  "MindFriendApp/Features/Community/ContributeStrategySheet.swift"
]

wisdom_files.each do |file_path|
  add_file_to_project(project, app_target, file_path)
end

project.save
puts "\nProject saved successfully!"
