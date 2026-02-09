---
description: "Instructions for iOS Swift/SwiftUI code"
applyTo: "apps/ios/**/*.swift"
---

# iOS-Specific Guidelines

## SwiftUI Best Practices

### View Composition
- Break down complex views into smaller, reusable components
- Use `@ViewBuilder` for conditional view composition
- Prefer composition over inheritance
- Keep views under 100 lines; extract subviews when larger

### State Management
```swift
// Prefer @Observable for iOS 17+
@Observable
final class MyViewModel {
    var data: [Item] = []
    var isLoading = false
}

// Use in view
struct MyView: View {
    @State private var viewModel = MyViewModel()
    
    var body: some View {
        // View code
    }
}
```

### Async/Await Pattern
```swift
// Use Task for async operations in views
.task {
    await viewModel.loadData()
}

// Handle errors gracefully
func loadData() async {
    do {
        let data = try await supabase.from("table").select()
        self.data = data.value
    } catch {
        logger.error("Load failed: \(error)")
        errorMessage = "Unable to load data"
    }
}
```

## Feature Module Pattern

Each feature should follow this structure:
```
Features/FeatureName/
  FeatureNameView.swift       # Main view
  FeatureNameViewModel.swift  # Business logic
  Components/                 # Feature-specific components
    SubView1.swift
    SubView2.swift
```

## Testing Guidelines

### ViewModel Tests
```swift
@Test func testLoadData() async throws {
    let viewModel = MyViewModel(dependency: mockDependency)
    await viewModel.loadData()
    #expect(viewModel.data.isEmpty == false)
}
```

### UI Tests
- Test critical user flows (auth, subscription, crisis)
- Use accessibility identifiers for test targets
- Mock Supabase responses for deterministic tests

## Accessibility

### VoiceOver Support
```swift
Button(action: save) {
    Image(systemName: "checkmark")
}
.accessibilityLabel("Save changes")
.accessibilityHint("Saves your current progress")
```

### Dynamic Type
- Use system fonts (`.body`, `.headline`, etc.)
- Test with largest accessibility sizes
- Avoid fixed heights for text containers

### Color Contrast
- Use semantic colors from asset catalog
- Test in both light and dark modes
- Ensure minimum 4.5:1 contrast ratio for text

## Supabase Swift SDK Patterns

### Authentication
```swift
// Sign in with Apple
let session = try await supabase.auth.signInWithIdToken(
    credentials: .init(
        provider: .apple,
        idToken: appleToken
    )
)

// Get current user
let user = try await supabase.auth.user
```

### Database Queries
```swift
// Fetch with filters
let quests: [Quest] = try await supabase
    .from("quests")
    .select()
    .eq("user_id", userId)
    .order("created_at", ascending: false)
    .execute()
    .value

// Insert
try await supabase
    .from("moods")
    .insert([
        "user_id": userId,
        "rating": rating,
        "notes": notes
    ])
    .execute()

// Update
try await supabase
    .from("quests")
    .update(["completed": true])
    .eq("id", questId)
    .execute()
```

### Edge Functions
```swift
struct ChatRequest: Codable {
    let conversationId: String
    let content: String
}

let response = try await supabase.functions.invoke(
    "chat",
    options: FunctionInvokeOptions(
        body: ChatRequest(
            conversationId: id,
            content: message
        )
    )
)
```

### Realtime Subscriptions
```swift
let channel = supabase.channel("circle:\(circleId)")
    .onPostgresChange(
        event: .insert,
        table: "circle_posts"
    ) { payload in
        if let post = try? payload.decodeRecord(as: CirclePost.self) {
            self.posts.append(post)
        }
    }

await channel.subscribe()

// Don't forget to unsubscribe
await channel.unsubscribe()
```

## Error Handling

### User-Friendly Messages
```swift
enum AppError: LocalizedError {
    case networkError
    case authenticationFailed
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Unable to connect. Please check your internet connection."
        case .authenticationFailed:
            return "Sign in failed. Please try again."
        case .quotaExceeded:
            return "You've reached your daily limit. Upgrade to continue."
        }
    }
}
```

### Logging
```swift
// Use logger for debugging
logger.debug("User initiated action: \(action)")
logger.info("Data loaded successfully: \(count) items")
logger.error("Failed to save: \(error.localizedDescription)")

// Use crash reporter for errors
crashReporter.recordError(error, userInfo: ["context": "saving_mood"])
```

## Performance

### Image Loading
- Use `AsyncImage` for remote images
- Implement caching for frequently accessed images
- Resize images appropriately before display

### List Performance
```swift
// Use lazy loading for large lists
List {
    ForEach(items) { item in
        ItemRow(item: item)
    }
}
.onAppear {
    if items.count > 20 {
        // Implement pagination
    }
}
```

### Background Processing
```swift
// Use background tasks for heavy operations
Task.detached {
    let result = await heavyComputation()
    await MainActor.run {
        self.updateUI(with: result)
    }
}
```

## Common Pitfalls to Avoid

- ❌ Don't use `@EnvironmentObject` excessively; prefer explicit dependencies
- ❌ Don't perform network calls in view body or computed properties
- ❌ Don't ignore Task cancellation in async operations
- ❌ Don't store secrets in UserDefaults (use Keychain)
- ❌ Don't use force unwrapping (`!`) without clear justification
- ❌ Don't block the main thread with synchronous operations

## StoreKit 2 Integration

### Product Loading
```swift
let products = try await Product.products(for: [productID])
guard let product = products.first else { return }

// Display product info
let price = product.displayPrice
let description = product.description
```

### Purchase Flow
```swift
let result = try await product.purchase()

switch result {
case .success(let verification):
    switch verification {
    case .verified(let transaction):
        // Send to backend for verification
        await verifyPurchase(transaction.originalID)
        await transaction.finish()
    case .unverified:
        // Handle unverified transaction
        break
    }
case .userCancelled:
    // User cancelled
    break
case .pending:
    // Purchase pending
    break
@unknown default:
    break
}
```

### Restore Purchases
```swift
for await result in Transaction.currentEntitlements {
    if case .verified(let transaction) = result {
        await verifyPurchase(transaction.originalID)
    }
}
```

## Push Notifications

### APNs Registration
```swift
// Request permission
let settings = await UNUserNotificationCenter.current()
    .notificationSettings()

if settings.authorizationStatus == .notDetermined {
    try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])
}

// Register for remote notifications
await UIApplication.shared.registerForRemoteNotifications()
```

### Handle Notifications
```swift
// In AppDelegate or Scene
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    // Send to backend via Edge Function
    Task {
        await registerAPNsToken(token)
    }
}
```

## Remember

- **Always** go through Supabase for backend operations
- **Never** call external APIs directly (use Edge Functions)
- **Test** with VoiceOver and Dynamic Type enabled
- **Document** complex business logic
- **Log** errors appropriately for debugging
