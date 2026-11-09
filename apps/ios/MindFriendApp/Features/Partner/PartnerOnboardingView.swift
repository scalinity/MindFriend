import SwiftUI

/// Onboarding view with tabs for sending invites and entering codes
struct PartnerOnboardingView: View {
    @ObservedObject var viewModel: PartnerModeViewModel
    var pendingCode: String?
    var expiresAt: Date?

    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                headerSection

                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("Send Invite").tag(0)
                    Text("Enter Code").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Tab content
                if selectedTab == 0 {
                    sendInviteTab
                } else {
                    enterCodeTab
                }

                // Benefits section
                benefitsSection
            }
            .padding(.vertical, SupportTheme.Spacing.l)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Partner Up")
                    .font(.title)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)

                Text("Connect with a partner for accountability and support on your wellness journey")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
    }

    // MARK: - Send Invite Tab

    private var sendInviteTab: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            if let code = pendingCode ?? viewModel.inviteCode {
                // Show existing code
                InviteCodeDisplay(
                    code: code,
                    expiresAt: expiresAt ?? viewModel.inviteExpiresAt ?? Date().addingTimeInterval(30 * 24 * 60 * 60)
                )
            } else {
                // Generate code button
                Button(action: {
                    Task {
                        await viewModel.generateInviteCode()
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: SupportTheme.onAccent))
                        }
                        Text(viewModel.isLoading ? "Generating..." : "Create Invite Code")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.supportPrimary)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Create invite code")
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
    }

    // MARK: - Enter Code Tab

    private var enterCodeTab: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("Enter your partner's code")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                CodeEntryField(code: $viewModel.codeInput)
            }

            Button(action: {
                Task {
                    await viewModel.acceptInviteCode()
                }
            }) {
                HStack {
                    if viewModel.isValidatingCode {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: SupportTheme.onAccent))
                            .padding(.trailing, SupportTheme.Spacing.xxs)
                    }
                    Text(viewModel.isValidatingCode ? "Connecting..." : "Connect")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.supportPrimary)
            .disabled(!viewModel.isCodeInputValid || viewModel.isValidatingCode)
            .accessibilityLabel("Connect with partner")
            .accessibilityHint(viewModel.isCodeInputValid ? "Enter the 8-character code from your partner" : "Enter a valid 8-character code first")
        }
        .padding(.horizontal, SupportTheme.Spacing.l)
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Why partner up?")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            PartnerBenefitRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "3x more likely to succeed",
                description: "Studies show accountability partners improve outcomes"
            )

            PartnerBenefitRow(
                icon: "heart.fill",
                title: "Mutual encouragement",
                description: "Send supportive messages when your partner needs it"
            )

            PartnerBenefitRow(
                icon: "hands.sparkles.fill",
                title: "Shared encouragement",
                description: "See each other's progress and celebrate together"
            )

            PartnerBenefitRow(
                icon: "figure.2.arms.open",
                title: "Couples exercises",
                description: "Complete mindfulness activities together"
            )
        }
        .padding(SupportTheme.Spacing.l)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.cardRadius)
        .padding(.horizontal, SupportTheme.Spacing.l)
    }
}

// MARK: - Supporting Views

private struct PartnerBenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(minWidth: 28)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()
        }
    }
}

// Previews disabled - requires authenticated SupabaseDataService
