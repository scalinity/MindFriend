#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project_path = 'MindFriendApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }

def find_or_create_group(project, path_components)
  current_group = project.main_group

  path_components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }
    if child
      current_group = child
    else
      current_group = current_group.new_group(component, component)
    end
  end

  current_group
end

# Partner Mode files to add
partner_files = [
  'MindFriendApp/Features/Partner/PartnerModeView.swift',
  'MindFriendApp/Features/Partner/PartnerModeViewModel.swift',
  'MindFriendApp/Features/Partner/PartnerOnboardingView.swift',
  'MindFriendApp/Features/Partner/PartnerDashboardView.swift',
  'MindFriendApp/Features/Partner/PartnerSharingSettingsView.swift',
  'MindFriendApp/Features/Partner/SharedExercisesView.swift',
  'MindFriendApp/Features/Partner/EncouragementPickerSheet.swift',
  'MindFriendApp/Features/Partner/Components/PartnerStatusCard.swift',
  'MindFriendApp/Features/Partner/Components/SharedMoodCard.swift',
  'MindFriendApp/Features/Partner/Components/SharedQuestCard.swift',
  'MindFriendApp/Features/Partner/Components/CodeEntryField.swift',
  'MindFriendApp/Features/Partner/Components/InviteCodeDisplay.swift',
  'MindFriendApp/Features/Partner/Components/PartnerPlaceholder.swift'
]

partner_files.each do |file_path|
  # Check if file already in project
  basename = File.basename(file_path)
  existing = project.files.find { |f| File.basename(f.path.to_s) == basename }

  if existing
    puts "Skipping (already exists): #{basename}"
    next
  end

  # Get path components for group hierarchy
  components = Pathname.new(file_path).each_filename.to_a
  filename = components.pop

  # Find or create group
  group = find_or_create_group(project, components)

  # Add file reference
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  # Add to build phase
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

project.save
puts "\nProject saved successfully!"
