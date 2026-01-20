import SwiftUI

/// Main view showing list of connected therapists with quick actions
struct ConnectedTherapistsView: View {
    @StateObject private var viewModel: ConnectedTherapistsViewModel
    @Environment(\.dismiss) private var dismiss

    init(therapyService: TherapyIntegrationService) {
        _viewModel = StateObject(wrappedValue: ConnectedTherapistsViewModel(therapyService: therapyService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading connections...")
                } else if viewModel.connections.isEmpty {
                    emptyStateView
                } else {
                    connectionsList
                }
            }
            .navigationTitle("My Therapists")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showingInviteSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingInviteSheet) {
                InviteTherapistView(therapyService: viewModel.therapyService)
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .task {
                await viewModel.loadConnections()
            }
            .refreshable {
                await viewModel.loadConnections()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.badge.gearshape")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Therapists Connected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Connect with your therapist to share your wellness progress securely.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                viewModel.showingInviteSheet = true
            } label: {
                Label("Invite a Therapist", systemImage: "envelope")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
        }
    }

    private var connectionsList: some View {
        List {
            // Active connections
            if !viewModel.activeConnections.isEmpty {
                Section("Connected Providers") {
                    ForEach(viewModel.activeConnections) { connection in
                        NavigationLink {
                            TherapistDetailView(
                                connection: connection,
                                therapyService: viewModel.therapyService
                            )
                        } label: {
                            ConnectionRow(connection: connection)
                        }
                    }
                }
            }

            // Pending connections
            if !viewModel.pendingConnections.isEmpty {
                Section("Pending Invites") {
                    ForEach(viewModel.pendingConnections) { connection in
                        PendingConnectionRow(
                            connection: connection,
                            onCancel: {
                                Task {
                                    await viewModel.revokeConnection(connection.id)
                                }
                            }
                        )
                    }
                }
            }

            // Revoked/ended connections
            if !viewModel.revokedConnections.isEmpty {
                Section("Previous Connections") {
                    ForEach(viewModel.revokedConnections) { connection in
                        RevokedConnectionRow(connection: connection)
                    }
                }
            }

            // Invite button at bottom
            Section {
                Button {
                    viewModel.showingInviteSheet = true
                } label: {
                    Label("Invite Another Therapist", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            }
        }
    }
}

// MARK: - Connection Row Components

struct ConnectionRow: View {
    let connection: TherapyConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.therapist?.displayName ?? "Therapist")
                        .font(.headline)

                    if let practiceName = connection.therapist?.practiceName {
                        Text(practiceName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if connection.therapist?.isVerified == true {
                        Label("Verified", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            // Sharing status
            if !connection.sharedDataTypes.isEmpty {
                HStack(spacing: 8) {
                    Text("Sharing:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(connection.sharedDataTypes, id: \.self) { type in
                        Text(type)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(6)
                    }
                }
            } else {
                Text("No data sharing enabled")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PendingConnectionRow: View {
    let connection: TherapyConnection
    let onCancel: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.therapist?.displayName ?? "Therapist")
                    .font(.headline)

                Text("Invitation pending...")
                    .font(.subheadline)
                    .foregroundColor(.orange)

                if let expiresAt = connection.invitationExpiresAt {
                    Text("Expires \(expiresAt, format: .dateTime.month().day())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button("Cancel", role: .destructive, action: onCancel)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct RevokedConnectionRow: View {
    let connection: TherapyConnection

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.therapist?.displayName ?? "Therapist")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text(connection.status.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let endedAt = connection.endedAt {
                    Text("Ended \(endedAt, format: .dateTime.month().day().year())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View Model

@MainActor
class ConnectedTherapistsViewModel: ObservableObject {
    let therapyService: TherapyIntegrationService

    @Published var connections: [TherapyConnection] = []
    @Published var isLoading = false
    @Published var showingError = false
    @Published var errorMessage: String?
    @Published var showingInviteSheet = false

    init(therapyService: TherapyIntegrationService) {
        self.therapyService = therapyService
    }

    var activeConnections: [TherapyConnection] {
        connections.filter { $0.status == .active }
    }

    var pendingConnections: [TherapyConnection] {
        connections.filter { $0.status == .pending }
    }

    var revokedConnections: [TherapyConnection] {
        connections.filter { $0.status == .revoked || $0.status == .ended }
    }

    func loadConnections() async {
        isLoading = true
        defer { isLoading = false }

        do {
            connections = try await therapyService.getConnections()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    func revokeConnection(_ connectionId: UUID) async {
        do {
            try await therapyService.revokeConnection(connectionId: connectionId)
            await loadConnections() // Refresh list
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Previews

#Preview {
    ConnectedTherapistsView(
        therapyService: TherapyIntegrationService(
            supabase: .init(
                supabaseURL: URL(string: "https://example.supabase.co")!,
                supabaseKey: "test"
            )
        )
    )
}
