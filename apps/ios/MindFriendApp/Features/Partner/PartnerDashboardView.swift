import SwiftUI

/// Dashboard view showing partner data and actions
struct PartnerDashboardView: View {
    @ObservedObject var viewModel: PartnerModeViewModel
    let partnerInfo: PartnerInfo

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Partner status card
                PartnerStatusCard(
                    partnerInfo: partnerInfo,
                    onSendEncouragement: {
                        viewModel.showEncouragementPicker = true
                    }
                )

                // Shared data section
                sharedDataSection

                // Together section
                togetherSection

                // Settings link
                settingsSection
            }
            .padding(.vertical, 16)
        }
        .refreshable {
            await viewModel.loadPartnerData()
        }
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .sheet(isPresented: $viewModel.showEncouragementPicker) {
            EncouragementPickerSheet(
                onSelect: { type in
                    Task {
                        await viewModel.sendEncouragement(type)
                    }
                },
                isLoading: viewModel.isSendingEncouragement
            )
            .presentationDetents([.medium])
        }
        .overlay {
            if viewModel.showEncouragementSent {
                encouragementSentOverlay
            }
        }
    }

    // MARK: - Shared Data Section

    private var sharedDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Their Progress")
                .font(.headline)
                .padding(.horizontal, 20)

            // Mood card
            if partnerInfo.isSharingMood {
                SharedMoodCard(moods: viewModel.partnerMoods)
                    .padding(.horizontal, 16)
            } else {
                PartnerPlaceholder(
                    icon: "face.smiling",
                    title: "Mood not shared",
                    message: "Your partner hasn't enabled mood sharing yet"
                )
                .padding(.horizontal, 16)
            }

            // Quest card
            if partnerInfo.isSharingExercises {
                SharedQuestCard(quest: viewModel.partnerQuest)
                    .padding(.horizontal, 16)
            } else {
                PartnerPlaceholder(
                    icon: "star",
                    title: "Quests not shared",
                    message: "Your partner hasn't enabled exercise sharing yet"
                )
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Together Section

    private var togetherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Together")
                .font(.headline)
                .padding(.horizontal, 20)

            NavigationLink(destination: SharedExercisesView(viewModel: viewModel)) {
                HStack {
                    Image(systemName: "figure.2.arms.open")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Couples Exercises")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text("Do mindfulness activities together")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(destination: PartnerSharingSettingsView(viewModel: viewModel)) {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Text("Sharing Settings")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Encouragement Sent Overlay

    private var encouragementSentOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)

            Text("Encouragement sent!")
                .font(.headline)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(), value: viewModel.showEncouragementSent)
    }
}

// Previews disabled - requires authenticated SupabaseDataService
