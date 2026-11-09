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
            VStack(spacing: SupportTheme.Spacing.m) {
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
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle(SupportDestination.warningSigns.title)
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
        VStack(spacing: SupportTheme.Spacing.s) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Pattern Confidence")
                        .font(.headline)
                .accessibilityAddTraits(.isHeader)
                    Text("How well your signature predicts crises")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                Spacer()
                confidenceBadge(confidence: signature.confidence)
            }

            // Confidence gauge
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.separator)

                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(confidenceColor(signature.confidence))
                        .frame(width: geometry.size.width * signature.confidence)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Source: \(signature.source.displayName)")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
                Spacer()
                if let lastLearned = signature.lastLearnedAt {
                    Text("Updated \(lastLearned, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .supportCard()
    }

    private func confidenceBadge(confidence: Double) -> some View {
        Text("\(Int(confidence * 100))%")
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(confidenceColor(confidence))
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.7...: return SupportTheme.accent
        case 0.5...: return SupportTheme.accent
        default: return .red
        }
    }

    // MARK: - Active Signals Card

    private func activeSignalsCard(result: PatternEmergenceResult) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SupportTheme.accent)
                Text("Currently Active (\(result.activeComponents.count))")
                    .font(.headline)
                Spacer()

                if result.isEmerging {
                    Text("Pattern Emerging")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.surface)
                        .foregroundStyle(SupportTheme.accent)
                        .cornerRadius(SupportTheme.controlRadius)
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
                            .foregroundStyle(SupportTheme.textSecondary)

                        if active.daysActive > 1 {
                            Text("\(active.daysActive)d")
                                .font(.caption2)
                                .padding(.horizontal, SupportTheme.Spacing.xxs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.separator)
                                .cornerRadius(SupportTheme.controlRadius)
                        }
                    }
                }
            }
        }
        .supportCard()
    }

    private func signalStrengthColor(_ value: Double) -> Color {
        switch value {
        case 0.8...: return .red
        case 0.6...: return SupportTheme.accent
        default: return SupportTheme.accent
        }
    }

    // MARK: - Signature Card

    private func signatureCard(signature: WarningSignature) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "list.clipboard.fill")
                    .foregroundStyle(SupportTheme.accent)
                Text("Your Signature (\(signature.components.count))")
                    .font(.headline)
                Spacer()
            }

            ForEach(SignatureComponentCategory.allCases, id: \.self) { category in
                let categoryComponents = signature.components.filter { weighted in
                    SignatureComponent.component(for: weighted.signal)?.category == category
                }

                if !categoryComponents.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Label(category.displayName, systemImage: category.icon)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(SupportTheme.textSecondary)

                        ForEach(categoryComponents, id: \.componentId) { weighted in
                            if let component = SignatureComponent.component(for: weighted.signal) {
                                signatureRow(component: component, weighted: weighted)
                            }
                        }
                    }
                }
            }
        }
        .supportCard()
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
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    private func weightColor(_ weight: Double) -> Color {
        switch weight {
        case 0.7...: return SupportTheme.accent
        case 0.4...: return SupportTheme.accent
        default: return SupportTheme.accent
        }
    }

    // MARK: - Accuracy Card

    private func accuracyCard(stats: SignatureAccuracyStats) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(SupportTheme.accent)
                Text("Prediction Accuracy")
                    .font(.headline)
                Spacer()
                Text("\(stats.accuracyPercentage)%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(SupportTheme.accent)
            }

            HStack(spacing: SupportTheme.Spacing.m) {
                statPill(
                    value: stats.accuratePredictions,
                    label: "Accurate",
                    color: SupportTheme.accent
                )
                statPill(
                    value: stats.helpedPrevent,
                    label: "Prevented",
                    color: SupportTheme.accent
                )
                statPill(
                    value: stats.falseAlarms,
                    label: "False",
                    color: SupportTheme.accent
                )
            }

            Text("Based on \(stats.totalAlerts) alerts with feedback")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
    }

    private func statPill(value: Int, label: String, color: Color) -> some View {
        VStack {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent Alerts Card

    private var recentAlertsCard: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(SupportTheme.accent)
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
        .supportCard()
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
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            if alert.userFeedback != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SupportTheme.accent)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
    }

    private func severityColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .mild: return SupportTheme.accent
        case .moderate: return SupportTheme.accent
        case .severe: return .red
        }
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Button {
                showingRelearn = true
            } label: {
                Label("Re-Learn from History", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportSecondary)

            Button {
                showingOnboarding = true
            } label: {
                Label("Edit Warning Signs", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportSecondary)
        }
        .supportCard()
    }

    // MARK: - No Signature View

    private var noSignatureView: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Image(systemName: "shield.checkered")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.accent)

            Text("Set Up Your Warning Signs")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.bold)

            Text("Learn your unique patterns that appear before stress overwhelms you. This helps MindFriend alert you 24-72 hours before a crisis.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showingOnboarding = true
            } label: {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
        }
        .padding(SupportTheme.Spacing.m)
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
