#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Files to remove (broken/incomplete smart notification feature)
broken_files = [
  'SmartNotificationModels.swift',
  'SmartNotificationSettingsView.swift',
  'CalendarContextProvider.swift',
  'LocationContextProvider.swift',
  'BiometricContextProvider.swift',
  'FocusModeProvider.swift',
  'ContextEngine.swift',
  'NotificationQueue.swift',
  'EngagementTracker.swift',
  'MLPredictionEngine.swift',
  'SmartNotificationService.swift'
]

# Remove from build phases
project.targets.each do |target|
  target.source_build_phase.files.each do |build_file|
    next unless build_file.file_ref
    basename = File.basename(build_file.file_ref.path.to_s)
    if broken_files.include?(basename)
      puts "Removing from build phase: #{basename}"
      build_file.remove_from_project
    end
  end
end

# Remove file references
project.files.each do |file_ref|
  basename = File.basename(file_ref.path.to_s)
  if broken_files.include?(basename)
    puts "Removing file reference: #{basename}"
    file_ref.remove_from_project
  end
end

project.save
puts "\nProject saved. Broken file references removed."
