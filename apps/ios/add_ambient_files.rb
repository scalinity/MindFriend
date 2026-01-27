#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

raise "Could not find MindFriendApp target" unless app_target

def find_or_create_group(project, path_components)
  current_group = project.main_group

  path_components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }
    if child
      current_group = child
    else
      current_group = current_group.new_group(component, component)
    end
  end

  current_group
end

def add_file_to_target(project, file_path, target, group_path_components)
  filename = File.basename(file_path)

  # Check if file already exists in project
  existing = project.files.find { |f| f.path && File.basename(f.path.to_s) == filename }
  if existing
    puts "  Already exists: #{filename}"
    return
  end

  group = find_or_create_group(project, group_path_components)

  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  target.source_build_phase.add_file_reference(file_ref)
  puts "  Added: #{file_path}"
end

puts "Adding Ambient Wellness Presence files to Xcode project..."
puts

# Main app files
puts "Adding main app files to MindFriendApp target:"

main_app_files = [
  { path: 'MindFriendApp/Core/Models/AmbientModels.swift', group: ['MindFriendApp', 'Core', 'Models'] },
  { path: 'MindFriendApp/Core/Services/AmbientThemeService.swift', group: ['MindFriendApp', 'Core', 'Services'] },
  { path: 'MindFriendApp/Features/Ambient/AmbientSettingsView.swift', group: ['MindFriendApp', 'Features', 'Ambient'] },
  { path: 'MindFriendApp/Features/Ambient/DynamicBackgroundView.swift', group: ['MindFriendApp', 'Features', 'Ambient'] },
  { path: 'MindFriendApp/Features/Ambient/Components/ParticleView.swift', group: ['MindFriendApp', 'Features', 'Ambient', 'Components'] },
]

main_app_files.each do |file_info|
  add_file_to_target(project, file_info[:path], app_target, file_info[:group])
end

project.save
puts
puts "Done! Project saved successfully."
puts
puts "Note: Widget files (QuickBreathWidget, AffirmationWidget, WellnessScoreWidget)"
puts "are in MindFriendWidgets/ directory but the widget extension target"
puts "needs to be configured in Xcode to compile them."
