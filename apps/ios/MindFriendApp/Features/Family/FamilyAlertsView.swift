import SwiftUI

/// View for displaying family alerts (for parents)
struct FamilyAlertsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var alerts: [FamilyAlert] = []
    @State private var isLoading = false
    let familyGroup: FamilyWellnessGroup

    var unreadAlerts: [FamilyAlert] {
        alerts.filter { !$0.wasRead }
    }

    var readAlerts: [FamilyAlert] {
        alerts.filter { $0.wasRead }
    }

    var body: some View {
        ZStack {
            if alerts.isEmpty && !isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                    Text("No alerts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("All is well with your family!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Unread Alerts
                        if !unreadAlerts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("New Alerts")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(unreadAlerts, id: \.id) { alert in
                                    AlertCard(alert: alert, onDismiss: {
                                        markAlertAsRead(alert.id)
                                    })
                                }
                            }
                        }

                        // Read Alerts
                        if !readAlerts.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("History")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(readAlerts.prefix(5), id: \.id) { alert in
                                    AlertCard(alert: alert, onDismiss: {})
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }

            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Alerts")
        .task {
            await loadAlerts()
        }
    }

    private func loadAlerts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            alerts = try await container.familyService.fetchFamilyAlerts()
        } catch {
            print("Failed to load alerts: \(error)")
        }
    }

    private func markAlertAsRead(_ alertId: String) {
        Task {
            do {
                try await container.familyService.markAlertAsRead(alertId: alertId)
                alerts = try await container.familyService.fetchFamilyAlerts()
            } catch {
                print("Failed to mark alert as read: \(error)")
            }
        }
    }
}

// MARK: - Alert Card

struct AlertCard: View {
    let alert: FamilyAlert
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(alert.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        Image(systemName: severityIcon(alert.severity))
                            .foregroundStyle(severityColor(alert.severity))
                    }

                    Text(alert.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            // Conversation Starters
            if let starters = alert.conversationStarters, !starters.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested topics:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(starters.prefix(2), id: \.self) { starter in
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text(starter)
                                .font(.caption2)
                        }
                    }
                }
                .padding(8)
                .background(.blue.opacity(0.05))
                .cornerRadius(6)
            }

            // Action Button
            if let actionType = alert.actionType {
                Button(action: {}) {
                    Text(actionLabel(actionType))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .cornerRadius(6)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(12)
        .padding(.horizontal)
        .opacity(alert.wasRead ? 0.7 : 1.0)
    }

    private func severityIcon(_ severity: AlertSeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .concern: return "xmark.circle.fill"
        }
    }

    private func severityColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .attention: return .orange
        case .concern: return .red
        }
    }

    private func actionLabel(_ actionType: AlertActionType) -> String {
        switch actionType {
        case .startConversation: return "Start Conversation"
        case .checkIn: return "Check In"
        case .celebrate: return "Celebrate"
        }
    }
}

#Preview {
    NavigationStack {
        FamilyAlertsView(
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
