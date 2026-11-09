import SwiftUI

/// Visual indicator displaying user's current capacity level
struct CapacityIndicator: View {
    @EnvironmentObject var difficultyService: DifficultyService
    @State private var showDetailSheet = false

    var body: some View {
        Button {
            showDetailSheet = true
        } label: {
            HStack(spacing: SupportTheme.Spacing.s) {
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 4)
                        .frame(width: 44, height: 44)

                    if let capacity = difficultyService.currentCapacity {
                        Circle()
                            .trim(from: 0, to: CGFloat(capacity.score) / 100)
                            .stroke(SupportTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: capacity.level.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(SupportTheme.accent)
                    } else if difficultyService.isCalculating {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "circle.grid.2x2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }

                // Label (with Dynamic Type support)
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    if let capacity = difficultyService.currentCapacity {
                        Text(capacity.level.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(SupportTheme.textPrimary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                        if capacity.hasOverride {
                            Text("Manual override")
                                .font(.caption2)
                                .foregroundColor(SupportTheme.textSecondary)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        } else if capacity.isStale {
                            Text("Updated \(timeAgo(capacity.calculatedAt))")
                                .font(.caption2)
                                .foregroundColor(SupportTheme.textSecondary)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        }
                    } else if difficultyService.isCalculating {
                        Text("Calculating...")
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    } else {
                        Text("Tap to calculate")
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.s)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
            .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .frame(minHeight: SupportTheme.minimumTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view detailed capacity breakdown")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showDetailSheet) {
            CapacityDetailSheet()
                .environmentObject(difficultyService)
        }
        .task {
            // Auto-refresh on appear if cache expired
            if difficultyService.getCachedCapacity() == nil {
                _ = try? await difficultyService.refreshCapacity()
            }
        }
    }

    private var accessibilityLabel: String {
        if let capacity = difficultyService.currentCapacity {
            var label = "Capacity: \(capacity.level.displayName), score \(capacity.score) out of 100"
            if capacity.hasOverride {
                label += ", manual override active"
            } else if capacity.isStale {
                label += ", last updated \(timeAgo(capacity.calculatedAt))"
            }
            return label
        } else if difficultyService.isCalculating {
            return "Calculating capacity"
        } else {
            return "Capacity not calculated, tap to calculate"
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval / 3600)
        if hours < 1 {
            return "just now"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else {
            return "\(hours / 24)d ago"
        }
    }
}

/// Detail sheet showing capacity breakdown
struct CapacityDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var difficultyService: DifficultyService
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    if let capacity = difficultyService.currentCapacity {
                        // Overall score
                        VStack(spacing: SupportTheme.Spacing.xs) {
                            ZStack {
                                Circle()
                                    .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 12)
                                    .frame(width: 120, height: 120)

                                Circle()
                                    .trim(from: 0, to: CGFloat(capacity.score) / 100)
                                    .stroke(SupportTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .frame(width: 120, height: 120)
                                    .rotationEffect(.degrees(-90))

                                VStack(spacing: SupportTheme.Spacing.xxs) {
                                    Text("\(capacity.score)")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(SupportTheme.accent)
                                    Text("Capacity")
                                        .font(.caption)
                                        .foregroundColor(SupportTheme.textSecondary)
                                }
                            }

                            Text(capacity.level.displayName)
                                .font(.title3)
                                .accessibilityAddTraits(.isHeader)
                                .fontWeight(.semibold)

                            if capacity.hasOverride {
                                HStack(spacing: SupportTheme.Spacing.xxs) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.caption2)
                                    Text("Manual override active")
                                        .font(.caption)
                                }
                                .foregroundColor(SupportTheme.accent)
                                .padding(.horizontal, SupportTheme.Spacing.s)
                                .padding(.vertical, SupportTheme.Spacing.xs)
                                .background(SupportTheme.surface)
                                .cornerRadius(SupportTheme.controlRadius)
                            }
                        }

                        Divider()
                            .padding(.horizontal)

                        // Component breakdown
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                            Text("Capacity Breakdown")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.horizontal)

                            ForEach(capacity.components.all) { component in
                                ComponentRow(component: component)
                            }
                        }

                        Divider()
                            .padding(.horizontal)

                        // Adjust difficulty button
                        Button {
                            showSettings = true
                        } label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text("Adjust Difficulty")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(SupportTheme.accent)
                            .foregroundColor(SupportTheme.onAccent)
                            .cornerRadius(SupportTheme.controlRadius)
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: SupportTheme.Spacing.m) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 48))
                                .foregroundColor(SupportTheme.textSecondary)

                            Text("No capacity data")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            Text("Complete your daily check-in to calculate your capacity")
                                .font(.subheadline)
                                .foregroundColor(SupportTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, SupportTheme.Spacing.xl)

                            Button {
                                Task {
                                    do {
                                        _ = try await difficultyService.refreshCapacity()
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            } label: {
                                if difficultyService.isCalculating {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                } else {
                                    Text("Calculate Now")
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(SupportTheme.accent)
                                        .foregroundColor(SupportTheme.onAccent)
                                        .cornerRadius(SupportTheme.controlRadius)
                                }
                            }
                            .disabled(difficultyService.isCalculating)
                            .padding(.horizontal, SupportTheme.Spacing.xl)

                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, SupportTheme.Spacing.xl)
                            }
                        }
                        .padding(.top, SupportTheme.Spacing.xl)
                    }
                }
                .padding(.vertical)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Your Capacity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                DifficultySettingsView()
                    .environmentObject(difficultyService)
            }
            .alert("Calculation Error", isPresented: $showError) {
                Button("OK") {
                    showError = false
                }
            } message: {
                Text(errorMessage ?? "Failed to calculate capacity")
            }
        }
    }
}

/// Individual component row in breakdown
struct ComponentRow: View {
    let component: ComponentScore

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Image(systemName: component.type.icon)
                    .foregroundColor(SupportTheme.accent)
                    .frame(minWidth: 24)

                Text(component.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(component.score)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(SupportTheme.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(SupportTheme.textSecondary.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(SupportTheme.controlRadius)

                    Rectangle()
                        .fill(scoreColor(component.score))
                        .frame(width: geometry.size.width * CGFloat(component.score) / 100, height: 8)
                        .cornerRadius(SupportTheme.controlRadius)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(component.weight * 100))% weight")
                    .font(.caption2)
                    .foregroundColor(SupportTheme.textSecondary)

                Spacer()

                Text("+\(String(format: "%.1f", component.contribution)) pts")
                    .font(.caption2)
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .padding(.horizontal)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0...40:
            return SupportTheme.accent
        case 41...70:
            return SupportTheme.accent
        default:
            return SupportTheme.accent
        }
    }
}

#Preview {
    CapacityIndicator()
        .environmentObject(
            {
                let service = DifficultyService(supabase: supabase)
                return service
            }())
}
