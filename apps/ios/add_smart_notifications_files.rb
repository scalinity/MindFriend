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

# Smart Notification files to add
files_to_add = [
  # Models
  "MindFriendApp/Features/Notifications/Models/SmartNotificationModels.swift",

  # Context Providers
  "MindFriendApp/Features/Notifications/Context/CalendarContextProvider.swift",
  "MindFriendApp/Features/Notifications/Context/LocationContextProvider.swift",
  "MindFriendApp/Features/Notifications/Context/BiometricContextProvider.swift",
  "MindFriendApp/Features/Notifications/Context/FocusModeProvider.swift",

  # Core Services
  "MindFriendApp/Core/Services/ContextEngine.swift",
  "MindFriendApp/Core/Services/NotificationQueue.swift",
  "MindFriendApp/Core/Services/EngagementTracker.swift",
  "MindFriendApp/Core/Services/MLPredictionEngine.swift",
  "MindFriendApp/Core/Services/SmartNotificationService.swift",

  # Views
  "MindFriendApp/Features/Notifications/Views/SmartNotificationSettingsView.swift"
]

# Test files to add
test_files_to_add = [
  "MindFriendAppTests/SmartNotificationTests.swift"
]

puts "Adding Smart Notification files to Xcode project..."

files_to_add.each do |file_path|
  basename = File.basename(file_path)

  # Check if already exists
  if project.files.any? { |f| File.basename(f.path.to_s) == basename }
    puts "  Skipping (already exists): #{file_path}"
    next
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "  Added: #{file_path}"
end

puts "\nAdding test files..."

test_files_to_add.each do |file_path|
  basename = File.basename(file_path)

  # Check if already exists
  if project.files.any? { |f| File.basename(f.path.to_s) == basename }
    puts "  Skipping (already exists): #{file_path}"
    next
  end

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  test_target.source_build_phase.add_file_reference(file_ref)

  puts "  Added: #{file_path}"
end

project.save
puts "\nDone! Project saved."
