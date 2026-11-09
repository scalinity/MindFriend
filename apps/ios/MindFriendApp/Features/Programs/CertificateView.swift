import SwiftUI

// MARK: - Certificates List View

struct CertificatesListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var certificates: [ProgramCertificate] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let loadError {
                SupportUnavailableState(title: "Certificates couldn’t load", message: loadError, actionTitle: "Try again") {
                    Task { await loadCertificates() }
                }
            } else if certificates.isEmpty {
                EmptyCertificatesView()
            } else {
                ScrollView {
                    LazyVStack(spacing: SupportTheme.Spacing.m) {
                        ForEach(certificates) { certificate in
                            NavigationLink {
                                CertificateDetailView(certificate: certificate)
                            } label: {
                                CertificateCard(certificate: certificate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(SupportTheme.Spacing.m)
                    .frame(maxWidth: SupportTheme.readableWidth)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .supportScreen()
        .navigationTitle("My Certificates")
        .task { await loadCertificates() }
    }

    private func loadCertificates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            certificates = try await container.supabaseDataService.getCertificates()
            loadError = nil
        } catch {
            // Shown in place on this page; a failure here is not a reason to interrupt with an alert.
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Certificate Card

struct CertificateCard: View {
    let certificate: ProgramCertificate

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack(spacing: SupportTheme.Spacing.s) {
                Image(systemName: certificate.program?.category.icon ?? "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(SupportTheme.Celebration.gold)
                    .frame(width: SupportTheme.minimumTarget, height: SupportTheme.minimumTarget)
                    .background(SupportTheme.elevated, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .accessibilityHidden(true)

                VStack(alignment: .leading) {
                    Text(certificate.program?.title ?? "Program")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text(certificate.issuedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(SupportTheme.textSecondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: SupportTheme.Spacing.m) {
                StatBadge(label: "Days", value: "\(certificate.completionStats.daysCompleted)")
                StatBadge(label: "Skips used", value: "\(certificate.completionStats.skipsUsed)")
            }
        }
        .supportCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Certificate for \(certificate.program?.title ?? "Program"), completed on \(certificate.issuedAt.formatted(date: .abbreviated, time: .omitted)). \(certificate.completionStats.daysCompleted) days completed, \(certificate.completionStats.skipsUsed) skips used")
        .accessibilityHint("Double tap to view certificate details")
    }
}

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Certificate Detail View

struct CertificateDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    let certificate: ProgramCertificate

    @State private var isSharing = false

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                CertificateVisual(certificate: certificate)

                VStack(spacing: SupportTheme.Spacing.m) {
                    Text("Completion")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: SupportTheme.Spacing.l) {
                        StatColumn(
                            icon: "calendar",
                            value: "\(certificate.completionStats.daysCompleted)",
                            label: "Days completed"
                        )

                        StatColumn(
                            icon: "arrow.right.circle",
                            value: "\(certificate.completionStats.skipsUsed)",
                            label: "Skips used"
                        )
                    }
                }
                .supportCard()

                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        Task { await shareToCircle() }
                    } label: {
                        Label(
                            certificate.sharedToCircle ? "Shared to Circle" : "Share to Circle",
                            systemImage: certificate.sharedToCircle ? "checkmark.circle.fill" : "person.2.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportSecondary)
                    .disabled(certificate.sharedToCircle)

                    Button {
                        shareExternally()
                    } label: {
                        Label("Share certificate", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)
                }
            }
            .padding(SupportTheme.Spacing.m)
            .frame(maxWidth: SupportTheme.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .supportScreen()
        .navigationTitle("Certificate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shareToCircle() async {
        do {
            try await container.supabaseDataService.shareCertificateToCircle(certificateId: certificate.id)
            appState.showCelebration(
                title: "Shared",
                subtitle: "Shared to your circle",
                icon: "checkmark.circle.fill"
            )
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func shareExternally() {
        let text = "I completed the \(certificate.program?.title ?? "wellness program") on MindFriend. Certificate #\(certificate.certificateNumber)"

        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }

        Task {
            try? await container.supabaseDataService.shareCertificateExternally(certificateId: certificate.id)
        }
    }
}

struct StatColumn: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(SupportTheme.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Certificate Visual

struct CertificateVisual: View {
    let certificate: ProgramCertificate

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 50))
                .foregroundStyle(SupportTheme.Celebration.gold)
                .accessibilityHidden(true)

            Text("Certificate of completion")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SupportTheme.textSecondary)

            Text(certificate.program?.title ?? "Wellness Program")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Completed \(certificate.issuedAt.formatted(date: .long, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            Divider()
                .overlay(SupportTheme.separator)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            Text("Certificate #\(certificate.certificateNumber)")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .fontDesign(.monospaced)
        }
        .padding(SupportTheme.Spacing.l)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                .strokeBorder(SupportTheme.Celebration.gold, lineWidth: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Certificate of Completion for \(certificate.program?.title ?? "Wellness Program"). Completed \(certificate.issuedAt.formatted(date: .long, time: .omitted)). Certificate number \(certificate.certificateNumber)")
    }
}

// MARK: - Empty State

struct EmptyCertificatesView: View {
    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "medal")
                .font(.system(size: 48))
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)

            Text("No certificates yet")
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)

            Text("Complete a program to earn your first certificate.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(SupportTheme.Spacing.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No certificates yet. Complete a program to earn your first certificate.")
    }
}

#Preview("Certificates List") {
    NavigationStack {
        CertificatesListView()
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}

#Preview("Certificate Detail") {
    NavigationStack {
        CertificateDetailView(certificate: ProgramCertificate(
            id: "1",
            userId: "user1",
            programId: "prog1",
            enrollmentId: "enroll1",
            certificateNumber: "MF-2024-001234",
            completionStats: ProgramCompletionStats(
                daysCompleted: 21,
                streakBest: 18,
                skipsUsed: 1,
                programTitle: "21-Day Anxiety Reset"
            ),
            issuedAt: Date(),
            sharedToCircle: false,
            sharedExternally: false,
            program: Program(
                id: "prog1",
                slug: "21-day-anxiety-reset",
                title: "21-Day Anxiety Reset",
                description: "A comprehensive program",
                durationDays: 21,
                category: .anxiety,
                difficulty: .beginner,
                premiumOnly: false,
                learningObjectives: [],
                tags: [],
                coverImageUrl: nil,
                estimatedDailyMinutes: 15,
                sortOrder: 1,
                methodology: nil,
                evidenceSummary: nil,
                evidenceUrl: nil,
                targetConditions: [],
                requiresBaselineAssessment: false,
                assessmentType: nil
            )
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
