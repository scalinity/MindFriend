import SwiftUI

/// A view explaining MindFriend's evidence-based approach to wellness
struct OurApproachView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var methodologies: [MethodologyInfo] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                // Header
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Evidence-Based Wellness")
                        .font(.title)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)

                    Text("Every exercise in MindFriend is rooted in research-backed therapeutic approaches.")
                        .foregroundColor(SupportTheme.textSecondary)
                }

                // Review process
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label("Professional Review", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundColor(SupportTheme.accent)

                    Text(
                        "Our exercises are reviewed by licensed mental health professionals to ensure they're safe, effective, and appropriate for self-guided use."
                    )
                    .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SupportTheme.surface)
                .cornerRadius(SupportTheme.controlRadius)

                // Methodologies section
                Text("Therapeutic Approaches")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if methodologies.isEmpty {
                    Text("Unable to load methodology information.")
                        .foregroundColor(SupportTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(methodologies) { method in
                        MethodologyCard(methodology: method)
                    }
                }

                // Disclaimer
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Label("Important Note", systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)

                    Text(
                        "MindFriend is not a replacement for professional mental health care. If you're experiencing a crisis or need clinical support, please contact a mental health professional."
                    )
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
                }
                .padding()
                .background(SupportTheme.field)
                .cornerRadius(SupportTheme.controlRadius)
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Our Approach")
        .task {
            await loadMethodologies()
        }
    }

    private func loadMethodologies() async {
        isLoading = true
        defer { isLoading = false }

        do {
            methodologies = try await container.supabaseDataService.getAllMethodologies()
        } catch {
            Log.ui.error("Failed to load methodologies", error: error)
            methodologies = []
        }
    }
}

/// A card displaying a single methodology
private struct MethodologyCard: View {
    let methodology: MethodologyInfo

    private var evidenceBasis: EvidenceBasis? {
        EvidenceBasis(rawValue: methodology.code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Text(methodology.code)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundColor(SupportTheme.accent)
                Text("•")
                    .foregroundColor(SupportTheme.textSecondary)
                Text(methodology.name)
                    .font(.subheadline)
            }
            Text(methodology.description)
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)

            if let source = methodology.source {
                Text("Source: \(source)")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .italic()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.field)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OurApproachView()
            .environmentObject(DependencyContainer.preview)
    }
}
