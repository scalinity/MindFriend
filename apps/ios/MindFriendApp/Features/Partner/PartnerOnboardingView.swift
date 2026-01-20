import SwiftUI

/// Onboarding view with tabs for sending invites and entering codes
struct PartnerOnboardingView: View {
    @ObservedObject var viewModel: PartnerModeViewModel
    var pendingCode: String?
    var expiresAt: Date?

    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Tab picker
                Picker("", selection: $selectedTab) {
                    Text("Send Invite").tag(0)
                    Text("Enter Code").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                // Tab content
                if selectedTab == 0 {
                    sendInviteTab
                } else {
                    enterCodeTab
                }

                // Benefits section
                benefitsSection
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Partner Up")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Connect with a partner for accountability and support on your wellness journey")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Send Invite Tab

    private var sendInviteTab: some View {
        VStack(spacing: 20) {
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
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 4)
                        }
                        Text(viewModel.isLoading ? "Generating..." : "Create Invite Code")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Create invite code")
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Enter Code Tab

    private var enterCodeTab: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter your partner's code")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 4)
                    }
                    Text(viewModel.isValidatingCode ? "Connecting..." : "Connect")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.isCodeInputValid ? Color.accentColor : Color.secondary.opacity(0.3))
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(!viewModel.isCodeInputValid || viewModel.isValidatingCode)
            .accessibilityLabel("Connect with partner")
            .accessibilityHint(viewModel.isCodeInputValid ? "Enter the 6-character code from your partner" : "Enter a valid 6-character code first")
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Why partner up?")
                .font(.headline)

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
                icon: "flame.fill",
                title: "Shared streaks",
                description: "See each other's progress and celebrate together"
            )

            PartnerBenefitRow(
                icon: "figure.2.arms.open",
                title: "Couples exercises",
                description: "Complete mindfulness activities together"
            )
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .padding(.horizontal, 24)
    }
}

// MARK: - Supporting Views

private struct PartnerBenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// Previews disabled - requires authenticated SupabaseDataService
