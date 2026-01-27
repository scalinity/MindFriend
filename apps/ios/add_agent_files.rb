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

def file_exists_in_project?(project, basename)
  project.files.any? { |f| File.basename(f.path.to_s) == basename }
end

# Files to add
files_to_add = [
  # Models
  "MindFriendApp/Core/Models/AgentModels.swift",
  # Services
  "MindFriendApp/Core/Services/AgentService.swift",
  # Views
  "MindFriendApp/Features/Agent/AgentDashboardView.swift",
  "MindFriendApp/Features/Agent/AgentSettingsView.swift",
  "MindFriendApp/Features/Agent/AgentActionLogView.swift",
  # Components
  "MindFriendApp/Features/Agent/Components/AgentActionCard.swift",
  "MindFriendApp/Features/Agent/Components/SignalIndicatorView.swift",
]

test_files_to_add = [
  "MindFriendAppTests/AutonomousAgentTests.swift",
]

puts "Adding app files..."
files_to_add.each do |file_path|
  basename = File.basename(file_path)

  if file_exists_in_project?(project, basename)
    puts "  SKIP (exists): #{basename}"
    next
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "  ADDED: #{file_path}"
end

puts "\nAdding test files..."
test_files_to_add.each do |file_path|
  basename = File.basename(file_path)

  if file_exists_in_project?(project, basename)
    puts "  SKIP (exists): #{basename}"
    next
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  test_target.source_build_phase.add_file_reference(file_ref)

  puts "  ADDED: #{file_path}"
end

project.save
puts "\nProject saved successfully!"
