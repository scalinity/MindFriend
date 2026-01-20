#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')

files_to_check = [
  'AICoachingViewModel.swift',
  'ThoughtRecordView.swift',
  'CoachingSupportingViews.swift'
]

files_to_check.each do |filename|
  in_project = project.files.find { |f| File.basename(f.path.to_s) == filename }
  puts "#{filename}: #{in_project ? 'IN PROJECT' : 'NOT IN PROJECT'}"
end
