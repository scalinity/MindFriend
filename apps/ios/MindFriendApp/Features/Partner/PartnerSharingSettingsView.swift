import SwiftUI

/// View for managing what data you share with your partner
struct PartnerSharingSettingsView: View {
    @ObservedObject var viewModel: PartnerModeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEndPartnershipAlert = false

    var body: some View {
        List {
            // Sharing toggles section
            Section {
                SharingToggleRow(
                    icon: "face.smiling",
                    title: "Share my mood",
                    description: "Let your partner see your mood check-ins",
                    isOn: Binding(
                        get: { viewModel.mySharingSettings.shareMood },
                        set: { newValue in
                            Task {
                                await viewModel.updateSharingSettings(shareMood: newValue)
                            }
                        }
                    ),
                    isLoading: viewModel.isSavingSettings
                )

                SharingToggleRow(
                    icon: "star",
                    title: "Share my exercises",
                    description: "Let your partner see your quest progress",
                    isOn: Binding(
                        get: { viewModel.mySharingSettings.shareExercises },
                        set: { newValue in
                            Task {
                                await viewModel.updateSharingSettings(shareExercises: newValue)
                            }
                        }
                    ),
                    isLoading: viewModel.isSavingSettings
                )
            } header: {
                Text("What you share")
            } footer: {
                Text("Your partner will only see data you explicitly choose to share. Changes take effect immediately.")
            }

            // Partner's sharing section
            Section {
                if case .hasPartner(let info) = viewModel.partnerState {
                    HStack {
                        Image(systemName: "face.smiling")
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        Text("Their mood")
                        Spacer()
                        Text(info.isSharingMood ? "Shared" : "Not shared")
                            .foregroundStyle(info.isSharingMood ? .green : .secondary)
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: "star")
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        Text("Their exercises")
                        Spacer()
                        Text(info.isSharingExercises ? "Shared" : "Not shared")
                            .foregroundStyle(info.isSharingExercises ? .green : .secondary)
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("What your partner shares")
            }

            // End partnership section
            Section {
                Button(role: .destructive) {
                    showEndPartnershipAlert = true
                } label: {
                    HStack {
                        Image(systemName: "person.badge.minus")
                        Text("End Partnership")
                    }
                }
            } footer: {
                Text("Ending the partnership will remove shared data access for both of you. This cannot be undone.")
            }
        }
        .navigationTitle("Sharing Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("End Partnership?", isPresented: $showEndPartnershipAlert) {
            Button("Cancel", role: .cancel) { }
            Button("End Partnership", role: .destructive) {
                Task {
                    await viewModel.endPartnership()
                    dismiss()
                }
            }
        } message: {
            Text("This will end your partnership and remove shared data access. You can always connect with a new partner later.")
        }
    }
}

// MARK: - Sharing Toggle Row

struct SharingToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

// Previews disabled - requires authenticated SupabaseDataService
