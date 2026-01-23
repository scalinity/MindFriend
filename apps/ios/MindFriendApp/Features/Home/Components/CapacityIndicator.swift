import SwiftUI

/// Visual indicator displaying user's current capacity level
struct CapacityIndicator: View {
    @EnvironmentObject var difficultyService: DifficultyService
    @State private var showDetailSheet = false

    var body: some View {
        Button {
            showDetailSheet = true
        } label: {
            HStack(spacing: 12) {
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                        .frame(width: 44, height: 44)

                    if let capacity = difficultyService.currentCapacity {
                        Circle()
                            .trim(from: 0, to: CGFloat(capacity.score) / 100)
                            .stroke(capacity.level.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: capacity.level.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(capacity.level.color)
                    } else if difficultyService.isCalculating {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "circle.grid.2x2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }

                // Label (with Dynamic Type support)
                VStack(alignment: .leading, spacing: 2) {
                    if let capacity = difficultyService.currentCapacity {
                        Text(capacity.level.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                        if capacity.hasOverride {
                            Text("Manual override")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        } else if capacity.isStale {
                            Text("Updated \(timeAgo(capacity.calculatedAt))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        }
                    } else if difficultyService.isCalculating {
                        Text("Calculating...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    } else {
                        Text("Tap to calculate")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
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
                try? await difficultyService.refreshCapacity()
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
                VStack(spacing: 24) {
                    if let capacity = difficultyService.currentCapacity {
                        // Overall score
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                                    .frame(width: 120, height: 120)

                                Circle()
                                    .trim(from: 0, to: CGFloat(capacity.score) / 100)
                                    .stroke(capacity.level.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .frame(width: 120, height: 120)
                                    .rotationEffect(.degrees(-90))

                                VStack(spacing: 4) {
                                    Text("\(capacity.score)")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(capacity.level.color)
                                    Text("Capacity")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text(capacity.level.displayName)
                                .font(.title3)
                                .fontWeight(.semibold)

                            if capacity.hasOverride {
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.caption2)
                                    Text("Manual override active")
                                        .font(.caption)
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }

                        Divider()
                            .padding(.horizontal)

                        // Component breakdown
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Capacity Breakdown")
                                .font(.headline)
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
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)

                            Text("No capacity data")
                                .font(.headline)

                            Text("Complete your daily check-in to calculate your capacity")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

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
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            }
                            .disabled(difficultyService.isCalculating)
                            .padding(.horizontal, 32)

                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                        }
                        .padding(.top, 48)
                    }
                }
                .padding(.vertical)
            }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: component.type.icon)
                    .foregroundColor(.blue)
                    .frame(width: 24)

                Text(component.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(component.score)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)

                    Rectangle()
                        .fill(scoreColor(component.score))
                        .frame(width: geometry.size.width * CGFloat(component.score) / 100, height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(component.weight * 100))% weight")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("+\(String(format: "%.1f", component.contribution)) pts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 0...40:
            return .blue
        case 41...70:
            return .green
        default:
            return .orange
        }
    }
}

#Preview {
    CapacityIndicator()
        .environmentObject({
            let service = DifficultyService(supabase: supabase)
            return service
        }())
}
