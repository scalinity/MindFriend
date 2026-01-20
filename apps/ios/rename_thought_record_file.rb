#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

# Find and remove old reference
old_file_ref = project.files.find { |f| f.path.to_s == 'ThoughtRecordView.swift' && f.path.to_s.include?('AICoaching') }
if old_file_ref
  puts "Removing old ThoughtRecordView.swift reference..."
  # Remove from build phase
  app_target.source_build_phase.files.each do |build_file|
    if build_file.file_ref == old_file_ref
      build_file.remove_from_project
    end
  end
  # Remove file reference
  old_file_ref.remove_from_project
end

# Find the AICoaching group
def find_group(project, path_components)
  current = project.main_group
  path_components.each do |comp|
    current = current.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == comp }
    return nil unless current
  end
  current
end

ai_coaching_group = find_group(project, ['MindFriendApp', 'Features', 'AICoaching'])

if ai_coaching_group
  # Add new file reference
  new_file_ref = ai_coaching_group.new_reference('AICoachingThoughtRecordView.swift')
  new_file_ref.source_tree = '<group>'
  new_file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(new_file_ref)
  puts "Added AICoachingThoughtRecordView.swift to project"
else
  puts "Could not find AICoaching group"
end

project.save
