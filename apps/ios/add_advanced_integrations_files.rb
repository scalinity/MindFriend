#!/usr/bin/env ruby
# Script to add Advanced Integrations files to Xcode project
# Run from apps/ios/ directory

require 'xcodeproj'

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

# Advanced Integrations files to add
files_to_add = [
  'MindFriendApp/Core/Models/IntegrationTypes.swift',
  'MindFriendApp/Core/Services/EncryptionService.swift',
  'MindFriendApp/Core/Services/OAuthHandler.swift',
  'MindFriendApp/Core/Services/IntegrationManager.swift',
  'MindFriendApp/Core/Services/CalendarIntegrationService.swift',
]

added_count = 0

files_to_add.each do |file_path|
  puts "Processing: #{file_path}"

  is_test = file_path.include?("Tests")
  target = is_test ? test_target : app_target

  # Check if file already exists in project
  basename = File.basename(file_path)
  existing = project.files.find { |f| File.basename(f.path.to_s) == basename }
  if existing
    puts "  Skipping - already in project: #{basename}"
    next
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "  Added: #{file_path}"
  added_count += 1
end

project.save

puts "\n#{added_count} files added to project"
puts "Run 'xcodebuild -list' to verify"
