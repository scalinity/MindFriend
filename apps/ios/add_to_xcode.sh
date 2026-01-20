#!/bin/bash

PROJECT="MindFriendApp.xcodeproj"
FILES=(
  "MindFriendApp/Core/PhotoMoodModels.swift"
  "MindFriendApp/Core/Services/PhotoMoodService.swift"
  "MindFriendApp/Core/Extensions/UIImage+Privacy.swift"
)

echo "Adding files to Xcode project..."
for file in "${FILES[@]}"; do
  if [ -f "$file" ]; then
    echo "  ✓ Found: $file"
  else
    echo "  ✗ Missing: $file"
  fi
done

echo ""
echo "Note: Files need to be added manually via Xcode or using ruby xcodeproj gem"
echo "Run: gem install xcodeproj"
echo "Then use Ruby API to add files programmatically"
