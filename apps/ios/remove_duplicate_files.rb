#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

# Files to check for duplicates (keep the one in Features/Audio and Features/Boundaries)
duplicates_to_remove = [
  'Features/Sensory/AudioLibraryView.swift',
  'Features/Chat/PriorityMatrixView.swift'
]

removed_count = 0
app_target.source_build_phase.files.each do |build_file|
  next unless build_file.file_ref
  file_path = build_file.file_ref.real_path.to_s
  
  duplicates_to_remove.each do |dup|
    if file_path.include?(dup)
      puts "Removing duplicate: #{dup}"
      build_file.remove_from_project
      removed_count += 1
    end
  end
end

project.save
puts "Total removed: #{removed_count} duplicates"
