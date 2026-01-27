#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

# Files to remove (these no longer exist in the filesystem)
orphan_files = [
  'FindMentorView.swift',  # Renamed to FindMentorView.swift.unused
]

removed_count = 0

# Remove from source build phase
app_target.source_build_phase.files.each do |build_file|
  next unless build_file.file_ref
  file_name = File.basename(build_file.file_ref.path.to_s)
  if orphan_files.include?(file_name)
    build_file.remove_from_project
    puts "Removed from build phase: #{file_name}"
    removed_count += 1
  end
end

# Remove file references from project
project.files.each do |file_ref|
  file_name = File.basename(file_ref.path.to_s)
  if orphan_files.include?(file_name)
    file_ref.remove_from_project
    puts "Removed file reference: #{file_name}"
  end
end

project.save
puts "\nProject saved. Removed #{removed_count} orphaned file references."
