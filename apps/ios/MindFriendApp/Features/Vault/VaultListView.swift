import SwiftUI

/// Main view for the Private Vault feature.
/// Shows locked state, entry list with search, and navigation to editor.
struct VaultListView: View {
    @EnvironmentObject private var viewModel: VaultViewModel
    @State private var showingEditor = false
    @State private var selectedEntry: VaultEntry?
    @State private var showingResetConfirmation = false

    var body: some View {
        Group {
            switch viewModel.state {
            case .locked:
                lockedView
            case .unlocked:
                unlockedView
            case .keyMissing:
                keyMissingView
            case .unavailable(let reason):
                unavailableView(reason: reason)
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Private Vault")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.isUnlocked {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedEntry = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create new entry")
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.lock()
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .accessibilityLabel("Lock vault")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            VaultEntryEditorView(entry: selectedEntry)
                .environmentObject(viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .alert("Reset Vault?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await viewModel.resetVault()
                }
            }
        } message: {
            Text(
                "This will permanently delete all vault entries and create a new encryption key. This action cannot be undone."
            )
        }
        .onDisappear {
            // Lock vault when leaving the view
            viewModel.lock()
        }
    }

    // MARK: - Locked State View

    private var lockedView: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(SupportTheme.accent)
                .accessibilityHidden(true)

            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Private Vault")
                    .font(.title)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)

                Text("Your entries are encrypted and stored only on this device. They are never synced or used by AI.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            Button {
                Task {
                    await viewModel.unlock()
                }
            } label: {
                Label("Unlock with \(viewModel.biometricLabel)", systemImage: viewModel.biometricIconName)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SupportTheme.accent)
                    .foregroundStyle(SupportTheme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }
            .padding(.horizontal, SupportTheme.Spacing.xl)
            .accessibilityHint("Authenticate to access your private vault entries")

            Spacer()
        }
    }

    // MARK: - Unlocked State View

    private var unlockedView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SupportTheme.textSecondary)
                TextField("Search entries", text: $viewModel.searchText)
                    .textFieldStyle(.plain)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(SupportTheme.Spacing.s)
            .background(SupportTheme.field)
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            .padding(.horizontal)
            .padding(.vertical, SupportTheme.Spacing.xs)

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if viewModel.filteredEntries.isEmpty {
                emptyStateView
            } else {
                entryListView
            }
        }
    }

    // MARK: - Entry List

    private var entryListView: some View {
        List {
            ForEach(viewModel.filteredEntries) { entry in
                Button {
                    selectedEntry = entry
                    showingEditor = true
                } label: {
                    VaultEntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Tap to edit this entry")
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let entry = viewModel.filteredEntries[index]
                    Task {
                        await viewModel.deleteEntry(entry.id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadEntries()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Spacer()

            Image(systemName: viewModel.searchText.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)

            Text(viewModel.searchText.isEmpty ? "No entries yet" : "No matching entries")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(
                viewModel.searchText.isEmpty
                    ? "Tap + to create your first private journal entry"
                    : "Try a different search term"
            )
            .font(.subheadline)
            .foregroundStyle(SupportTheme.textSecondary)
            .multilineTextAlignment(.center)

            if viewModel.searchText.isEmpty {
                Button {
                    selectedEntry = nil
                    showingEditor = true
                } label: {
                    Label("Create Entry", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, SupportTheme.Spacing.l)
                        .padding(.vertical, SupportTheme.Spacing.s)
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }
                .padding(.top, SupportTheme.Spacing.xs)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Key Missing State

    private var keyMissingView: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.accent)
                .accessibilityHidden(true)

            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Encryption Key Not Found")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)

                Text(
                    "Your vault entries cannot be recovered because the encryption key is missing. This may happen if you removed your device passcode or restored from a backup."
                )
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            Button {
                showingResetConfirmation = true
            } label: {
                Text("Reset Vault")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SupportTheme.accent)
                    .foregroundStyle(SupportTheme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }
            .padding(.horizontal, SupportTheme.Spacing.xl)

            Spacer()
        }
    }

    // MARK: - Unavailable State

    private func unavailableView(reason: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            Image(systemName: "lock.slash")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.textSecondary)
                .accessibilityHidden(true)

            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Vault Unavailable")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)

                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            Spacer()
        }
    }
}

// MARK: - Entry Row

struct VaultEntryRow: View {
    let entry: VaultEntry

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(entry.displayTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)

            if entry.title != nil && !entry.body.isEmpty {
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)
            }

            Text(entry.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.displayTitle), updated \(entry.updatedAt.formatted())")
    }
}

#Preview {
    NavigationStack {
        VaultListView()
    }
}
