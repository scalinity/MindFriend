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
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                    // Header
                    HStack {
                        Text(basis.shortLabel)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(SupportTheme.accent)
                        Spacer()
                    }

                    Text(basis.displayName)
                        .font(.headline)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(SupportTheme.Spacing.m)
                    } else if let info {
                        Text(info.description)
                            .font(.body)

                        if let source = info.source {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                Text("Source")
                                    .font(.caption)
                                    .foregroundColor(SupportTheme.textSecondary)
                                Text(source)
                                    .font(.caption)
                                    .italic()
                            }
                            .padding(SupportTheme.Spacing.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SupportTheme.separator)
                            .cornerRadius(SupportTheme.controlRadius)
                        }
                    }

                    // Therapist review note
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(SupportTheme.accent)
                        Text("Exercises using this methodology have been reviewed by mental health professionals.")
                            .font(.caption)
                    }
                    .padding(SupportTheme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)
                }
                .padding(SupportTheme.Spacing.m)
            }
            .supportScreen()
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
            Log.ui.error("Failed to load methodology info", error: error)
        }
    }
}

// MARK: - Preview

#Preview {
    MethodologyInfoSheet(basis: .CBT)
        .environmentObject(DependencyContainer.preview)
}
