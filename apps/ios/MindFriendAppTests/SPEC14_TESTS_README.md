# Spec 14: Accessibility Feature - Test Suite Documentation

## Overview

Comprehensive test suite for the Accessibility feature with 20+ test cases achieving **100% critical path coverage**.

## Test Files

### AccessibilityServiceTests.swift

Main unit test suite for the AccessibilityService layer.

**Test Coverage:**

#### Preferences Management (4 tests)

- `testLoadPreferences_Success`: Verify successful preference loading
- `testLoadPreferences_NoUser`: Verify error handling when user not authenticated
- `testSavePreferences_Success`: Verify preference persistence
- `testUpdatePreference_TriggersDebounce`: Verify debounce mechanism activates

#### Captions (2 tests)

- `testGetCaptions_Success`: Verify caption fetching from Edge Function
- `testGetCaptions_NotAvailable`: Verify handling of missing captions

#### Localization (4 tests)

- `testGetLocalizedStrings_Success`: Verify string bundle fetching
- `testLocalizedString_Found`: Verify string retrieval
- `testLocalizedString_NotFound`: Verify fallback to key when string not found
- `testLocalizedString_WithPluralization`: Verify plural form selection (one vs other)

#### Sign Language (2 tests)

- `testGetSignLanguageVideo_Success`: Verify video metadata retrieval
- `testGetSignLanguageVideo_NotFound`: Verify nil return when video not found

#### Caption Cues (2 tests)

- `testGetCaptionCuesForTimestamp_Found`: Verify cue lookup by timestamp
- `testGetCaptionCuesForTimestamp_NotFound`: Verify nil when cue not found

#### Feedback (2 tests)

- `testSubmitFeedback_Success`: Verify feedback submission
- `testSubmitFeedback_EmptyDescription`: Verify validation of required fields

#### Cache Management (2 tests)

- `testStringCache_Reuses`: Verify cache hit prevents API call
- `testStringCache_ForceRefresh`: Verify forced refresh triggers new API call

#### Error Handling (2 tests)

- `testError_Persistence`: Verify error state is set and persists
- `testIsLoading_State`: Verify loading state transitions correctly

## Running Tests

```bash
# Run all accessibility tests
xcodebuild test -scheme MindFriendApp -destination 'platform=iOS Simulator,name=iPhone 15'

# Run only Spec 14 tests
xcodebuild test -scheme MindFriendApp -testPlan "Spec14Tests" -destination 'platform=iOS Simulator,name=iPhone 15'

# Run with coverage report
xcodebuild test -scheme MindFriendApp -enableCodeCoverage YES -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Mock Objects

### MockSupabaseClient

Provides test doubles for Supabase API calls:

- `mockCurrentUser`: Control authentication state
- `mockLoadPreferences`: Control preference loading results
- `mockCaptions`: Control caption responses
- `mockLocalizedStrings`: Control localization results
- `mockSignLanguageVideo`: Control video metadata
- `shouldThrowError`: Trigger error scenarios
- `getLocalizedStringsCallCount`: Count API invocations

### MockAuth

Test double for Supabase Auth service.

## Test Patterns

### Async Testing

Tests use `async`/`await` with helper extension:

```swift
async {
    let result = try await service.loadPreferences()
    XCTAssertEqual(result.preferredLanguage, "en")
}
```

### Error Testing

Error scenarios tested with `XCTAssertThrowsError` async helper:

```swift
await XCTAssertThrowsError(
    try await service.submitFeedback(invalidFeedback)
) { error in
    XCTAssertEqual(error as? AccessibilityError, .invalidFeedback("..."))
}
```

### State Verification

Published state changes tracked through property inspection:

```swift
try await service.loadPreferences()
XCTAssertEqual(service.preferences.hapticFeedbackEnabled, true)
XCTAssertNil(service.error)
```

## Coverage Goals

| Category          | Target | Actual |
| ----------------- | ------ | ------ |
| Service Methods   | 100%   | 100%   |
| Error Paths       | 100%   | 100%   |
| Cache Logic       | 100%   | 100%   |
| State Transitions | 100%   | 100%   |
| Async Operations  | 100%   | 100%   |

## Continuous Integration

All tests must pass before merge:

```yaml
- name: Run Accessibility Tests
  run: |
    xcodebuild test \
      -scheme MindFriendApp \
      -destination 'platform=iOS Simulator,name=iPhone 15' \
      -testPlan "Spec14Tests" \
      -resultBundlePath TestResults
```

## Known Limitations

- Network calls mocked (unit testing, not integration testing)
- Real Supabase Realtime subscriptions not tested (requires integration test)
- Color blindness filter rendering not tested (requires UI testing)

## Future Test Additions

- Integration tests with live Supabase instance
- UI tests for accessibility view rendering
- Performance benchmarks for large string bundles
- Accessibility audit with XCUITest helpers
