// SOSCoordinator.swift
// MindFriend - SOS Panic Button State Machine

import Foundation
import SwiftUI
import UIKit
import Supabase

/// Manages the SOS panic button intervention flow
@MainActor
final class SOSCoordinator: ObservableObject {
    // MARK: - Published State

    @Published private(set) var phase: SOSPhase = .ready
    @Published private(set) var settings: SOSSettings?
    @Published private(set) var currentEvent: SOSEvent?
    @Published private(set) var isLoading = false

    // MARK: - Dependencies

    private let supabase: SupabaseClient
    private weak var familyService: FamilyService?
    private weak var dataService: SupabaseDataService?

    // MARK: - Private State

    private var interventionTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var breathingTimer: Timer?
    private var startTime: Date?

    // Offline queue
    private var offlineQueue: [OfflineSOSEvent] = []
    private let offlineQueueKey = "sos_offline_queue"

    // MARK: - Computed Properties

    var isActive: Bool {
        phase.isActive
    }

    // MARK: - Initialization

    init(supabase: SupabaseClient, familyService: FamilyService? = nil, dataService: SupabaseDataService? = nil) {
        self.supabase = supabase
        self.familyService = familyService
        self.dataService = dataService
        loadOfflineQueue()
    }

    // MARK: - Public Methods

    /// Load user's SOS settings
    func loadSettings() async {
        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            // Use in-memory defaults for unauthenticated users (dev/preview mode)
            settings = SOSSettings.defaults(userId: "preview")
            return
        }

        do {
            let fetchedSettings: [SOSSettings] = try await supabase
                .from("sos_settings")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            if let existing = fetchedSettings.first {
                settings = existing
            } else {
                // Create default settings
                let defaults = SOSSettings.defaults(userId: userId)
                try await supabase
                    .from("sos_settings")
                    .insert(defaults)
                    .execute()
                settings = defaults
            }
        } catch {
            // Use defaults on error
            settings = SOSSettings.defaults(userId: userId)
            print("Failed to load SOS settings: \(error)")
        }
    }

    /// Start the SOS intervention
    func startSOS(from location: String? = "home") async {
        // Guard against rapid double-taps and concurrent starts
        guard phase == .ready, !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        // Get userId (use "preview" for unauthenticated users)
        let userId = supabase.auth.currentUser?.id.uuidString ?? "preview"

        // Create event
        var event = SOSEvent.create(userId: userId, triggerLocation: location)
        currentEvent = event
        startTime = Date()

        // Trigger start haptic
        triggerHaptic(.sosStart)

        // Check if auto-notify is enabled
        if settings?.autoNotifyEnabled == true && settings?.hasEmergencyContact == true {
            // Start countdown before sending family alert
            let countdown = settings?.countdownSeconds ?? 3
            phase = .countdown(remaining: countdown)
            event.familyAlertSent = false
            currentEvent = event

            countdownTask = Task {
                for remaining in stride(from: countdown, through: 1, by: -1) {
                    await MainActor.run {
                        phase = .countdown(remaining: remaining)
                        triggerHaptic(.countdownTick)
                    }
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        return // Cancelled
                    }
                }

                // Send family alert
                await sendFamilyAlert()
            }
        } else {
            // Skip countdown, go directly to breathing
            await proceedToBreathing()
        }
    }

    /// Cancel the countdown and skip family notification
    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil

        Task {
            await proceedToBreathing()
        }
    }

    /// Proceed to breathing phase
    func proceedToBreathing() async {
        // Use current settings or fall back to defaults to ensure SOS flow always continues
        let currentSettings = settings ?? SOSSettings.defaults(userId: supabase.auth.currentUser?.id.uuidString ?? "preview")

        // Update settings if we had to use defaults (so other phases have access)
        if settings == nil {
            settings = currentSettings
        }

        let pattern = currentSettings.preferredBreathingPattern
        let totalCycles = pattern.defaultCycles

        phase = .breathing(cycleIndex: 0, totalCycles: totalCycles, phaseIndex: 0)
        recordPhaseCompletion("started")
    }

    /// Advance to next breath phase
    func advanceBreathing() {
        guard case let .breathing(cycleIndex, totalCycles, phaseIndex) = phase,
              let settings = settings else { return }

        let pattern = settings.preferredBreathingPattern
        let phases = pattern.phases

        let nextPhaseIndex = phaseIndex + 1

        if nextPhaseIndex >= phases.count {
            // Completed one cycle
            let nextCycle = cycleIndex + 1
            if nextCycle >= totalCycles {
                // All cycles complete
                completeBreathing()
            } else {
                phase = .breathing(cycleIndex: nextCycle, totalCycles: totalCycles, phaseIndex: 0)
            }
        } else {
            phase = .breathing(cycleIndex: cycleIndex, totalCycles: totalCycles, phaseIndex: nextPhaseIndex)
        }
    }

    /// Complete breathing phase
    func completeBreathing() {
        triggerHaptic(.phaseComplete)
        recordPhaseCompletion("breathing")

        // Always proceed - default to resources if settings unavailable
        if settings?.includeGrounding == true {
            proceedToGrounding()
        } else {
            proceedToResources()
        }
    }

    /// Proceed to grounding phase
    func proceedToGrounding() {
        phase = .grounding(sense: .see) // Start with "see" (5 things)
    }

    /// Advance to next grounding sense
    func advanceGrounding() {
        guard case let .grounding(currentSense) = phase else { return }

        triggerHaptic(.groundingTap)

        if let nextSense = currentSense.next {
            phase = .grounding(sense: nextSense)
        } else {
            completeGrounding()
        }
    }

    /// Complete grounding phase
    func completeGrounding() {
        triggerHaptic(.phaseComplete)
        recordPhaseCompletion("grounding")
        proceedToResources()
    }

    /// Proceed to resources phase
    func proceedToResources() {
        phase = .resources
    }

    /// Proceed to check-in phase
    func proceedToCheckIn() {
        recordPhaseCompletion("resources")
        phase = .checkIn
    }

    /// Skip directly to resources (from any phase)
    func skipToResources() {
        cancelAllTasks()
        phase = .resources
    }

    /// Complete the intervention with rating
    func completeCheckIn(helpfulnessRating: Int, moodAfter: Int) async {
        let rating = helpfulnessRating  // Alias for internal use
        guard var event = currentEvent else { return }

        let endTime = Date()
        event.endedAt = endTime
        event.moodAfter = moodAfter
        event.helpfulnessRating = rating
        event.wasInterrupted = false
        event.interventionDurationSeconds = Int(endTime.timeIntervalSince(startTime ?? endTime))

        currentEvent = event
        recordPhaseCompletion("checkin")

        triggerHaptic(.complete)
        phase = .complete

        // Save event
        await saveEvent(event)

        // Sync any queued events
        await syncOfflineEvents()
    }

    /// Record mood before intervention
    func recordMoodBefore(_ mood: Int) {
        currentEvent?.moodBefore = mood
    }

    /// Cancel the SOS intervention
    func cancelSOS() async {
        guard var event = currentEvent else { return }

        cancelAllTasks()

        let endTime = Date()
        event.endedAt = endTime
        event.wasInterrupted = true
        event.interventionDurationSeconds = Int(endTime.timeIntervalSince(startTime ?? endTime))

        currentEvent = event
        phase = .cancelled

        // Save interrupted event
        await saveEvent(event)
    }

    /// Reset to ready state
    func reset() {
        cancelAllTasks()
        phase = .ready
        currentEvent = nil
        startTime = nil
    }

    /// Exit to chat (navigation handled externally)
    func exitToChat() {
        cancelAllTasks()
        phase = .complete
    }

    /// Update full settings object
    func updateSettings(_ newSettings: SOSSettings) async throws {
        do {
            try await supabase
                .from("sos_settings")
                .upsert(newSettings)
                .execute()
            self.settings = newSettings
        } catch {
            print("Failed to update SOS settings: \(error)")
            throw error
        }
    }

    /// Start test mode (no logging, no notifications)
    func startTestMode() {
        // Reset state and start without creating a persistent event
        cancelAllTasks()
        currentEvent = nil
        startTime = Date()

        // Go directly to breathing with test settings
        if let settings = settings {
            let pattern = settings.preferredBreathingPattern
            let totalCycles = max(1, pattern.defaultCycles / 2) // Shorter for testing
            phase = .breathing(cycleIndex: 0, totalCycles: totalCycles, phaseIndex: 0)
        } else {
            phase = .breathing(cycleIndex: 0, totalCycles: 2, phaseIndex: 0)
        }
    }

    /// Fetch recent SOS events for history
    func fetchRecentEvents(limit: Int = 20) async -> [SOSEvent] {
        guard let userId = supabase.auth.currentUser?.id.uuidString else { return [] }

        do {
            let events: [SOSEvent] = try await supabase
                .from("sos_events")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return events
        } catch {
            print("Failed to fetch SOS events: \(error)")
            return []
        }
    }

    // MARK: - Haptic Feedback

    /// Trigger haptic feedback
    func triggerHaptic(_ type: SOSHapticType) {
        let generator: UIImpactFeedbackGenerator
        switch type {
        case .sosStart:
            generator = UIImpactFeedbackGenerator(style: .heavy)
        case .countdownTick:
            generator = UIImpactFeedbackGenerator(style: .rigid)
        case .inhale, .phaseStart:
            generator = UIImpactFeedbackGenerator(style: .medium)
        case .hold:
            generator = UIImpactFeedbackGenerator(style: .soft)
        case .exhale:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .phaseComplete, .complete, .success:
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.success)
            return
        case .groundingTap:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .gentleEnd:
            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.warning)
            return
        }
        generator.impactOccurred()
    }

    /// Get the appropriate haptic type for current breathing phase
    func hapticForBreathingPhase(_ phaseName: String) -> SOSHapticType {
        switch phaseName {
        case "inhale": return .inhale
        case "hold": return .hold
        case "exhale": return .exhale
        default: return .inhale
        }
    }

    // MARK: - Private Methods

    private func recordPhaseCompletion(_ phaseName: String) {
        currentEvent?.completedPhases.append(phaseName)
    }

    private func sendFamilyAlert() async {
        guard var event = currentEvent,
              let settings = settings,
              settings.autoNotifyEnabled,
              let phone = settings.emergencyContactPhone,
              isValidPhoneNumber(phone) else {
            // If phone validation fails, skip alert and proceed to breathing
            await proceedToBreathing()
            return
        }

        // Mark alert as sent
        event.familyAlertSent = true
        currentEvent = event

        // Sanitize phone number for SMS URL (remove non-numeric characters except +)
        let sanitizedPhone = phone.filter { $0.isNumber || $0 == "+" }

        // Open SMS app with pre-filled message
        let message = "I'm using MindFriend's calming exercises. Just wanted to let you know."
        if let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "sms:\(sanitizedPhone)?body=\(encodedMessage)") {
            await UIApplication.shared.open(url)
            event.contactNotified = true
            currentEvent = event
        }

        // Continue to breathing
        await proceedToBreathing()
    }

    /// Validate phone number format (basic validation)
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        // Strip non-numeric characters except +
        let stripped = phone.filter { $0.isNumber || $0 == "+" }
        // Must have at least 7 digits (minimum for local numbers)
        let digitCount = stripped.filter { $0.isNumber }.count
        return digitCount >= 7 && digitCount <= 15
    }

    private func cancelAllTasks() {
        interventionTask?.cancel()
        interventionTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        breathingTimer?.invalidate()
        breathingTimer = nil
    }

    // MARK: - Persistence

    private func saveEvent(_ event: SOSEvent) async {
        // Don't try to save preview events to database
        guard event.userId != "preview" else {
            print("SOS event not saved (preview mode)")
            return
        }

        do {
            try await supabase
                .from("sos_events")
                .upsert(event)
                .execute()
        } catch {
            // Queue for offline sync
            queueEventOffline(event)
            print("Failed to save SOS event, queued offline: \(error)")
        }
    }

    private func queueEventOffline(_ event: SOSEvent) {
        let offlineEvent = OfflineSOSEvent(event: event, queuedAt: Date())
        offlineQueue.append(offlineEvent)
        saveOfflineQueue()
    }

    private func saveOfflineQueue() {
        guard let data = try? JSONEncoder().encode(offlineQueue) else { return }
        UserDefaults.standard.set(data, forKey: offlineQueueKey)
    }

    private func loadOfflineQueue() {
        guard let data = UserDefaults.standard.data(forKey: offlineQueueKey),
              let queue = try? JSONDecoder().decode([OfflineSOSEvent].self, from: data) else { return }
        offlineQueue = queue
    }

    /// Sync queued offline events when connection is restored
    func syncOfflineEvents() async {
        guard !offlineQueue.isEmpty else { return }

        var synced: [String] = []

        for offlineEvent in offlineQueue {
            do {
                try await supabase
                    .from("sos_events")
                    .upsert(offlineEvent.event)
                    .execute()
                synced.append(offlineEvent.id)
            } catch {
                print("Failed to sync offline SOS event: \(error)")
            }
        }

        // Remove synced events
        offlineQueue.removeAll { synced.contains($0.id) }
        saveOfflineQueue()
    }

    // MARK: - Settings Updates

    /// Generic helper for updating a single settings property
    private func updateSettingsProperty(_ update: (inout SOSSettings) -> Void) async {
        guard var updatedSettings = settings else { return }
        update(&updatedSettings)
        updatedSettings.updatedAt = Date()

        do {
            try await supabase
                .from("sos_settings")
                .update(updatedSettings)
                .eq("user_id", value: updatedSettings.userId)
                .execute()
            self.settings = updatedSettings
        } catch {
            print("Failed to update SOS settings: \(error)")
        }
    }

    /// Update auto-notify setting
    func updateAutoNotify(_ enabled: Bool) async {
        await updateSettingsProperty { $0.autoNotifyEnabled = enabled }
    }

    /// Update emergency contact
    func updateEmergencyContact(name: String?, phone: String?) async {
        await updateSettingsProperty {
            $0.emergencyContactName = name
            $0.emergencyContactPhone = phone
        }
    }

    /// Update breathing pattern preference
    func updateBreathingPattern(_ pattern: BreathingPattern) async {
        await updateSettingsProperty { $0.preferredBreathingPattern = pattern }
    }

    /// Update grounding preference
    func updateIncludeGrounding(_ include: Bool) async {
        await updateSettingsProperty { $0.includeGrounding = include }
    }
}
