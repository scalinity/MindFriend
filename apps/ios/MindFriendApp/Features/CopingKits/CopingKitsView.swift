import SwiftUI

// MARK: - Coping Kits View (Home Card)

struct CopingKitsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: CopingKitsViewModel
    @State private var showingDetail = false
    @State private var selectedProgress: KitProgress?

    init(viewModel: CopingKitsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack {
                Label("Coping Kits", systemImage: "heart.circle.fill")
                    .font(.headline)
                    .foregroundStyle(SupportTheme.accent)

                Spacer()

                Button {
                    Task {
                        await viewModel.loadKits()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Refresh coping kits")
                .disabled(viewModel.isLoading)
            }

            if viewModel.showError {
                SupportUnavailableState(title: "Kits unavailable", message: viewModel.error?.localizedDescription ?? "Please try again.", actionTitle: "Try again") {
                    viewModel.dismissError()
                    Task { await viewModel.loadKits() }
                }
            }
            // Loading state
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.m)
            } else {
                // Active progress section
                if !viewModel.activeProgress.isEmpty {
                    activeProgressSection
                }

                // Quick kits grid
                quickKitsSection
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, y: 2)
        .sheet(isPresented: $showingDetail) {
            if let kit = viewModel.selectedKit {
                CopingKitDetailView(viewModel: viewModel, kit: kit)
            }
        }
        .onChange(of: selectedProgress) { oldValue, newValue in
            if let progress = newValue {
                Task {
                    await viewModel.resumeKit(progress)
                    await MainActor.run {
                        showingDetail = true
                        selectedProgress = nil
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showPremiumUpgrade) {
            PremiumUpgradeSheet()
        }
        .task {
            await viewModel.loadKits()
        }
    }

    // MARK: - Active Progress Section

    private var activeProgressSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Continue where you left off")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            ForEach(viewModel.activeProgress) { progress in
                Button {
                    selectedProgress = progress
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(progress.kitTitle)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("\(progress.stepsRemaining) step\(progress.stepsRemaining == 1 ? "" : "s") remaining")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "play.fill")
                            .foregroundStyle(SupportTheme.accent)
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick Kits Section

    private var quickKitsSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: SupportTheme.Spacing.s) {
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
            VStack(spacing: SupportTheme.Spacing.xs) {
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
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(SupportTheme.textPrimary)

                // Duration
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(kit.formattedDuration)
                        .font(.caption2)
                }
                .foregroundStyle(SupportTheme.textSecondary)

                // Premium badge
                if kit.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SupportTheme.Spacing.s)
            .padding(.horizontal, SupportTheme.Spacing.xs)
            .background(SupportTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        }
        .buttonStyle(.plain)
    }

    private var iconBackgroundColor: Color {
        switch kit.contextTag {
        case .anxiety: return SupportTheme.accent.opacity(0.15)
        case .stress: return SupportTheme.accent.opacity(0.15)
        case .sadness: return SupportTheme.accent.opacity(0.15)
        case .sleep: return SupportTheme.accent.opacity(0.15)
        case .focus: return SupportTheme.accent.opacity(0.15)
        case .crisis: return .red.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch kit.contextTag {
        case .anxiety: return SupportTheme.accent
        case .stress: return SupportTheme.accent
        case .sadness: return SupportTheme.accent
        case .sleep: return SupportTheme.accent
        case .focus: return SupportTheme.accent
        case .crisis: return .red
        }
    }
}

// MARK: - Premium Upgrade Sheet

struct PremiumUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.l) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.accent)

                Text("Premium Kit")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Upgrade to Premium to access this coping kit and many more.")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)

                Spacer()

                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        // TODO: Trigger upgrade flow
                        dismiss()
                    } label: {
                        Text("Upgrade to Premium")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)

                    Button {
                        dismiss()
                    } label: {
                        Text("Maybe Later")
                            .fontWeight(.medium)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SupportTheme.textSecondary)
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                            .accessibilityLabel("Close")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        CopingKitsView(viewModel: CopingKitsViewModel.preview())
            .padding(SupportTheme.Spacing.m)
    }
    .background(SupportTheme.surface)
}
#endif
