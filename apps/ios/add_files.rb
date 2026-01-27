#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

def find_or_create_group(project, file_path)
  components = file_path.split('/')
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

files = [
  'MindFriendApp/Core/Services/NetworkRetryService.swift',
  'MindFriendApp/Core/Services/PathwayCacheService.swift',
  'MindFriendApp/Core/Services/SecureStorage.swift'
]

files.each do |file_path|
  # Check if already exists
  basename = File.basename(file_path)
  if project.files.any? { |f| File.basename(f.path.to_s) == basename }
    puts "Already in project: #{file_path}"
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
puts "Project saved successfully"
