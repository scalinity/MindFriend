#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

# Files to add (relative to project root)
files_to_add = [
  "MindFriendApp/Features/Mentorship/FindMentorView.swift",
  "MindFriendApp/Features/Mentorship/MentorshipChatView.swift",
  "MindFriendApp/Features/Mentorship/MentorshipDataService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipEncryptionService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipFindMentorView.swift",
  "MindFriendApp/Features/Mentorship/MentorshipLifecycleService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipListView.swift",
  "MindFriendApp/Features/Mentorship/MentorshipMatchesView.swift",
  "MindFriendApp/Features/Mentorship/MentorshipMatchingService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipMessagingService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipProfileService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipProfileView.swift",
  "MindFriendApp/Features/Mentorship/MentorshipSafetyService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipService.swift",
  "MindFriendApp/Features/Mentorship/MentorshipTabView.swift",
  "MindFriendApp/Core/MentorshipMatchingModels.swift",
  "MindFriendApp/Core/MentorshipModels.swift",
]

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

# Add files
files_to_add.each do |file_path|
  # Skip if already in project
  next if app_target.source_build_phase.files.any? { |bf|
    bf.file_ref && File.basename(bf.file_ref.path.to_s) == File.basename(file_path)
  }

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "✅ Added: #{file_path}"
end

project.save
puts "\n✅ All mentorship files added to Xcode project"
