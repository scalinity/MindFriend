#!/usr/bin/env ruby
# Add Forum files to Xcode project using xcodeproj gem
# Install gem first: gem install xcodeproj

require 'xcodeproj'

PROJECT_PATH = 'MindFriendApp.xcodeproj'
TARGET_NAME = 'MindFriendApp'

# Files to add with their relative paths from project root
FILES_TO_ADD = [
  { path: 'MindFriendApp/Core/ForumModels.swift', group_path: ['MindFriendApp', 'Core'] },
  { path: 'MindFriendApp/Networking/Services/ForumService.swift', group_path: ['MindFriendApp', 'Networking', 'Services'] },
  { path: 'MindFriendApp/Features/Forums/ForumHomeView.swift', group_path: ['MindFriendApp', 'Features', 'Forums'] },
  { path: 'MindFriendApp/Features/Forums/BoardView.swift', group_path: ['MindFriendApp', 'Features', 'Forums'] },
  { path: 'MindFriendApp/Features/Forums/ThreadView.swift', group_path: ['MindFriendApp', 'Features', 'Forums'] },
  { path: 'MindFriendApp/Features/Forums/ComposeThreadView.swift', group_path: ['MindFriendApp', 'Features', 'Forums'] },
  { path: 'MindFriendApp/Features/Forums/ComposeReplyView.swift', group_path: ['MindFriendApp', 'Features', 'Forums'] },
  { path: 'MindFriendApp/Features/Forums/ReportView.swift', group_path: ['MindFriendApp', 'Features', 'Forums'] },
  { path: 'MindFriendApp/Features/Forums/ModeratorDashboardView.swift', group_path: ['MindFriendApp', 'Features', 'Forums'] }
]

# Open project
project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }

if target.nil?
  puts "Error: Target '#{TARGET_NAME}' not found"
  exit 1
end

puts "Found target: #{target.name}"

# Find or create group
def find_or_create_group(project, group_path)
  current_group = project.main_group

  group_path.each do |group_name|
    next_group = current_group.groups.find { |g| g.display_name == group_name }

    if next_group.nil?
      puts "  Creating group: #{group_name}"
      next_group = current_group.new_group(group_name, group_name)
    end

    current_group = next_group
  end

  current_group
end

# Remove any existing references to these files
FILES_TO_ADD.each do |file_info|
  file_name = File.basename(file_info[:path])

  # Find and remove existing references
  project.files.select { |f| f.display_name == file_name }.each do |file_ref|
    puts "Removing existing reference to: #{file_name}"
    file_ref.remove_from_project
  end
end

# Add files
FILES_TO_ADD.each do |file_info|
  file_path = file_info[:path]
  file_name = File.basename(file_path)

  # Find or create the group
  group = find_or_create_group(project, file_info[:group_path])

  puts "Adding #{file_name} to #{file_info[:group_path].join('/')}..."

  # Add file reference
  file_ref = group.new_file(file_path)

  # Add to build phase
  target.source_build_phase.add_file_reference(file_ref)
end

# Save project
puts "\nSaving project..."
project.save

puts "\n✅ Successfully added all Forum files!"
puts "\nFiles added:"
FILES_TO_ADD.each do |file_info|
  puts "  - #{File.basename(file_info[:path])}"
end
puts "\nReopen Xcode to see the changes."
