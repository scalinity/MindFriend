#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }

def find_or_create_group(project, file_path)
  components = Pathname.new(file_path).each_filename.to_a
  filename = components.pop

  current_group = project.main_group
  components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }
    current_group = child || current_group.new_group(component, component)
  end

  [current_group, filename]
end

# New files to add for Stress Signature Fingerprint (F026)
files_to_add = [
  # Models
  "MindFriendApp/Core/StressSignatureModels.swift",
  # Services
  "MindFriendApp/Core/Services/PatternLearner.swift",
  "MindFriendApp/Core/Services/SignalMonitor.swift",
  "MindFriendApp/Core/Services/PatternDetector.swift",
  "MindFriendApp/Core/Services/EarlyInterventionService.swift",
  "MindFriendApp/Core/Services/StressSignatureEngine.swift",
  # Views
  "MindFriendApp/Features/Signature/SignatureOnboardingFlow.swift",
  "MindFriendApp/Features/Signature/WarningSignsDashboardView.swift",
  "MindFriendApp/Features/Signature/PatternAlertView.swift"
]

files_to_add.each do |file_path|
  # Check if file already exists in project
  basename = File.basename(file_path)
  if project.files.any? { |f| File.basename(f.path.to_s) == basename }
    puts "Skipping (already exists): #{file_path}"
    next
  end

  # Check if file exists on disk
  unless File.exist?(file_path)
    puts "Skipping (not on disk): #{file_path}"
    next
  end

  is_test = file_path.include?("Tests")
  target = is_test ? test_target : app_target

  group, filename = find_or_create_group(project, file_path)
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

project.save
puts "Project saved successfully!"
