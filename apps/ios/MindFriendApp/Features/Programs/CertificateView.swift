import SwiftUI

// MARK: - Certificates List View

struct CertificatesListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var certificates: [ProgramCertificate] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if certificates.isEmpty {
                EmptyCertificatesView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(certificates) { certificate in
                            NavigationLink {
                                CertificateDetailView(certificate: certificate)
                            } label: {
                                CertificateCard(certificate: certificate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("My Certificates")
        .task { await loadCertificates() }
    }

    private func loadCertificates() async {
        isLoading = true
        defer { isLoading = false }

        do {
            certificates = try await container.supabaseDataService.getCertificates()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

// MARK: - Certificate Card

struct CertificateCard: View {
    let certificate: ProgramCertificate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Program icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill((certificate.program?.category.color ?? .blue).gradient)
                        .frame(width: 44, height: 44)

                    Image(systemName: certificate.program?.category.icon ?? "checkmark.seal.fill")
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading) {
                    Text(certificate.program?.title ?? "Program")
                        .font(.headline)

                    Text(certificate.issuedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            // Stats
            HStack(spacing: 16) {
                StatBadge(label: "Days", value: "\(certificate.completionStats.daysCompleted)")
                StatBadge(label: "Best Streak", value: "\(certificate.completionStats.streakBest)")
                StatBadge(label: "Skips Used", value: "\(certificate.completionStats.skipsUsed)")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Certificate for \(certificate.program?.title ?? "Program"), completed on \(certificate.issuedAt.formatted(date: .abbreviated, time: .omitted)). \(certificate.completionStats.daysCompleted) days completed, best streak \(certificate.completionStats.streakBest), \(certificate.completionStats.skipsUsed) skips used")
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
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            VStack(spacing: 24) {
                // Certificate visual
                CertificateVisual(certificate: certificate)

                // Stats
                VStack(spacing: 16) {
                    Text("Completion Stats")
                        .font(.headline)

                    HStack(spacing: 24) {
                        StatColumn(
                            icon: "calendar",
                            value: "\(certificate.completionStats.daysCompleted)",
                            label: "Days Completed"
                        )

                        StatColumn(
                            icon: "flame.fill",
                            value: "\(certificate.completionStats.streakBest)",
                            label: "Best Streak"
                        )

                        StatColumn(
                            icon: "arrow.right.circle",
                            value: "\(certificate.completionStats.skipsUsed)",
                            label: "Skips Used"
                        )
                    }
                }

                // Share buttons
                VStack(spacing: 12) {
                    Button {
                        Task { await shareToCircle() }
                    } label: {
                        Label(
                            certificate.sharedToCircle ? "Shared to Circle" : "Share to Circle",
                            systemImage: certificate.sharedToCircle ? "checkmark.circle.fill" : "person.2.circle"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(certificate.sharedToCircle)

                    Button {
                        shareExternally()
                    } label: {
                        Label("Share Certificate", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Certificate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shareToCircle() async {
        do {
            try await container.supabaseDataService.shareCertificateToCircle(certificateId: certificate.id)
            appState.showCelebration(
                title: "Shared!",
                subtitle: "Shared to your circle",
                icon: "checkmark.circle.fill"
            )
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func shareExternally() {
        let text = "I completed the \(certificate.program?.title ?? "wellness program") on MindFriend! Certificate #\(certificate.certificateNumber)"

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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        VStack(spacing: 16) {
            // Border decoration
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [.yellow, .orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                )
                .overlay {
                    VStack(spacing: 16) {
                        // Seal
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.yellow.gradient)
                            .accessibilityHidden(true)

                        Text("Certificate of Completion")
                            .font(.caption)
                            .textCase(.uppercase)
                            .tracking(2)
                            .foregroundStyle(.secondary)

                        Text(certificate.program?.title ?? "Wellness Program")
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("Completed \(certificate.issuedAt.formatted(date: .long, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()
                            .padding(.horizontal, 40)

                        Text("Certificate #\(certificate.certificateNumber)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fontDesign(.monospaced)
                    }
                    .padding(24)
                }
                .frame(height: 300)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Certificate of Completion for \(certificate.program?.title ?? "Wellness Program"). Completed \(certificate.issuedAt.formatted(date: .long, time: .omitted)). Certificate number \(certificate.certificateNumber)")
    }
}

// MARK: - Empty State

struct EmptyCertificatesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "medal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Certificates Yet")
                .font(.headline)

            Text("Complete a program to earn your first certificate!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
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
                sortOrder: 1
            )
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
