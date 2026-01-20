#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

thought_record_file = app_target.source_build_phase.files.find do |build_file|
  build_file.file_ref && build_file.file_ref.path.to_s.include?('ThoughtRecordView.swift')
end

if thought_record_file
  puts "ThoughtRecordView.swift IS in build phases"
  puts "Path: #{thought_record_file.file_ref.path}"
else
  puts "ThoughtRecordView.swift IS NOT in build phases!"
end

coaching_supporting_file = app_target.source_build_phase.files.find do |build_file|
  build_file.file_ref && build_file.file_ref.path.to_s.include?('CoachingSupportingViews.swift')
end

if coaching_supporting_file
  puts "CoachingSupportingViews.swift IS in build phases"
  puts "Path: #{coaching_supporting_file.file_ref.path}"
else
  puts "CoachingSupportingViews.swift IS NOT in build phases!"
end
