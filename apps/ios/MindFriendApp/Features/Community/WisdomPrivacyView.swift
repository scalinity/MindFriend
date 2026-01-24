import SwiftUI
import Supabase

/// Privacy settings for Community Wisdom participation
struct WisdomPrivacyView: View {
    @EnvironmentObject private var wisdomService: WisdomService
    @State private var contributeEnabled = false
    @State private var receiveEnabled = false
    @State private var isLoading = false
    @State private var showingDataPreview = false

    var body: some View {
        List {
            // Explainer Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.title)
                            .foregroundColor(.purple)
                        Text("How Community Wisdom Works")
                            .font(.headline)
                    }

                    Text("MindFriend learns what helps people feel better by analyzing anonymous patterns across our community. No personal information is ever shared.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            // Contribution Toggle
            Section {
                Toggle(isOn: $contributeEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contribute Anonymous Data")
                            .font(.body)
                        Text("Help improve MindFriend for everyone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: contributeEnabled) { _, newValue in
                    updateConsent()
                }

                if contributeEnabled {
                    Button {
                        showingDataPreview = true
                    } label: {
                        HStack {
                            Text("See What's Contributed")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Contribute")
            } footer: {
                Text("Your data is hashed with SHA-256 encryption. We never store your user ID with contributions.")
            }

            // Receive Recommendations Toggle
            Section {
                Toggle(isOn: $receiveEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Receive Recommendations")
                            .font(.body)
                        Text("Get personalized community insights")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: receiveEnabled) { _, newValue in
                    updateConsent()
                }
            } header: {
                Text("Receive")
            } footer: {
                Text("Recommendations are based on patterns from people in similar situations. You can give feedback to improve relevance.")
            }

            // Privacy Details
            Section {
                PrivacyDetailRow(
                    icon: "lock.shield",
                    title: "Fully Anonymous",
                    description: "Your identity is never linked to contributions"
                )

                PrivacyDetailRow(
                    icon: "person.2",
                    title: "Aggregated Only",
                    description: "We only show patterns from 10+ people"
                )

                PrivacyDetailRow(
                    icon: "clock.arrow.circlepath",
                    title: "Auto-Cleanup",
                    description: "Raw data is deleted after 90 days"
                )

                PrivacyDetailRow(
                    icon: "hand.raised",
                    title: "Your Choice",
                    description: "You can opt out anytime"
                )
            } header: {
                Text("Privacy Guarantees")
            }
        }
        .navigationTitle("Community Wisdom Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDataPreview) {
            DataPreviewSheet()
        }
        .task {
            await loadConsent()
        }
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    private func loadConsent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await wisdomService.fetchConsent()
            contributeEnabled = wisdomService.consent?.contributeAnonymousData ?? false
            receiveEnabled = wisdomService.consent?.receiveRecommendations ?? false
        } catch {
            print("Failed to load consent: \(error)")
        }
    }

    private func updateConsent() {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                try await wisdomService.updateConsent(
                    contribute: contributeEnabled,
                    receive: receiveEnabled
                )
            } catch {
                // Revert on failure
                contributeEnabled = wisdomService.consent?.contributeAnonymousData ?? false
                receiveEnabled = wisdomService.consent?.receiveRecommendations ?? false
                print("Failed to update consent: \(error)")
            }
        }
    }
}

// MARK: - Privacy Detail Row

private struct PrivacyDetailRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.purple)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Data Preview Sheet

private struct DataPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("When you log a mood, we contribute:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    DataPreviewItem(label: "Mood Score", value: "3 (1-5 scale)")
                    DataPreviewItem(label: "Time of Day", value: "morning")
                    DataPreviewItem(label: "Emotion", value: "anxious")
                } header: {
                    Text("Mood Patterns")
                }

                Section {
                    Text("When you complete an exercise, we contribute:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    DataPreviewItem(label: "Exercise Type", value: "breathing")
                    DataPreviewItem(label: "Your Rating", value: "4 (1-5 scale)")
                } header: {
                    Text("Exercise Effectiveness")
                }

                Section {
                    Text("When you progress in a pathway, we contribute:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    DataPreviewItem(label: "Pathway Type", value: "anxiety_reduction")
                    DataPreviewItem(label: "Phase Number", value: "2")
                } header: {
                    Text("Pathway Progress")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What We Never Store:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        BulletPoint(text: "Your name or email")
                        BulletPoint(text: "Your user ID")
                        BulletPoint(text: "Journal entries or chat messages")
                        BulletPoint(text: "Any personally identifiable information")
                    }
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Data Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DataPreviewItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .font(.subheadline)
    }
}

private struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.red)
            Text(text)
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

#Preview {
    NavigationStack {
        WisdomPrivacyView()
            .environmentObject(WisdomService(supabase: DependencyContainer.shared.supabaseClient))
    }
}
