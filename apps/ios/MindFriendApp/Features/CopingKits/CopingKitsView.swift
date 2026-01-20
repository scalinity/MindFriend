import SwiftUI

// MARK: - Coping Kits View (Home Card)

struct CopingKitsView: View {
    @StateObject private var viewModel: CopingKitsViewModel
    @State private var showingDetail = false
    @State private var selectedProgress: KitProgress?

    init(viewModel: CopingKitsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Coping Kits", systemImage: "heart.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.pink)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadKits()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .disabled(viewModel.isLoading)
            }

            // Loading state
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                // Active progress section
                if !viewModel.activeProgress.isEmpty {
                    activeProgressSection
                }

                // Quick kits grid
                quickKitsSection
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .sheet(isPresented: $showingDetail) {
            if let kit = viewModel.selectedKit {
                CopingKitDetailView(viewModel: viewModel, kit: kit)
            }
        }
        .sheet(item: $selectedProgress) { progress in
            Task {
                await viewModel.resumeKit(progress)
                await MainActor.run {
                    showingDetail = true
                }
            }
        }
        .sheet(isPresented: $viewModel.showPremiumUpgrade) {
            PremiumUpgradeSheet()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.error?.localizedDescription ?? "An error occurred")
        }
        .task {
            await viewModel.loadKits()
        }
    }

    // MARK: - Active Progress Section

    private var activeProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue where you left off")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(viewModel.activeProgress) { progress in
                Button {
                    selectedProgress = progress
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(progress.kitTitle)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("\(progress.stepsRemaining) step\(progress.stepsRemaining == 1 ? "" : "s") remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "play.fill")
                            .foregroundStyle(.pink)
                    }
                    .padding(12)
                    .background(Color.pink.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick Kits Section

    private var quickKitsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(viewModel.availableKits.prefix(6)) { kit in
                CopingKitCard(kit: kit, onTap: {
                    viewModel.selectKit(kit)
                    showingDetail = true
                })
            }
        }
    }
}

// MARK: - Coping Kit Card

struct CopingKitCard: View {
    let kit: CopingKit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 44, height: 44)

                    Image(systemName: kit.contextIcon)
                        .font(.title3)
                        .foregroundStyle(iconColor)
                }

                // Title
                Text(kit.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // Duration
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(kit.formattedDuration)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                // Premium badge
                if kit.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var iconBackgroundColor: Color {
        switch kit.contextTag {
        case .anxiety: return .orange.opacity(0.15)
        case .stress: return .yellow.opacity(0.15)
        case .sadness: return .blue.opacity(0.15)
        case .sleep: return .indigo.opacity(0.15)
        case .focus: return .green.opacity(0.15)
        case .crisis: return .red.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch kit.contextTag {
        case .anxiety: return .orange
        case .stress: return .yellow
        case .sadness: return .blue
        case .sleep: return .indigo
        case .focus: return .green
        case .crisis: return .red
        }
    }
}

// MARK: - Premium Upgrade Sheet

struct PremiumUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow)

                Text("Premium Kit")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Upgrade to Premium to access this coping kit and many more.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        // TODO: Trigger upgrade flow
                        dismiss()
                    } label: {
                        Text("Upgrade to Premium")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.pink)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Maybe Later")
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        CopingKitsView(viewModel: CopingKitsViewModel.preview())
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
