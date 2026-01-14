import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.currentUser?.displayName ?? "User")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)

                                Text("@\(appState.currentUser?.handle ?? "")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if appState.entitlements.tier == .premium {
                                    Label("Premium", systemImage: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }

                            Spacer()

                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Stats
                Section("Stats") {
                    HStack {
                        StatItem(value: "\(appState.currentUser?.stats.currentStreakDays ?? 0)", label: "Streak")
                        Divider()
                        StatItem(value: "\(appState.currentUser?.stats.totalQuestsCompleted ?? 0)", label: "Quests")
                        Divider()
                        StatItem(value: "\(appState.currentUser?.badges.count ?? 0)", label: "Badges")
                    }
                    .padding(.vertical, 8)
                }

                // Settings
                Section("Settings") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }

                    NavigationLink {
                        AIPreferencesView()
                    } label: {
                        Label("AI Preferences", systemImage: "brain")
                    }

                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy", systemImage: "lock.fill")
                    }

                    NavigationLink {
                        MemorySettingsView()
                    } label: {
                        Label("AI Memory", systemImage: "brain.head.profile")
                    }
                }

                // Premium
                if appState.entitlements.tier == .free {
                    Section {
                        Button {
                            appState.showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text("Upgrade to Premium")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Data
                Section("Data") {
                    NavigationLink {
                        DataExportView()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

                // Support
                Section("Support") {
                    Button {
                        appState.showCrisisResources = true
                    } label: {
                        Label("Crisis Resources", systemImage: "heart.text.square.fill")
                            .foregroundStyle(.red)
                    }

                    Link(destination: URL(string: "mailto:support@mindfriend.app")!) {
                        Label("Contact Support", systemImage: "envelope")
                    }

                    Link(destination: URL(string: "https://mindfriend.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "https://mindfriend.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // Version
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
            .confirmationDialog("Sign Out", isPresented: $showLogoutConfirm) {
                Button("Sign Out", role: .destructive) {
                    logout()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .confirmationDialog("Delete Account", isPresented: $showDeleteConfirm) {
                Button("Delete Account", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This will permanently delete your account and all data. This action cannot be undone.")
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
        }
    }

    private func logout() {
        Task {
            do {
                try await container.supabaseAuthService.signOut()
            } catch {
                print("Logout error: \(error)")
            }
            await MainActor.run {
                appState.setUnauthenticated()
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await container.supabaseAuthService.deleteAccount()
                await MainActor.run {
                    appState.setUnauthenticated()
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var remindersEnabled = true
    @State private var questTime = Date()
    @State private var quietHoursEnabled = false
    @State private var quietStart = Date()
    @State private var quietEnd = Date()

    var body: some View {
        Form {
            Section {
                Toggle("Daily Reminders", isOn: $remindersEnabled)
                DatePicker("Quest Time", selection: $questTime, displayedComponents: .hourAndMinute)
            }

            Section("Quiet Hours") {
                Toggle("Enable Quiet Hours", isOn: $quietHoursEnabled)
                if quietHoursEnabled {
                    DatePicker("Start", selection: $quietStart, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $quietEnd, displayedComponents: .hourAndMinute)
                }
            }
        }
        .navigationTitle("Notifications")
    }
}

struct AIPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTone: AITone = .friendly

    var body: some View {
        Form {
            Section("AI Tone") {
                ForEach(AITone.allCases, id: \.self) { tone in
                    Button {
                        selectedTone = tone
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tone.displayName)
                                    .foregroundStyle(.primary)
                                Text(tone.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTone == tone {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Preferences")
        .onAppear {
            selectedTone = appState.currentUser?.settings.aiTone ?? .friendly
        }
    }
}

struct PrivacySettingsView: View {
    @State private var shareMoodInCircles = true
    @State private var privacyMode: PrivacyMode = .standard

    var body: some View {
        Form {
            Section {
                Toggle("Share Mood in Circles", isOn: $shareMoodInCircles)
            } footer: {
                Text("When enabled, your daily mood will be visible to your circle members")
            }

            Section("Privacy Mode") {
                ForEach(PrivacyMode.allCases, id: \.self) { mode in
                    Button {
                        privacyMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if privacyMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Privacy")
    }
}

struct DataExportView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var isExporting = false
    @State private var exportData: UserDataExport?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Export Your Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Download all your MindFriend data including moods, quests, conversations, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                performExport()
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Text("Export Data")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)

            Spacer()
        }
        .padding()
        .navigationTitle("Export Data")
    }

    private func performExport() {
        isExporting = true
        Task {
            do {
                let data = try await container.supabaseDataService.exportUserData()
                // In real app, would share the data file
                print("Exported: \(data)")
            } catch {
                await MainActor.run {
                    appState.showError(.apiError(error.localizedDescription))
                }
            }
            isExporting = false
        }
    }
}

struct BadgesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(appState.currentUser?.badges ?? []) { badge in
                    BadgeCard(badge: badge)
                }
            }
            .padding()
        }
        .navigationTitle("Badges")
    }
}

struct BadgeCard: View {
    let badge: Badge

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: badge.icon)
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text(badge.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(badge.earnedAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

extension Bundle {
    var appVersion: String {
        "\(infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var displayName: String = ""
    @State private var handle: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var handleValidation: HandleValidation = .empty

    enum HandleValidation {
        case empty
        case checking
        case valid
        case tooShort
        case invalidFormat
        case taken

        var message: String? {
            switch self {
            case .empty: return nil
            case .checking: return "Checking availability..."
            case .valid: return "Handle is available"
            case .tooShort: return "Handle must be at least 3 characters"
            case .invalidFormat: return "Only letters, numbers, and underscores allowed"
            case .taken: return "This handle is already taken"
            }
        }

        var color: Color {
            switch self {
            case .valid: return .green
            case .tooShort, .invalidFormat, .taken: return .red
            default: return .secondary
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)

                    HStack {
                        Text("@")
                            .foregroundStyle(.secondary)
                        TextField("handle", text: $handle)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: handle) { _, newValue in
                                validateHandle(newValue)
                            }

                        if handleValidation == .checking {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if handleValidation == .valid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if handleValidation == .taken || handleValidation == .invalidFormat {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let message = handleValidation.message {
                            Text(message)
                                .foregroundStyle(handleValidation.color)
                        }
                        Text("Your handle is how others find you in circles")
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(isSaving || displayName.isEmpty || !canSave)
                }
            }
            .onAppear {
                displayName = appState.currentUser?.displayName ?? ""
                handle = appState.currentUser?.handle ?? ""
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var canSave: Bool {
        if handle.isEmpty {
            return true // Handle is optional
        }
        return handleValidation == .valid
    }

    private func validateHandle(_ newHandle: String) {
        let trimmed = newHandle.lowercased().trimmingCharacters(in: .whitespaces)

        // Empty is OK (handle is optional)
        guard !trimmed.isEmpty else {
            handleValidation = .empty
            return
        }

        // Check length
        guard trimmed.count >= 3 else {
            handleValidation = .tooShort
            return
        }

        // Check format
        let handleRegex = /^[a-z0-9_]{3,30}$/
        guard trimmed.wholeMatch(of: handleRegex) != nil else {
            handleValidation = .invalidFormat
            return
        }

        // If it's the same as current handle, it's valid
        if trimmed == appState.currentUser?.handle.lowercased() {
            handleValidation = .valid
            return
        }

        // Check availability
        handleValidation = .checking
        Task {
            do {
                let isAvailable = try await container.supabaseAuthService.isHandleAvailable(trimmed)
                await MainActor.run {
                    // Only update if still the same handle
                    if handle.lowercased().trimmingCharacters(in: .whitespaces) == trimmed {
                        handleValidation = isAvailable ? .valid : .taken
                    }
                }
            } catch {
                await MainActor.run {
                    handleValidation = .invalidFormat
                }
            }
        }
    }

    private func saveProfile() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await container.supabaseAuthService.updateProfile(
                    displayName: displayName,
                    handle: handle.isEmpty ? nil : handle
                )

                // Refresh the profile
                let updatedProfile = try await container.supabaseAuthService.fetchProfile()
                await MainActor.run {
                    appState.currentUser = updatedProfile
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            isSaving = false
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
