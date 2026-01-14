import SwiftUI

/// A sheet that displays detailed information about a therapeutic methodology
struct MethodologyInfoSheet: View {
    let basis: EvidenceBasis

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var container: DependencyContainer
    @State private var info: MethodologyInfo?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Text(basis.shortLabel)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(basis.color)
                        Spacer()
                    }

                    Text(basis.displayName)
                        .font(.headline)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if let info {
                        Text(info.description)
                            .font(.body)

                        if let source = info.source {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Source")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(source)
                                    .font(.caption)
                                    .italic()
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }

                    // Therapist review note
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Exercises using this methodology have been reviewed by mental health professionals.")
                            .font(.caption)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("About This Method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await loadInfo()
        }
    }

    private func loadInfo() async {
        isLoading = true
        defer { isLoading = false }

        do {
            info = try await container.supabaseDataService.getMethodologyInfo(code: basis.rawValue)
        } catch {
            // Info is optional - we can still show basic info from the enum
            print("[MethodologyInfoSheet] Failed to load methodology info: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    MethodologyInfoSheet(basis: .CBT)
        .environmentObject(DependencyContainer.preview)
}
