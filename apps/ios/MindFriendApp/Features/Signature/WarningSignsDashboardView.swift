import SwiftUI

/// Dashboard showing user's warning signs, active signals, and accuracy statistics
struct WarningSignsDashboardView: View {
    @EnvironmentObject private var container: DependencyContainer
    @ObservedObject var engine: StressSignatureEngine

    @State private var showingOnboarding = false
    @State private var showingRelearn = false
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let signature = engine.currentSignature {
                    // Confidence card
                    confidenceCard(signature: signature)

                    // Active signals
                    if let result = engine.lastDetectionResult, !result.activeComponents.isEmpty {
                        activeSignalsCard(result: result)
                    }

                    // Your signature
                    signatureCard(signature: signature)

                    // Accuracy stats
                    if let stats = engine.accuracyStats, stats.totalAlerts > 0 {
                        accuracyCard(stats: stats)
                    }

                    // Recent alerts
                    if !engine.activeAlerts.isEmpty {
                        recentAlertsCard
                    }

                    // Actions
                    actionsCard
                } else {
                    noSignatureView
                }
            }
            .padding()
        }
        .navigationTitle("Warning Signs")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await refreshData()
        }
        .sheet(isPresented: $showingOnboarding) {
            SignatureOnboardingFlow()
        }
        .alert("Re-Learn Patterns", isPresented: $showingRelearn) {
            Button("Cancel", role: .cancel) {}
            Button("Re-Learn") {
                Task {
                    try? await engine.learnFromHistory()
                }
            }
        } message: {
            Text("This will analyze your crisis history to update your warning signs. Your existing patterns will be merged with newly discovered ones.")
        }
        .task {
            await refreshData()
        }
    }

    // MARK: - Confidence Card

    private func confidenceCard(signature: WarningSignature) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Pattern Confidence")
                        .font(.headline)
                    Text("How well your signature predicts crises")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                confidenceBadge(confidence: signature.confidence)
            }

            // Confidence gauge
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(confidenceColor(signature.confidence).gradient)
                        .frame(width: geometry.size.width * signature.confidence)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Source: \(signature.source.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastLearned = signature.lastLearnedAt {
                    Text("Updated \(lastLearned, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func confidenceBadge(confidence: Double) -> some View {
        Text("\(Int(confidence * 100))%")
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(confidenceColor(confidence))
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.7...: return .green
        case 0.5...: return .orange
        default: return .red
        }
    }

    // MARK: - Active Signals Card

    private func activeSignalsCard(result: PatternEmergenceResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Currently Active (\(result.activeComponents.count))")
                    .font(.headline)
                Spacer()

                if result.isEmerging {
                    Text("Pattern Emerging")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .cornerRadius(8)
                }
            }

            ForEach(result.activeComponents, id: \.componentId) { active in
                if let component = SignatureComponent.component(for: active.signal) {
                    HStack {
                        Circle()
                            .fill(signalStrengthColor(active.detectedValue))
                            .frame(width: 8, height: 8)

                        Text(component.displayName)
                            .font(.subheadline)

                        Spacer()

                        Text("\(Int(active.detectedValue * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if active.daysActive > 1 {
                            Text("\(active.daysActive)d")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func signalStrengthColor(_ value: Double) -> Color {
        switch value {
        case 0.8...: return .red
        case 0.6...: return .orange
        default: return .yellow
        }
    }

    // MARK: - Signature Card

    private func signatureCard(signature: WarningSignature) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.clipboard.fill")
                    .foregroundStyle(.purple)
                Text("Your Signature (\(signature.components.count))")
                    .font(.headline)
                Spacer()
            }

            ForEach(SignatureComponentCategory.allCases, id: \.self) { category in
                let categoryComponents = signature.components.filter { weighted in
                    SignatureComponent.component(for: weighted.signal)?.category == category
                }

                if !categoryComponents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(category.displayName, systemImage: category.icon)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(categoryComponents, id: \.componentId) { weighted in
                            if let component = SignatureComponent.component(for: weighted.signal) {
                                signatureRow(component: component, weighted: weighted)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func signatureRow(component: SignatureComponent, weighted: WeightedComponent) -> some View {
        HStack {
            Circle()
                .fill(weightColor(weighted.weight))
                .frame(width: 8, height: 8)

            Text(component.displayName)
                .font(.subheadline)

            Spacer()

            // Weight indicator
            Text("×\(String(format: "%.1f", weighted.weight))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func weightColor(_ weight: Double) -> Color {
        switch weight {
        case 0.7...: return .purple
        case 0.4...: return .blue
        default: return .gray
        }
    }

    // MARK: - Accuracy Card

    private func accuracyCard(stats: SignatureAccuracyStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.green)
                Text("Prediction Accuracy")
                    .font(.headline)
                Spacer()
                Text("\(stats.accuracyPercentage)%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 16) {
                statPill(
                    value: stats.accuratePredictions,
                    label: "Accurate",
                    color: .green
                )
                statPill(
                    value: stats.helpedPrevent,
                    label: "Prevented",
                    color: .blue
                )
                statPill(
                    value: stats.falseAlarms,
                    label: "False",
                    color: .orange
                )
            }

            Text("Based on \(stats.totalAlerts) alerts with feedback")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func statPill(value: Int, label: String, color: Color) -> some View {
        VStack {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent Alerts Card

    private var recentAlertsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
                Text("Recent Alerts")
                    .font(.headline)
                Spacer()
            }

            ForEach(engine.activeAlerts.prefix(3)) { alert in
                NavigationLink(destination: PatternAlertView(alert: alert, engine: engine)) {
                    alertRow(alert)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func alertRow(_ alert: PatternAlert) -> some View {
        HStack {
            Circle()
                .fill(severityColor(alert.severity))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading) {
                Text(alert.severity.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(alert.detectedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if alert.userFeedback != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func severityColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                showingRelearn = true
            } label: {
                Label("Re-Learn from History", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showingOnboarding = true
            } label: {
                Label("Edit Warning Signs", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - No Signature View

    private var noSignatureView: some View {
        VStack(spacing: 24) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 60))
                .foregroundStyle(.purple.gradient)

            Text("Set Up Your Warning Signs")
                .font(.title2)
                .fontWeight(.bold)

            Text("Learn your unique patterns that appear before stress overwhelms you. This helps MindFriend alert you 24-72 hours before a crisis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingOnboarding = true
            } label: {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func refreshData() async {
        isRefreshing = true
        do {
            try await engine.startMonitoring()
        } catch {
            // Signature not initialized - that's OK
        }
        isRefreshing = false
    }
}

struct WarningSignsDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        let authService = SupabaseAuthService()
        let dataService = SupabaseDataService(authService: authService)
        return NavigationStack {
            WarningSignsDashboardView(
                engine: StressSignatureEngine(
                    supabaseDataService: dataService,
                    patternLearner: PatternLearner(supabaseDataService: dataService),
                    signalMonitor: SignalMonitor(supabaseDataService: dataService),
                    patternDetector: PatternDetector(supabaseDataService: dataService),
                    interventionService: EarlyInterventionService(supabaseDataService: dataService)
                )
            )
        }
    }
}
