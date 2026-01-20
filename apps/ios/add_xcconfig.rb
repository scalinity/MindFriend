#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')

# Add xcconfig files to project if not already present
debug_config_file = project.files.find { |f| f.path == 'Debug.xcconfig' }
release_config_file = project.files.find { |f| f.path == 'Release.xcconfig' }

unless debug_config_file
  debug_config_file = project.new_file('Debug.xcconfig')
  puts "Added Debug.xcconfig to project"
end

unless release_config_file
  release_config_file = project.new_file('Release.xcconfig')
  puts "Added Release.xcconfig to project"
end

# Get the main target
target = project.targets.find { |t| t.name == 'MindFriendApp' }

# Assign xcconfig files to build configurations
project.build_configurations.each do |config|
  if config.name == 'Debug'
    config.base_configuration_reference = debug_config_file
    puts "Assigned Debug.xcconfig to Debug configuration"
  elsif config.name == 'Release'
    config.base_configuration_reference = release_config_file
    puts "Assigned Release.xcconfig to Release configuration"
  end
end

# Also set for the target configurations
target.build_configurations.each do |config|
  if config.name == 'Debug'
    config.base_configuration_reference = debug_config_file
    puts "Assigned Debug.xcconfig to target Debug configuration"
  elsif config.name == 'Release'
    config.base_configuration_reference = release_config_file
    puts "Assigned Release.xcconfig to target Release configuration"
  end
end

project.save
puts "Project saved successfully"
