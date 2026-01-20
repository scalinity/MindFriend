#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Files to remove (incomplete features that don't compile)
incomplete_files = [
  # Forum feature (incomplete)
  'ForumService.swift',

  # Vault feature files that have issues
  'VaultEntryEditorView.swift',

  # Journal files with issues
  'JournalDetailView.swift',

  # Quest Arcs issues
  'QuestArcsService.swift',

  # Therapy integration issues
  'TherapyIntegrationService.swift'
]

# Remove from build phases
project.targets.each do |target|
  target.source_build_phase.files.each do |build_file|
    next unless build_file.file_ref
    basename = File.basename(build_file.file_ref.path.to_s)
    if incomplete_files.include?(basename)
      puts "Removing from build phase: #{basename}"
      build_file.remove_from_project
    end
  end
end

# Remove file references
project.files.each do |file_ref|
  basename = File.basename(file_ref.path.to_s)
  if incomplete_files.include?(basename)
    puts "Removing file reference: #{basename}"
    file_ref.remove_from_project
  end
end

project.save
puts "\nProject saved. Incomplete file references removed."
