import Foundation
import SwiftUI

// MARK: - Safety Plan View Model

@MainActor
final class SafetyPlanViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var payload: SafetyPlanPayload = .empty
    @Published var settings: SafetyPlanSettings = .default

    @Published var isLoading = false
    @Published var isSaving = false
    @Published var hasExistingPlan = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isCacheStale = false

    // MARK: - Private Properties

    private var originalPayload: SafetyPlanPayload = .empty
    private var planVersion: Int = 0
    private static let pinnedQuickActionKey = "safety_plan.pinned_quick_actions"
    private static let cacheTtl: TimeInterval = 7 * 24 * 60 * 60

    // MARK: - Public Methods

    func loadPlan(container: DependencyContainer) async {
        isLoading = true
        errorMessage = ""
        isCacheStale = false

        do {
            let response: SafetyPlanResponse = try await container.supabaseDataService.fetchSafetyPlan()

            if response.success, let data = response.data {
                payload = data.payload
                originalPayload = data.payload
                settings = SafetyPlanSettings(
                    allowAiReference: data.settings.allowAiReference,
                    pinnedToQuickActions: loadPinnedQuickAction()
                )
                hasExistingPlan = true
                planVersion = data.version
                await cachePlan(payload: data.payload, settings: settings, version: data.version)
            } else {
                // No existing plan
                hasExistingPlan = false
                payload = .empty
                settings = SafetyPlanSettings(
                    allowAiReference: false,
                    pinnedToQuickActions: loadPinnedQuickAction()
                )
                planVersion = 0
                await clearCachedPlan()
            }
        } catch {
            if await loadCachedPlan() {
                hasExistingPlan = true
            } else {
                errorMessage = error.localizedDescription
                showError = true
                hasExistingPlan = false
            }
        }

        isLoading = false
    }

    func updatePlan(container: DependencyContainer, payload: SafetyPlanPayload) async -> Bool {
        isSaving = true
        errorMessage = ""

        do {
            let operation: SafetyPlanOperation = hasExistingPlan ? .update : .create
            let response: SafetyPlanResponse = try await container.supabaseDataService.saveSafetyPlan(
                payload: payload,
                operation: operation
            )

            if response.success, let data = response.data {
                self.payload = data.payload
                originalPayload = data.payload
                self.settings = SafetyPlanSettings(
                    allowAiReference: data.settings.allowAiReference,
                    pinnedToQuickActions: loadPinnedQuickAction()
                )
                hasExistingPlan = true
                isCacheStale = false
                planVersion = data.version
                await cachePlan(payload: data.payload, settings: settings, version: data.version)
                isSaving = false
                return true
            } else if let error = response.error {
                errorMessage = error
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
        return false
    }

    func updateSettings(container: DependencyContainer, allowAiReference: Bool? = nil, pinnedToQuickActions: Bool? = nil) async {
        var newSettings = settings
        if let allowAiReference = allowAiReference {
            newSettings.allowAiReference = allowAiReference
        }
        if let pinnedToQuickActions = pinnedToQuickActions {
            newSettings.pinnedToQuickActions = pinnedToQuickActions
        }

        // Store original settings for potential revert
        let previousSettings = settings

        // Update local immediately for responsiveness
        settings = newSettings

        if let pinnedToQuickActions = pinnedToQuickActions {
            storePinnedQuickAction(pinnedToQuickActions)
        }

        guard allowAiReference != nil else {
            await cachePlan(payload: payload, settings: settings, version: planVersion)
            return
        }

        do {
            let response: SafetyPlanResponse = try await container.supabaseDataService.updateSafetyPlanSettings(settings: newSettings)

            if response.success, let data = response.data {
                settings.allowAiReference = data.settings.allowAiReference
                planVersion = data.version
                await cachePlan(payload: payload, settings: settings, version: data.version)
            } else if let error = response.error {
                // Revert to previous settings on failure
                errorMessage = error
                showError = true
                settings.allowAiReference = previousSettings.allowAiReference
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            // Revert to previous settings on failure
            settings.allowAiReference = previousSettings.allowAiReference
        }
    }

    func deletePlan(container: DependencyContainer) async {
        isSaving = true
        errorMessage = ""

        do {
            let response: SafetyPlanResponse = try await container.supabaseDataService.deleteSafetyPlan()

            if response.success {
                payload = .empty
                settings = .default
                hasExistingPlan = false
                storePinnedQuickAction(false)
                planVersion = 0
                await clearCachedPlan()
            } else if let error = response.error {
                errorMessage = error
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSaving = false
    }

    // MARK: - Local Storage

    private func loadPinnedQuickAction() -> Bool {
        UserDefaults.standard.bool(forKey: Self.pinnedQuickActionKey)
    }

    private func storePinnedQuickAction(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.pinnedQuickActionKey)
    }

    private func cachePlan(payload: SafetyPlanPayload, settings: SafetyPlanSettings, version: Int) async {
        let cached = SafetyPlanCachePayload(
            payload: payload,
            settings: settings,
            version: version,
            cachedAt: Date(),
            expiresAt: Date().addingTimeInterval(Self.cacheTtl)
        )
        try? await OfflineCacheService.shared.cache(cached, key: .safetyPlan)
    }

    private func clearCachedPlan() async {
        await OfflineCacheService.shared.invalidate(key: .safetyPlan)
        isCacheStale = false
    }

    private func loadCachedPlan() async -> Bool {
        guard let cached: SafetyPlanCachePayload = try? await OfflineCacheService.shared.retrieve(
            key: .safetyPlan,
            as: SafetyPlanCachePayload.self
        ) else {
            return false
        }

        payload = cached.payload
        originalPayload = cached.payload
        settings = SafetyPlanSettings(
            allowAiReference: cached.settings.allowAiReference,
            pinnedToQuickActions: loadPinnedQuickAction()
        )
        hasExistingPlan = true
        planVersion = cached.version
        isCacheStale = cached.isExpired
        return true
    }

    // MARK: - Computed Properties

    var hasChanges: Bool {
        payload != originalPayload
    }

    var isComplete: Bool {
        // Check if plan has minimum required sections
        !payload.warningSigns.isEmpty ||
        !payload.coping.isEmpty ||
        !payload.contacts.isEmpty ||
        !payload.environmentSteps.isEmpty
    }
}

// MARK: - Safety Plan Wizard State

@MainActor
final class SafetyPlanWizardState: ObservableObject {
    @Published var currentStep: SafetyPlanWizardStep = .warningSigns
    @Published var payload: SafetyPlanPayload = .empty

    var progress: Double {
        Double(currentStep.rawValue + 1) / Double(SafetyPlanWizardStep.allCases.count)
    }

    var isFirstStep: Bool {
        currentStep == .warningSigns
    }

    var isLastStep: Bool {
        currentStep == .review
    }

    var canProceed: Bool {
        switch currentStep {
        case .warningSigns:
            return !payload.warningSigns.isEmpty
        case .coping:
            return !payload.coping.isEmpty
        case .contacts:
            return payload.contacts.count <= 3
        case .resources:
            return true
        case .environment:
            return !payload.environmentSteps.isEmpty
        case .anchors:
            return true // Optional
        case .review:
            return true
        }
    }

    func goToNextStep() {
        guard let nextStep = SafetyPlanWizardStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextStep
    }

    func goToPreviousStep() {
        guard let prevStep = SafetyPlanWizardStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = prevStep
    }

    func goToStep(_ step: SafetyPlanWizardStep) {
        currentStep = step
    }
}

// MARK: - Safety Plan Analytics

extension SafetyPlanViewModel {
    func trackPlanCreated() {
        // Analytics.track(.safety_plan_created, properties: [
        //     "version": 1,
        //     "sections_completed": countCompletedSections()
        // ])
    }

    func trackPlanOpened(source: String) {
        // Analytics.track(.safety_plan_opened, properties: ["source": source])
    }

    func trackCrisisViewOpened() {
        // Analytics.track(.safety_plan_crisis_opened)
    }

    func trackCondensedViewOpened() {
        // Analytics.track(.safety_plan_condensed_viewed)
    }

    func trackContactTapped(contactId: String, method: String) {
        // Analytics.track(.safety_plan_contact_tapped, properties: [
        //     "contact_id": contactId,
        //     "method": method
        // ])
    }

    func trackResourceTapped(resourceId: String, type: String) {
        // Analytics.track(.safety_plan_resource_tapped, properties: [
        //     "resource_id": resourceId,
        //     "type": type
        // ])
    }

    private func countCompletedSections() -> Int {
        var count = 0
        if !payload.warningSigns.isEmpty { count += 1 }
        if !payload.coping.isEmpty { count += 1 }
        if !payload.contacts.isEmpty { count += 1 }
        if !payload.resources.isEmpty { count += 1 }
        if !payload.environmentSteps.isEmpty { count += 1 }
        if !payload.anchors.isEmpty { count += 1 }
        return count
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension SafetyPlanViewModel {
    static var preview: SafetyPlanViewModel {
        let vm = SafetyPlanViewModel()
        vm.payload = SafetyPlanPayload(
            warningSigns: [
                SafetyPlanItem(text: "Withdrawing from others"),
                SafetyPlanItem(text: "Sleep quality decreases")
            ],
            coping: [
                CopingStrategy(type: .exercise, label: "Box Breathing", duration: 2, category: .breathing, isFavorite: true)
            ],
            contacts: [
                TrustedContact(name: "Mom", phone: "+1234567890", relationship: .family, isPrimary: true)
            ],
            resources: [
                ProfessionalResource(type: .hotline, name: "988", phone: "988")
            ]
        )
        vm.settings = SafetyPlanSettings(allowAiReference: true, pinnedToQuickActions: true)
        vm.hasExistingPlan = true
        return vm
    }
}
#endif
