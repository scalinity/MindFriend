import SwiftUI

/// Detail view for a connected therapist showing profile, access log, and actions
struct TherapistDetailView: View {
    let connection: TherapyConnection
    let therapyService: TherapyIntegrationService

    @State private var accessLog: [TherapyAccessLog] = []
    @State private var isLoadingLog = false
    @State private var showingDisconnectAlert = false
    @State private var showingSharingSettings = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Therapist Info Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.therapist?.displayName ?? "Therapist")
                                .font(.title2)
                                .fontWeight(.bold)

                            if let practiceName = connection.therapist?.practiceName {
                                Text(practiceName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if connection.therapist?.isVerified == true {
                            VStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                Text("Verified")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    if let specialties = connection.therapist?.specialties, !specialties.isEmpty {
                        HStack {
                            ForEach(specialties.prefix(3), id: \.self) { specialty in
                                Text(specialty)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(6)
                            }
                        }
                    }

                    if let connectedAt = connection.connectedAt {
                        Text("Connected since \(connectedAt, format: .dateTime.month().day().year())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Sharing Status
            Section("Sharing Settings") {
                NavigationLink {
                    SharingSettingsView(connection: connection, therapyService: therapyService)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        if !connection.sharedDataTypes.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(connection.sharedDataTypes, id: \.self) { type in
                                    Text(type)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(6)
                                }
                            }
                        } else {
                            Text("No data sharing enabled")
                                .foregroundColor(.orange)
                        }

                        Text("Tap to manage what data is shared")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Access Log
            Section("Recent Activity") {
                if isLoadingLog {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if accessLog.isEmpty {
                    Text("No activity yet")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(accessLog.prefix(10)) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.formattedAction)
                                .font(.subheadline)

                            Text(log.formattedDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if accessLog.count > 10 {
                        Text("Showing 10 of \(accessLog.count) events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Actions
            Section {
                Button(role: .destructive) {
                    showingDisconnectAlert = true
                } label: {
                    Label("Disconnect", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        }
        .navigationTitle("Therapist Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAccessLog()
        }
        .alert("Disconnect from Therapist?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task {
                    await disconnectTherapist()
                }
            }
        } message: {
            Text("Your therapist will immediately lose access to all shared data. Active assignments will remain visible but no new ones can be created.")
        }
    }

    private func loadAccessLog() async {
        isLoadingLog = true
        defer { isLoadingLog = false }

        do {
            accessLog = try await therapyService.getAccessLog(connectionId: connection.id)
        } catch {
            print("Failed to load access log: \(error)")
        }
    }

    private func disconnectTherapist() async {
        do {
            try await therapyService.revokeConnection(connectionId: connection.id)
            dismiss()
        } catch {
            print("Failed to disconnect: \(error)")
        }
    }
}
