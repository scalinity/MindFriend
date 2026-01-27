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

# Find all Swift files on disk
all_files = Dir.glob("{MindFriendApp,MindFriendAppTests}/**/*.swift")

# Get files already in project
existing = project.files.map { |f| f.path.to_s }

# Add missing files
added_count = 0
all_files.each do |file_path|
  next if existing.include?(file_path)
  next unless File.exist?(file_path)
  
  is_test = file_path.include?("Tests")
  target = is_test ? test_target : app_target
  
  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)
  
  added_count += 1
  puts "✓ Added: #{file_path}"
end

project.save
puts "\nAdded #{added_count} files to project"
