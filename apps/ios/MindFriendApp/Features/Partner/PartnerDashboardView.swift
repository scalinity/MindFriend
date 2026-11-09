import SwiftUI

/// Dashboard view showing partner data and actions
struct PartnerDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: PartnerModeViewModel
    let partnerInfo: PartnerInfo

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
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
            .padding(.vertical, SupportTheme.Spacing.m)
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Their Progress")
                .font(.headline)
                .padding(.horizontal, SupportTheme.Spacing.l)

            // Mood card
            if partnerInfo.isSharingMood {
                SharedMoodCard(moods: viewModel.partnerMoods)
                    .padding(.horizontal, SupportTheme.Spacing.m)
            } else {
                PartnerPlaceholder(
                    icon: "face.smiling",
                    title: "Mood not shared",
                    message: "Your partner hasn't enabled mood sharing yet"
                )
                .padding(.horizontal, SupportTheme.Spacing.m)
            }

            // Quest card
            if partnerInfo.isSharingExercises {
                SharedQuestCard(quest: viewModel.partnerQuest)
                    .padding(.horizontal, SupportTheme.Spacing.m)
            } else {
                PartnerPlaceholder(
                    icon: "star",
                    title: "Quests not shared",
                    message: "Your partner hasn't enabled exercise sharing yet"
                )
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
        }
    }

    // MARK: - Together Section

    private var togetherSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Together")
                .font(.headline)
                .padding(.horizontal, SupportTheme.Spacing.l)

            NavigationLink(destination: SharedExercisesView(viewModel: viewModel)) {
                HStack {
                    Image(systemName: "figure.2.arms.open")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Couples Exercises")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(SupportTheme.textPrimary)

                        Text("Do mindfulness activities together")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .supportCard()
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            NavigationLink(destination: PartnerSharingSettingsView(viewModel: viewModel)) {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text("Sharing Settings")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .supportCard()
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
    }

    // MARK: - Encouragement Sent Overlay

    private var encouragementSentOverlay: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 50))
                .foregroundStyle(.tint)

            Text("Encouragement sent!")
                .font(.headline)
        }
        .padding(SupportTheme.Spacing.xl)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.cardRadius)
        .transition(reduceMotion ? .opacity.animation(.easeInOut(duration: 0.2)) : .scale.combined(with: .opacity))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(), value: viewModel.showEncouragementSent)
    }
}

// Previews disabled - requires authenticated SupabaseDataService
