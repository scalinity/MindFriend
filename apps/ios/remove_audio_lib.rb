#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

removed_count = 0
app_target.source_build_phase.files.each do |build_file|
  next unless build_file.file_ref
  file_path = build_file.file_ref.real_path.to_s
  
  if file_path.include?('Features/Audio/AudioLibraryView.swift')
    puts "Removing: Features/Audio/AudioLibraryView.swift"
    build_file.remove_from_project
    removed_count += 1
  end
end

project.save
puts "Total removed: #{removed_count}"
