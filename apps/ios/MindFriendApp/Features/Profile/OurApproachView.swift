import SwiftUI

/// A view explaining MindFriend's evidence-based approach to wellness
struct OurApproachView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var methodologies: [MethodologyInfo] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Evidence-Based Wellness")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Every exercise in MindFriend is rooted in research-backed therapeutic approaches.")
                        .foregroundColor(.secondary)
                }

                // Review process
                VStack(alignment: .leading, spacing: 12) {
                    Label("Professional Review", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text("Our exercises are reviewed by licensed mental health professionals to ensure they're safe, effective, and appropriate for self-guided use.")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)

                // Methodologies section
                Text("Therapeutic Approaches")
                    .font(.headline)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if methodologies.isEmpty {
                    Text("Unable to load methodology information.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(methodologies) { method in
                        MethodologyCard(methodology: method)
                    }
                }

                // Disclaimer
                VStack(alignment: .leading, spacing: 8) {
                    Label("Important Note", systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("MindFriend is not a replacement for professional mental health care. If you're experiencing a crisis or need clinical support, please contact a mental health professional.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding()
        }
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
            print("[OurApproachView] Failed to load methodologies: \(error)")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(methodology.code)
                    .font(.headline)
                    .foregroundColor(evidenceBasis?.color ?? .gray)
                Text("•")
                    .foregroundColor(.secondary)
                Text(methodology.name)
                    .font(.subheadline)
            }
            Text(methodology.description)
                .font(.caption)
                .foregroundColor(.secondary)

            if let source = methodology.source {
                Text("Source: \(source)")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
                    .italic()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OurApproachView()
            .environmentObject(DependencyContainer.preview)
    }
}
