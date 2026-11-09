import SwiftUI

/// View for displaying family alerts (for parents)
struct FamilyAlertsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var alerts: [FamilyAlert] = []
    @State private var isLoading = false
    @State private var loadError: String?
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
                VStack(spacing: SupportTheme.Spacing.m) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 40))
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("No alerts")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("All is well with your family!")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SupportTheme.surface)
            } else {
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.l) {
                        // Unread Alerts
                        if !unreadAlerts.isEmpty {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
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
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
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
        .safeAreaInset(edge: .bottom) {
            if let loadError {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label("Family alerts unavailable", systemImage: "exclamationmark.triangle")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    Text(loadError)
                    Button("Try Again") { Task { await loadAlerts() } }
                        .buttonStyle(.supportSecondary)
                }
                .supportCard()
                .padding(SupportTheme.Spacing.m)
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Alerts")
        .task {
            await loadAlerts()
        }
    }

    private func loadAlerts() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            alerts = try await container.familyService.fetchFamilyAlerts()
        } catch {
            loadError = error.localizedDescription
            Log.family.error("Failed to load alerts", error: error)
        }
    }

    private func markAlertAsRead(_ alertId: String) {
        Task {
            do {
                try await container.familyService.markAlertAsRead(alertId: alertId)
                alerts = try await container.familyService.fetchFamilyAlerts()
            } catch {
                Log.family.error("Failed to mark alert as read", error: error)
            }
        }
    }
}

// MARK: - Alert Card

struct AlertCard: View {
    let alert: FamilyAlert
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
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
                        .foregroundStyle(SupportTheme.textSecondary)
                        .lineLimit(3)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SupportTheme.textSecondary)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .accessibilityLabel("Dismiss family alert")
            }

            // Conversation Starters
            if let starters = alert.conversationStarters, !starters.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Suggested topics:")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)

                    ForEach(starters.prefix(2), id: \.self) { starter in
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption2)
                                .foregroundStyle(SupportTheme.accent)
                            Text(starter)
                                .font(.caption2)
                        }
                    }
                }
                .padding(SupportTheme.Spacing.xs)
                .background(SupportTheme.surface)
                .cornerRadius(SupportTheme.controlRadius)
            }

            // Action Button
            if let actionType = alert.actionType {
                Button(action: {}) {
                    Text(actionLabel(actionType))
                        .frame(maxWidth: .infinity)
                        .font(.caption)
                }
                .buttonStyle(.supportSecondary)
            }
        }
        .supportCard()
        .padding(.horizontal)
        .opacity(alert.wasRead ? 0.7 : 1.0)
    }

    private func severityIcon(_ severity: FamilyAlertSeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .concern: return "xmark.circle.fill"
        }
    }

    private func severityColor(_ severity: FamilyAlertSeverity) -> Color {
        switch severity {
        case .info: return SupportTheme.accent
        case .attention: return SupportTheme.accent
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
