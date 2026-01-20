#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')

# Files to remove (based on directories deleted)
files_to_remove = [
  'CopingKitsViewModel.swift',
  'CopingKitCompletionView.swift',
  'CopingKitsView.swift',
  'CopingKitStepView.swift',
  'ThoughtRecordView.swift',
  'AssessmentView.swift',
  'AssignmentsView.swift',
  'AssignmentDetailView.swift',
  'BreathingPattern+Duration.swift',
]

# Find and remove file references
project.files.each do |file_ref|
  filename = File.basename(file_ref.path.to_s)
  if files_to_remove.include?(filename)
    puts "Removing: #{filename}"
    # Remove from build phases
    project.targets.each do |target|
      target.source_build_phase.files.each do |build_file|
        if build_file.file_ref == file_ref
          build_file.remove_from_project
        end
      end
    end
    file_ref.remove_from_project
  end
end

project.save
puts "Done!"
