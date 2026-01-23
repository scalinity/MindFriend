#!/bin/bash
# Fix Sentry.framework build errors
# Run this whenever you get "Sentry.framework couldn't be opened" errors

set -e

echo "🔧 Fixing Sentry package issues..."
echo ""

cd "$(dirname "$0")"

# Step 1: Clean derived data
echo "1️⃣  Cleaning derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/MindFriendApp-*

# Step 2: Clean local build folder
echo "2️⃣  Cleaning local build folder..."
rm -rf build .build

# Step 3: Re-resolve Swift packages
echo "3️⃣  Re-resolving Swift packages..."
xcodebuild -resolvePackageDependencies \
  -project MindFriendApp.xcodeproj \
  -scheme MindFriendApp

echo ""
echo "✅ Done! Sentry should now be fixed."
echo ""
echo "Next steps:"
echo "  • If using Xcode: Product → Build (⌘B)"
echo "  • If using CLI: xcodebuild -project MindFriendApp.xcodeproj -scheme MindFriendApp -destination 'generic/platform=iOS Simulator' build"
echo ""
