#!/usr/bin/env ruby
# Script to add new Swift files to Xcode project

require 'xcodeproj'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

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

# Files to add
files_to_add = [
  'MindFriendApp/Core/Models.swift',  # Modified, already in project
  'MindFriendApp/Features/SafetyPlan/SafetyPlanView.swift',
  'MindFriendApp/Features/SafetyPlan/SafetyPlanCondensedView.swift',
  'MindFriendApp/Features/SafetyPlan/SafetyPlanViewModel.swift',
  'MindFriendApp/Features/AICoaching/AICoachingView.swift',
  'MindFriendApp/Features/AICoaching/AICoachingViewModel.swift',
  'MindFriendApp/Features/AICoaching/ThoughtRecordView.swift',
  'MindFriendApp/Features/AICoaching/CoachingSupportingViews.swift',
  'MindFriendApp/Features/WeeklyWellbeing/WeeklyWellbeingView.swift',
  'MindFriendApp/Features/WeeklyWellbeing/WeeklyWellbeingViewModel.swift',
  'MindFriendApp/Features/WeeklyWellbeing/CircleHabitsView.swift',
  'MindFriendApp/Features/WeeklyWellbeing/CircleHabitsViewModel.swift',
  'MindFriendApp/Features/WeeklyWellbeing/CircleSupportingViews.swift',
]

files_to_add.each do |file_path|
  next unless File.exist?(file_path)

  basename = File.basename(file_path)
  next if project.files.any? { |f| File.basename(f.path.to_s) == basename }

  is_test = file_path.include?("Tests")
  target = is_test ? test_target : app_target

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

project.save
puts "\nProject saved successfully!"
