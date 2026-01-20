# Partner Mode UX - Quick Start Guide

**For developers starting implementation**

---

## Pre-Implementation Checklist

Before you begin Phase 1, verify:

- [ ] Spec read and understood: `.claude/specs/partner-mode-ux-spec.md`
- [ ] Implementation plan reviewed: `.claude/plans/partner-mode-ux-plan.md`
- [ ] Database tables exist: `partner_links`, `couples_exercises`, `couples_exercise_sessions`
- [ ] RPCs available: `generate_buddy_code()`, `accept_buddy_invite()`
- [ ] Existing buddy system works (test in app)

---

## Phase 1: Get Started (3 hours)

### Step 1: Create ViewModel Skeleton (30 min)

```bash
cd apps/ios/MindFriendApp/Features
mkdir -p Partner/Components
touch Partner/PartnerModeViewModel.swift
```

**File:** `Partner/PartnerModeViewModel.swift`

```swift
import SwiftUI
import Combine

@MainActor
final class PartnerModeViewModel: ObservableObject {
    // MARK: - Dependencies
    private let dataService: SupabaseDataService
    
    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }
    
    // MARK: - State
    @Published var partnerState: PartnerState = .loading
    @Published var inviteCode: String?
    @Published var codeInput: String = ""
    @Published var isValidating = false
    @Published var sharingSettings: SharingSettings?
    @Published var partnerMoods: [MoodEntry] = []
    @Published var partnerQuest: Quest?
    @Published var couplesExercises: [CouplesExercise] = []
    @Published var activeSession: CouplesExerciseSession?
    @Published var error: CouplesModeError?
    @Published var showEncouragementPicker = false
    @Published var isSavingSharingSettings = false
    
    // MARK: - Actions (skeleton)
    func loadPartnerData() async { }
    func generateInviteCode() async { }
    func acceptInviteCode(_ code: String) async { }
    func updateSharingSettings(_ settings: SharingSettings) async { }
    func sendEncouragement(_ type: BuddyEncouragement.MessageType) async { }
    func loadCouplesExercises() async { }
    func startExerciseSession(_ exerciseId: UUID) async { }
}

// MARK: - Supporting Types
enum PartnerState: Equatable {
    case loading
    case noPartner
    case hasPartner(PartnerInfo)
}

struct PartnerInfo: Equatable {
    let partnerId: UUID
    let partnerName: String
    let partnerStreak: Int
    let hasCompletedToday: Bool
    let lastActive: Date
    let isSharingMood: Bool
    let isSharingExercises: Bool
}

struct SharingSettings: Equatable {
    var shareMood: Bool
    var shareExercises: Bool
}
```

### Step 2: Extend CouplesModels.swift (15 min)

**File:** `Core/Models/CouplesModels.swift`

Add this extension at the end of the file:

```swift
// MARK: - PartnerLink Extensions

extension PartnerLink {
    /// Returns current user's sharing settings
    func mySharingSettings(for userId: UUID) -> SharingSettings {
        if userId == userId1 {
            return SharingSettings(shareMood: user1ShareMood, shareExercises: user1ShareExercises)
        } else {
            return SharingSettings(shareMood: user2ShareMood, shareExercises: user2ShareExercises)
        }
    }
    
    /// Returns partner's sharing settings (what they share with me)
    func partnerSharingSettings(for userId: UUID) -> SharingSettings {
        if userId == userId1 {
            return SharingSettings(shareMood: user2ShareMood, shareExercises: user2ShareExercises)
        } else {
            return SharingSettings(shareMood: user1ShareMood, shareExercises: user1ShareExercises)
        }
    }
    
    /// Returns partner's user ID
    func partnerId(for userId: UUID) -> UUID? {
        if userId == userId1 { return userId2 }
        if userId == userId2 { return userId1 }
        return nil
    }
}
```

### Step 3: Add Service Methods (2 hours)

**File:** `Networking/Services/SupabaseDataService.swift`

Add after line 1972 (after `getPendingBuddyInvites()`):

**Copy the 13 service methods from the plan:**
- See plan section: "Service Methods (Add to SupabaseDataService.swift)"
- Methods start with `getActivePartnerLink()` and end with `acceptPartnerInvite()`
- Total: ~400 lines

### Step 4: Create Test File (30 min)

```bash
touch MindFriendAppTests/PartnerModeViewModelTests.swift
```

**File:** `MindFriendAppTests/PartnerModeViewModelTests.swift`

```swift
import XCTest
@testable import MindFriendApp

@MainActor
final class PartnerModeViewModelTests: XCTestCase {
    var viewModel: PartnerModeViewModel!
    var mockDataService: MockSupabaseDataService!
    
    override func setUp() async throws {
        // TODO: Set up mock service
    }
    
    func test_generateInviteCode_success() async throws {
        // TODO: Implement
    }
    
    // ... add other test stubs
}
```

### Step 5: Add to Xcode Project

```bash
cd apps/ios
```

**Create Ruby script:** `add_partner_files.rb`

```ruby
#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('MindFriendApp.xcodeproj')
app_target = project.targets.find { |t| t.name == 'MindFriendApp' }
test_target = project.targets.find { |t| t.name == 'MindFriendAppTests' }

def add_file(project, target, file_path)
  group = project.main_group
  components = file_path.split('/')
  filename = components.pop
  
  components.each do |component|
    child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component }
    group = child || group.new_group(component, component)
  end
  
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)
  
  puts "Added: #{file_path}"
end

# Phase 1 files
add_file(project, app_target, 'MindFriendApp/Features/Partner/PartnerModeViewModel.swift')
add_file(project, test_target, 'MindFriendAppTests/PartnerModeViewModelTests.swift')

project.save
```

Run:
```bash
chmod +x add_partner_files.rb
./add_partner_files.rb
```

### Step 6: Verify Compilation

```bash
xcodebuild -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 15' build
```

**Expected:** Build succeeds (tests may fail, that's OK)

---

## Phase 2-8: Follow the Plan

See full implementation plan for detailed steps: `.claude/plans/partner-mode-ux-plan.md`

Each phase includes:
- Files to create
- Code snippets
- Verification steps
- Checkpoints

---

## Common Pitfalls & Solutions

### Issue: "Cannot find 'SupabaseDataService' in scope"

**Solution:** Make sure `SupabaseDataService.swift` is in Xcode project target
```bash
# Verify file is in project
xcodebuild -list
```

### Issue: "Use of unresolved identifier 'SharingSettings'"

**Solution:** Make sure `CouplesModels.swift` extension is added correctly

### Issue: Files created but not compiling

**Solution:** Add to Xcode project using Ruby script
```bash
cd apps/ios
gem install xcodeproj
./add_partner_files.rb
```

### Issue: Tests not running

**Solution:** Verify test target includes test file
```bash
xcodebuild test -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MindFriendAppTests/PartnerModeViewModelTests
```

---

## Development Workflow

### Daily Workflow

1. **Morning:** Review phase checklist
2. **Code:** Implement features from phase
3. **Test:** Run tests after each component
4. **Checkpoint:** Verify phase completion criteria
5. **Log:** Update `docs/PROGRESS.md`

### Testing Strategy

```bash
# After each component
xcodebuild test -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 15'

# Full test suite
xcodebuild test -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 15' -resultBundlePath TestResults
```

### Git Workflow

```bash
# After each phase
git add .
git commit -m "feat(partner-mode): complete phase N - <description>

- Implemented <feature>
- Added tests for <component>
- Verified <checkpoint>

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Resources

| Resource | Location |
|----------|----------|
| Full Plan | `.claude/plans/partner-mode-ux-plan.md` |
| Spec | `.claude/specs/partner-mode-ux-spec.md` |
| Data Flow Diagrams | `.claude/plans/partner-mode-data-flow.md` |
| Summary | `.claude/plans/partner-mode-ux-summary.md` |
| Progress Log | `docs/PROGRESS.md` |

---

## Support

If you encounter blockers:

1. Check the full plan for detailed implementation steps
2. Review data flow diagrams for system understanding
3. Check existing buddy system code for reference patterns
4. See `Features/Buddy/InviteBuddySheet.swift` for UI patterns
5. See `Features/Home/HomeView.swift` for polling pattern

---

## Phase Checklist

Print this and check off as you go:

```
Phase 1: Foundation
  [ ] PartnerModeViewModel created
  [ ] CouplesModels extended
  [ ] 13 service methods added
  [ ] Test file created
  [ ] Files added to Xcode
  [ ] Build succeeds

Phase 2: Onboarding Views
  [ ] InviteCodeDisplay created
  [ ] CodeEntryField created
  [ ] PartnerOnboardingView created
  [ ] PartnerModeView shell created
  [ ] ViewModel logic implemented
  [ ] Manual test: code generation works

Phase 3: Dashboard Views
  [ ] PartnerStatusCard created
  [ ] SharedMoodCard created
  [ ] SharedQuestCard created
  [ ] PartnerPlaceholder created
  [ ] PartnerDashboardView created
  [ ] Polling implemented
  [ ] Manual test: dashboard shows data

Phase 4: Sharing Settings
  [ ] SharingToggleRow created
  [ ] PartnerSharingSettingsView created
  [ ] ViewModel logic implemented
  [ ] Manual test: toggles save

Phase 5: Shared Exercises
  [ ] SharedExercisesView created
  [ ] ViewModel logic implemented
  [ ] Manual test: exercises load

Phase 6: Encouragement
  [ ] EncouragementPickerSheet created
  [ ] ViewModel logic implemented
  [ ] Manual test: encouragement sends

Phase 7: Deep Linking
  [ ] AppState updated
  [ ] MindFriendApp updated
  [ ] PartnerModeView updated
  [ ] SettingsView updated
  [ ] Manual test: deep link works

Phase 8: Testing & Polish
  [ ] All unit tests pass
  [ ] Integration tests pass
  [ ] Accessibility verified
  [ ] Polish complete
```

---

**Ready to begin? Start with Phase 1, Step 1!**

EOF
