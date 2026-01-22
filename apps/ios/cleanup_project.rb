#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

# Files that don't exist and should be removed
orphaned_patterns = [
  'Biofeedback/Views',
  'Biofeedback/Services',
  'Biofeedback/Models',
  'BreathingHistoryView',
  'BreathingStatsView',
  'BreathingSummaryView',
  'BreathingSessionView',
  'BreathingCircleView',
  'ManualBreathingView',
  'BiofeedbackCoachView',
  'RespirationDetectionService',
  'BiofeedbackSessionManager',
  'BiofeedbackDataService',
  'BreathingPattern'
]

removed_count = 0

# Remove from source build phase
app_target.source_build_phase.files.each do |build_file|
  next unless build_file.file_ref
  file_path = build_file.file_ref.real_path.to_s rescue ''
  
  if orphaned_patterns.any? { |pattern| file_path.include?(pattern) } && !File.exist?(file_path)
    build_file.remove_from_project
    puts "Removed: #{file_path}"
    removed_count += 1
  end
end

# Remove orphaned file references
project.files.each do |file_ref|
  next unless file_ref.path
  file_path = file_ref.real_path.to_s rescue ''
  
  if orphaned_patterns.any? { |pattern| file_path.include?(pattern) } && !File.exist?(file_path)
    file_ref.remove_from_project
    puts "Removed file ref: #{file_path}"
    removed_count += 1
  end
end

project.save
puts "Cleaned up #{removed_count} orphaned references"
