import Foundation
import SwiftUI
import LocalAuthentication

/// ViewModel for the Private Vault feature.
/// Manages vault state, authentication, and CRUD operations.
@MainActor
final class VaultViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var entries: [VaultEntry] = []
    @Published var searchText: String = ""
    @Published private(set) var state: VaultState = .locked
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // MARK: - Dependencies

    private let storageService: VaultStoring
    private let authService: VaultAuthenticating
    private let encryptionService: VaultEncrypting

    // MARK: - Initialization

    init(
        storageService: VaultStoring,
        authService: VaultAuthenticating,
        encryptionService: VaultEncrypting
    ) {
        self.storageService = storageService
        self.authService = authService
        self.encryptionService = encryptionService
    }

    // MARK: - Computed Properties

    /// Filtered entries based on search text
    var filteredEntries: [VaultEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { entry in
            (entry.title?.lowercased().contains(query) ?? false) ||
            entry.body.lowercased().contains(query)
        }
    }

    /// Whether the vault is currently unlocked
    var isUnlocked: Bool {
        state == .unlocked
    }

    /// Whether biometric authentication is available
    var isBiometricAvailable: Bool {
        authService.isBiometricAvailable()
    }

    /// The type of biometric authentication available
    var biometricType: LABiometryType {
        authService.biometricType()
    }

    /// Label for the biometric authentication button
    var biometricLabel: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometrics"
        }
    }

    /// System image name for the biometric type
    var biometricIconName: String {
        switch biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "lock.shield"
        }
    }

    /// Whether the vault has any entries
    var hasEntries: Bool {
        !entries.isEmpty
    }

    /// Number of entries in the vault
    var entryCount: Int {
        entries.count
    }

    // MARK: - Actions

    /// Attempts to unlock the vault with biometric authentication
    func unlock() async {
        guard state == .locked else { return }

        do {
            let authenticated = try await authService.authenticate(
                reason: "Unlock your private vault"
            )

            if authenticated {
                // Check if encryption key exists
                let keyExists = await encryptionService.keyExists()
                if keyExists {
                    state = .unlocked
                    await loadEntries()
                } else {
                    // First time: generate key
                    try await encryptionService.generateKey()
                    state = .unlocked
                    await loadEntries()
                }
            }
        } catch let error as VaultError {
            if error == .keyNotFound {
                state = .keyMissing
            }
            showError(error.errorDescription ?? "Authentication failed")
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Locks the vault and clears sensitive data from memory
    func lock() {
        state = .locked
        entries = []
        searchText = ""
    }

    /// Loads all entries from storage
    func loadEntries() async {
        guard isUnlocked else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await storageService.listEntries()
        } catch let error as VaultError {
            showError(error.errorDescription ?? "Failed to load entries")
        } catch {
            showError("Failed to load entries: \(error.localizedDescription)")
        }
    }

    /// Creates a new vault entry
    func createEntry(title: String?, body: String) async -> Bool {
        guard isUnlocked else {
            showError(VaultError.vaultLocked.errorDescription!)
            return false
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            showError(VaultError.emptyBody.errorDescription!)
            return false
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = VaultEntry(
            title: trimmedTitle?.isEmpty == true ? nil : trimmedTitle,
            body: trimmedBody
        )

        do {
            try await storageService.saveEntry(entry)
            await loadEntries()
            return true
        } catch let error as VaultError {
            showError(error.errorDescription ?? "Failed to save entry")
            return false
        } catch {
            showError("Failed to save entry: \(error.localizedDescription)")
            return false
        }
    }

    /// Updates an existing vault entry
    func updateEntry(_ entry: VaultEntry, title: String?, body: String) async -> Bool {
        guard isUnlocked else {
            showError(VaultError.vaultLocked.errorDescription!)
            return false
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            showError(VaultError.emptyBody.errorDescription!)
            return false
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = entry
        updated.title = trimmedTitle?.isEmpty == true ? nil : trimmedTitle
        updated.body = trimmedBody
        updated.updatedAt = Date()

        do {
            try await storageService.saveEntry(updated)
            await loadEntries()
            return true
        } catch let error as VaultError {
            showError(error.errorDescription ?? "Failed to update entry")
            return false
        } catch {
            showError("Failed to update entry: \(error.localizedDescription)")
            return false
        }
    }

    /// Deletes a vault entry
    func deleteEntry(_ id: UUID) async {
        guard isUnlocked else {
            showError(VaultError.vaultLocked.errorDescription!)
            return
        }

        do {
            try await storageService.deleteEntry(id)
            await loadEntries()
        } catch let error as VaultError {
            showError(error.errorDescription ?? "Failed to delete entry")
        } catch {
            showError("Failed to delete entry: \(error.localizedDescription)")
        }
    }

    /// Resets the vault: deletes all entries and regenerates the encryption key
    func resetVault() async {
        do {
            // Delete all entries first
            try await storageService.deleteAllEntries()

            // Delete and regenerate the encryption key
            try await encryptionService.deleteKey()
            try await encryptionService.generateKey()

            // Clear state
            entries = []
            searchText = ""
            state = .unlocked
        } catch let error as VaultError {
            showError(error.errorDescription ?? "Failed to reset vault")
        } catch {
            showError("Failed to reset vault: \(error.localizedDescription)")
        }
    }

    /// Checks the current vault state without unlocking
    func checkVaultState() async {
        let keyExists = await encryptionService.keyExists()
        if !keyExists && state == .unlocked {
            state = .keyMissing
        }
    }

    /// Clears the current error
    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
