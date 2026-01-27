#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

# Track files we've seen
seen = {}
duplicates = []

app_target.source_build_phase.files.each do |build_file|
  next unless build_file.file_ref
  next unless build_file.file_ref.path
  
  path = build_file.file_ref.path.to_s
  if seen[path]
    duplicates << build_file
  else
    seen[path] = true
  end
end

puts "Found #{duplicates.length} duplicate build files"
duplicates.each do |dup|
  app_target.source_build_phase.remove_build_file(dup)
  puts "✓ Removed duplicate"
end

project.save
puts "Project cleaned"
