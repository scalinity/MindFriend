import SwiftUI
import SentrySwiftUI
import Sentry

// MARK: - Automatic View Tracing

/// A view modifier that automatically handles Sentry tracing with TTFD (Time to Full Display).
/// Wraps the view in a SentryTracedView and automatically reports when loading completes.
///
/// Usage:
/// ```swift
/// MyView()
///     .traced("Home", isLoading: $isLoading) {
///         await loadData()
///     }
/// ```
struct TracedViewModifier<T>: ViewModifier {
    let name: String
    @Binding var isLoading: Bool
    let loadAction: () async -> T

    @State private var hasReportedDisplay = false

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .task {
                isLoading = true
                _ = await loadAction()
                isLoading = false
                reportDisplayIfNeeded()
            }
            .onChange(of: isLoading) { _, newValue in
                if !newValue {
                    reportDisplayIfNeeded()
                }
            }
    }

    private func reportDisplayIfNeeded() {
        guard !hasReportedDisplay, CrashReporter.shared.isEnabled else { return }
        hasReportedDisplay = true
        CrashReporter.shared.reportFullyDisplayed()
    }
}

/// A simpler view modifier for views that just need tracing without loading state binding.
/// Automatically reports display after the async task completes.
///
/// Usage:
/// ```swift
/// MyView()
///     .tracedTask("ChatList") {
///         await loadConversations()
///     }
/// ```
struct TracedTaskModifier: ViewModifier {
    let name: String
    let action: () async -> Void

    @State private var hasReportedDisplay = false

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .task {
                await action()
                if !hasReportedDisplay, CrashReporter.shared.isEnabled {
                    hasReportedDisplay = true
                    CrashReporter.shared.reportFullyDisplayed()
                }
            }
    }
}

/// A view modifier for multiple async data loads that reports when ALL complete.
///
/// Usage:
/// ```swift
/// MyView()
///     .tracedTasks("Home", tasks: [
///         { await loadQuest() },
///         { await loadMood() },
///         { await loadBuddy() }
///     ])
/// ```
struct TracedMultiTaskModifier: ViewModifier {
    let name: String
    let tasks: [() async -> Void]

    @State private var hasReportedDisplay = false

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .task {
                // Run all tasks concurrently
                await withTaskGroup(of: Void.self) { group in
                    for task in tasks {
                        group.addTask { await task() }
                    }
                }
                // Report after ALL tasks complete
                if !hasReportedDisplay, CrashReporter.shared.isEnabled {
                    hasReportedDisplay = true
                    CrashReporter.shared.reportFullyDisplayed()
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Add Sentry tracing with automatic TTFD reporting when loading state changes.
    ///
    /// - Parameters:
    ///   - name: The trace name (e.g., "Home", "Chat")
    ///   - isLoading: Binding to loading state - reports display when this becomes false
    ///   - action: Async action to perform on appear
    func traced<T>(
        _ name: String,
        isLoading: Binding<Bool>,
        action: @escaping () async -> T
    ) -> some View {
        modifier(TracedViewModifier(name: name, isLoading: isLoading, loadAction: action))
    }

    /// Add Sentry tracing with automatic TTFD reporting after task completes.
    ///
    /// - Parameters:
    ///   - name: The trace name (e.g., "ChatList", "ExerciseLibrary")
    ///   - action: Async action to perform on appear
    func tracedTask(
        _ name: String,
        action: @escaping () async -> Void
    ) -> some View {
        modifier(TracedTaskModifier(name: name, action: action))
    }

    /// Add Sentry tracing with automatic TTFD reporting after ALL tasks complete.
    ///
    /// - Parameters:
    ///   - name: The trace name
    ///   - tasks: Array of async tasks - reports display when all complete
    func tracedTasks(
        _ name: String,
        tasks: [() async -> Void]
    ) -> some View {
        modifier(TracedMultiTaskModifier(name: name, tasks: tasks))
    }
}

// MARK: - Traced Data Loading

/// A property wrapper that automatically traces data loading operations.
/// Reports fully displayed when the value is set.
///
/// **Thread Safety**: This property wrapper is annotated with @MainActor and must only
/// be used from the main thread (standard for SwiftUI views). The @State properties
/// are inherently thread-safe, and @MainActor ensures all access happens serially
/// on the main thread, preventing race conditions in the check-then-set pattern.
///
/// Usage:
/// ```swift
/// @TracedState("quests") var quests: [Quest] = []
/// ```
@MainActor
@propertyWrapper
struct TracedState<Value>: DynamicProperty {
    private let traceName: String
    @State private var value: Value
    @State private var hasReportedDisplay = false

    init(wrappedValue: Value, _ traceName: String) {
        self.traceName = traceName
        self._value = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { value }
        nonmutating set {
            value = newValue
            if !hasReportedDisplay {
                hasReportedDisplay = true
                CrashReporter.shared.reportFullyDisplayed()
                CrashReporter.shared.logDebug("TTFD: \(traceName) loaded")
            }
        }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { value },
            set: { newValue in
                value = newValue
                if !hasReportedDisplay {
                    hasReportedDisplay = true
                    CrashReporter.shared.reportFullyDisplayed()
                }
            }
        )
    }
}

// MARK: - Async Operation Tracing

/// Execute an async operation with automatic Sentry span tracing.
///
/// Usage:
/// ```swift
/// let users = try await traced("fetch_users", operation: "db.query") {
///     try await supabase.from("users").select().execute().value
/// }
/// ```
func traced<T>(
    _ description: String,
    operation: String,
    block: () async throws -> T
) async rethrows -> T {
    let span = CrashReporter.shared.startSpan(operation: operation, description: description)

    do {
        let result = try await block()
        span?.finish(status: .ok)
        return result
    } catch {
        span?.setData(value: error.localizedDescription, key: "error")
        span?.finish(status: .internalError)
        throw error
    }
}

/// Execute an async operation with automatic Sentry transaction tracing.
/// Use this for top-level operations that aren't part of an existing transaction.
///
/// Usage:
/// ```swift
/// let response = try await tracedTransaction("Send Message", operation: "chat.send") {
///     try await chatService.sendMessage(...)
/// }
/// ```
func tracedTransaction<T>(
    _ name: String,
    operation: String,
    data: [String: Any]? = nil,
    block: () async throws -> T
) async rethrows -> T {
    let transaction = CrashReporter.shared.startTransaction(
        name: name,
        operation: operation,
        bindToScope: true
    )

    if let data = data {
        for (key, value) in data {
            transaction?.setData(value: value, key: key)
        }
    }

    do {
        let result = try await block()
        transaction?.finish(status: .ok)
        return result
    } catch {
        transaction?.setData(value: error.localizedDescription, key: "error")
        transaction?.finish(status: .internalError)
        throw error
    }
}
