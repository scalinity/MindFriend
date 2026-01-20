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
            Text("This will permanently delete all vault entries and create a new encryption key. This action cannot be undone.")
        }
        .onDisappear {
            // Lock vault when leaving the view
            viewModel.lock()
        }
    }

    // MARK: - Locked State View

    private var lockedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Private Vault")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Your entries are encrypted and stored only on this device. They are never synced or used by AI.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
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
                    .foregroundStyle(.secondary)
                TextField("Search entries", text: $viewModel.searchText)
                    .textFieldStyle(.plain)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)

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
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: viewModel.searchText.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(viewModel.searchText.isEmpty ? "No entries yet" : "No matching entries")
                .font(.headline)

            Text(viewModel.searchText.isEmpty
                 ? "Tap + to create your first private journal entry"
                 : "Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.searchText.isEmpty {
                Button {
                    selectedEntry = nil
                    showingEditor = true
                } label: {
                    Label("Create Entry", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Key Missing State

    private var keyMissingView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Encryption Key Not Found")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your vault entries cannot be recovered because the encryption key is missing. This may happen if you removed your device passcode or restored from a backup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                showingResetConfirmation = true
            } label: {
                Text("Reset Vault")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Unavailable State

    private func unavailableView(reason: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Vault Unavailable")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}

// MARK: - Entry Row

struct VaultEntryRow: View {
    let entry: VaultEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.displayTitle)
                .font(.headline)
                .lineLimit(1)

            if entry.title != nil && !entry.body.isEmpty {
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(entry.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.displayTitle), updated \(entry.updatedAt.formatted())")
    }
}

#Preview {
    NavigationStack {
        VaultListView()
    }
}
