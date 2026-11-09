import SwiftUI
import Supabase

// MARK: - Onboarding Container

/// Birth year is self-reported; the boundary-year confirmation avoids inventing a birthday.
struct OnboardingConsent: Equatable {
    static let version = "2026-11-06"
    static func referenceYear(at date: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.year, from: date)
    }
    var birthYear: Int?
    var confirmsThirteen = false
    var acceptsTerms = false

    func isEligible(currentYear: Int) -> Bool {
        guard let birthYear, (1900...currentYear).contains(birthYear) else { return false }
        return currentYear - birthYear >= 13 && confirmsThirteen && acceptsTerms
    }
}

struct OnboardingFlow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var consent = OnboardingConsent()
    @State private var showWelcome = false
    @State private var isCompleting = false
    @State private var errorMessage: String?
    @State private var showDeleteAccount = false
    private var currentYear: Int { OnboardingConsent.referenceYear() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Group {
                    if showWelcome {
                        Text("What would be useful right now?").font(.largeTitle.bold())
                        Text("We can talk it through or try one small thing. You can explore at your own pace.")
                        Button("Talk about something") { completeOnboarding(destination: .chat) }
                            .buttonStyle(.supportPrimary)
                        Button("Try a short practice") { completeOnboarding(destination: .home, practice: true) }
                            .buttonStyle(.supportSecondary)
                        Button("Explore first") { completeOnboarding(destination: SupportShellTab.explore.mainTab) }
                            .buttonStyle(.bordered)
                        Button("Review consent") { showWelcome = false }
                    } else {
                        Text("Welcome to MindFriend").font(.largeTitle.bold())
                        Text("Not a medical provider. Not for emergencies.").font(.headline)
                        Text("MindFriend offers nonclinical support and practical self-care. It is for people aged 13 and older.")
                        Picker("Birth year", selection: $consent.birthYear) {
                            Text("Select your birth year").tag(nil as Int?)
                            ForEach(Array((1900...currentYear).reversed()), id: \.self) { year in
                                Text(String(year)).tag(Optional(year))
                            }
                        }
                        .pickerStyle(.menu)
                        Toggle("My thirteenth birthday has already occurred", isOn: $consent.confirmsThirteen)
                        Toggle("I agree to the Terms of Service and Privacy Policy", isOn: $consent.acceptsTerms)
                        Link("Terms of Service", destination: AppURLs.termsOfUse)
                        Link("Privacy Policy", destination: AppURLs.privacyPolicy)
                        if let year = consent.birthYear, currentYear - year < 13 {
                            Text("MindFriend is available from age 13. You can still open support and crisis resources below.")
                        }
                        Button("Continue") { showWelcome = true }
                            .buttonStyle(.supportPrimary)
                            .disabled(!consent.isEligible(currentYear: currentYear))
                    }
                    }
                    .disabled(isCompleting)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).accessibilityLabel("Setup not saved. " + errorMessage)
                    }
                    if isCompleting { ProgressView("Saving your choices…") }
                    Button("Support and crisis resources") { appState.showCrisisResources = true }
                    Button("Delete account", role: .destructive) { showDeleteAccount = true }
                        .disabled(isCompleting)
                    Button("Sign out") {
                        Task {
                            do { try await container.supabaseAuthService.signOut(); appState.setUnauthenticated() }
                            catch { errorMessage = "Could not sign out. Please try again." }
                        }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
            }
            .navigationTitle("Welcome")
            .sheet(isPresented: $appState.showCrisisResources) { CrisisResourcesView() }
            .confirmationDialog("Delete this account and its account data?", isPresented: $showDeleteAccount, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) { }
            }
            .onChange(of: container.supabaseAuthService.userId) { _, _ in
                consent = OnboardingConsent()
                showWelcome = false
                errorMessage = nil
            }
        }
    }

    private func completeOnboarding(destination: MainTab, practice: Bool = false) {
        guard !isCompleting, consent.isEligible(currentYear: currentYear), let birthYear = consent.birthYear,
              let owner = container.supabaseAuthService.userId else { return }
        let submittedConsent = consent
        isCompleting = true
        errorMessage = nil
        Task {
            defer { isCompleting = false }
            do {
                try await container.supabaseDataService.completeOnboarding(
                    expectedOwner: owner, birthYear: birthYear, confirmsThirteen: submittedConsent.confirmsThirteen,
                    acceptsTerms: submittedConsent.acceptsTerms)
                let profile = try await container.supabaseAuthService.fetchProfile()
                guard container.supabaseAuthService.userId == owner, profile.id == owner,
                      !profile.needsOnboarding else { throw CancellationError() }
                appState.completeOnboarding(user: profile)
                container.supabaseAuthService.identifyCurrentUserAfterOnboarding(profile: profile)
                appState.selectedTab = destination
                if destination == .chat { appState.shouldOpenNewChat = true }
                if practice { DeepLinkRouter.shared.handleRoute(.exerciseLibrary, appState: appState) }
            } catch is CancellationError {
                return
            } catch let error as PostgrestError where error.code == "42501" {
                return
            } catch let error as PostgrestError where error.code == "22023" {
                guard container.supabaseAuthService.userId == owner else { return }
                errorMessage = "Your birth year and consent could not be accepted. Review your choices before trying again."
                showWelcome = false
            } catch {
                guard container.supabaseAuthService.userId == owner else { return }
                errorMessage = "Your setup has not been confirmed. The service may be unavailable. Try again when connected; your choices are still here."
            }
        }
    }
    private func deleteAccount() {
        guard let owner = container.supabaseAuthService.userId else { return }
        isCompleting = true
        Task {
            defer { isCompleting = false }
            do {
                guard container.supabaseAuthService.userId == owner else { return }
                try await container.supabaseAuthService.deleteAccount(expectedOwner: owner)
                if container.supabaseAuthService.userId == nil { appState.setUnauthenticated() }
            } catch {
                guard container.supabaseAuthService.userId == owner else { return }
                errorMessage = "Your account was not deleted. Please try again when connected."
            }
        }
    }

}
