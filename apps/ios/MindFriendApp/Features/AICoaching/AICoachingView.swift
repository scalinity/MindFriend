import SwiftUI

// MARK: - AI Coaching Mode Selection View

struct AICoachingView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = AICoachingViewModel()

    @State private var showingThoughtRecords = false
    @State private var showingPreferences = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Mode Selection
                    modeSelectionSection

                    // Quick Actions
                    quickActionsSection

                    // Recent Thought Records
                    if !viewModel.recentThoughtRecords.isEmpty {
                        recentThoughtRecordsSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AI Coaching")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPreferences = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingThoughtRecords) {
                ThoughtRecordsListView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingPreferences) {
                CoachingPreferencesView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadData(container: container)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Welcome to AI Coaching")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a coaching mode to get started with personalized guidance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    // MARK: - Mode Selection Section

    private var modeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Mode")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(ConversationMode.allCases) { mode in
                ModeCard(mode: mode, isActive: viewModel.currentMode == mode) {
                    Task {
                        await viewModel.selectMode(mode, container: container)
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                QuickActionCard(
                    title: "Thought Records",
                    icon: "note.text",
                    color: .orange
                ) {
                    showingThoughtRecords = true
                }

                QuickActionCard(
                    title: "Suggested Quests",
                    icon: "star",
                    color: .yellow
                ) {
                    // Navigate to suggested quests
                }
            }
        }
    }

    // MARK: - Recent Thought Records Section

    private var recentThoughtRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Thought Records")
                    .font(.headline)

                Spacer()

                Button("See All") {
                    showingThoughtRecords = true
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 4)

            ForEach(viewModel.recentThoughtRecords.prefix(2)) { record in
                ThoughtRecordCard(record: record)
            }
        }
    }
}

// MARK: - Mode Card

struct ModeCard: View {
    let mode: ConversationMode
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundStyle(colorForMode(mode))
                    .frame(width: 48, height: 48)
                    .background(colorForMode(mode).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(mode.shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Active indicator or chevron
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(isActive ? Color.green.opacity(0.1) : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isActive ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func colorForMode(_ mode: ConversationMode) -> Color {
        switch mode {
        case .supportive: return .green
        case .challenging: return .red
        case .socratic: return .indigo
        case .empathetic: return .pink
        case .reflect: return .purple
        case .plan: return .blue
        case .reframe: return .orange
        }
    }
}

// MARK: - Quick Action Card

struct QuickActionCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thought Record Card

struct ThoughtRecordCard: View {
    let record: ThoughtRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let event = record.activatingEvent ?? ""
                Text(event.prefix(50) + (event.count > 50 ? "..." : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if record.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                ForEach(record.cognitiveDistortions.prefix(2)) { distortion in
                    Text(distortion.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(record.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AICoachingView()
        .environmentObject(DependencyContainer.preview)
}
#endif
