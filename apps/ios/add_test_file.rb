#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }

# Find or create test group
test_group = project.main_group.children.find { |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == 'MindFriendAppTests'
} || project.main_group.new_group('MindFriendAppTests', 'MindFriendAppTests')

# Add the test file
file_ref = test_group.new_reference('MentorshipServiceTests.swift')
file_ref.source_tree = '<group>'
file_ref.last_known_file_type = 'sourcecode.swift'
test_target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Added MentorshipServiceTests.swift to project"
