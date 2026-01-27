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

files_to_add = [
  "MindFriendApp/Core/Services/CalendarTriggerMonitor.swift",
  "MindFriendApp/Core/Services/OptimalTimingAnalyzer.swift",
  "MindFriendApp/Core/Services/InterventionNotificationManager.swift"
]

files_to_add.each do |file_path|
  next unless File.exist?(file_path)
  
  # Skip if already in project
  next if project.files.any? { |f| f.path.to_s == file_path }
  
  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)
  
  puts "Added: #{file_path}"
end

project.save
puts "Project updated"
