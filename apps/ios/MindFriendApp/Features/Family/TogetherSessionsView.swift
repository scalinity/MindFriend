import SwiftUI

/// View for together sessions (synchronized family activities)
struct TogetherSessionsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var sessions: [TogetherSession] = []
    @State private var templates: [TogetherTemplate] = []
    @State private var isLoading = false
    @State private var showStartSession = false
    let familyGroup: FamilyWellnessGroup

    var activeSessions: [TogetherSession] {
        sessions.filter { $0.status == .inProgress }
    }

    var upcomingSessions: [TogetherSession] {
        sessions.filter { $0.status == .pending }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Active Sessions
                    if !activeSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Currently Active")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(activeSessions, id: \.id) { session in
                                TogetherActiveSessionCard(session: session)
                            }
                        }
                    }

                    // Upcoming Sessions
                    if !upcomingSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(upcomingSessions, id: \.id) { session in
                                SessionCard(session: session)
                            }
                        }
                    }

                    // Start New Activity
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Start an Activity")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(templates.prefix(4), id: \.id) { template in
                            TemplateCard(template: template) {
                                // Start session with this template
                            }
                        }
                    }

                    if sessions.isEmpty && templates.isEmpty && !isLoading {
                        VStack(spacing: 16) {
                            Image(systemName: "person.2.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(.gray)
                            Text("No activities yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(.vertical)
            }

            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Together Sessions")
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let sessionsTask = container.familyService.fetchTogetherSessions()
            async let templatesTask = container.familyService.fetchTogetherTemplates()

            sessions = try await sessionsTask
            templates = try await templatesTask
        } catch {
            Log.family.error("Failed to load data", error: error)
        }
    }
}

// MARK: - Supporting Cards

struct TogetherActiveSessionCard: View {
    let session: TogetherSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                    Text("In Progress")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            }

            if let timeRemaining = session.timeRemaining {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Time remaining: \(formatTimeInterval(timeRemaining))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: {}) {
                Text("View Details")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SessionCard: View {
    let session: TogetherSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let scheduledFor = session.scheduledFor {
                    Text(scheduledFor.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.white)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TemplateCard: View {
    let template: TogetherTemplate
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let description = template.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(template.formattedDuration)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }

            Button(action: action) {
                Text("Start Activity")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(6)
                    .font(.caption)
            }
        }
        .padding()
        .background(.gray.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        TogetherSessionsView(
            familyGroup: .init(
                id: "test",
                name: "Test Family",
                adminUserId: "admin",
                circleId: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        .environmentObject(DependencyContainer.preview)
    }
}
