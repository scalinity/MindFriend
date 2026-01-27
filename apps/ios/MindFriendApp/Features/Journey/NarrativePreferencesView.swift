import SwiftUI
import Supabase

/// Preferences view for customizing narrative generation
struct NarrativePreferencesView: View {
    @StateObject private var viewModel: NarrativePreferencesViewModel
    @Environment(\.dismiss) private var dismiss

    init(dataService: SupabaseDataService) {
        _viewModel = StateObject(wrappedValue: NarrativePreferencesViewModel(dataService: dataService))
    }

    var body: some View {
        Form {
            // Tone Section
            Section {
                Picker("Tone", selection: Binding(
                    get: { viewModel.currentTone },
                    set: { newTone in
                        Task {
                            await viewModel.updatePreferences(tone: newTone)
                        }
                    }
                )) {
                    ForEach(NarrativePreferences.ToneOption.allCases, id: \.self) { tone in
                        VStack(alignment: .leading) {
                            Text(tone.displayName)
                            Text(tone.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(tone)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Writing Style")
            } footer: {
                Text("Choose how your weekly stories are written. This will apply to future stories.")
            }

            // Length Section
            Section {
                Picker("Length", selection: Binding(
                    get: { viewModel.currentLength },
                    set: { newLength in
                        Task {
                            await viewModel.updatePreferences(length: newLength)
                        }
                    }
                )) {
                    ForEach(NarrativePreferences.LengthOption.allCases, id: \.self) { length in
                        VStack(alignment: .leading) {
                            Text(length.displayName)
                            Text(length.cardCountRange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(length)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Story Length")
            } footer: {
                Text("Control how detailed your weekly stories are.")
            }

            // Metrics Section
            Section {
                Toggle("Include Metrics", isOn: Binding(
                    get: { viewModel.currentIncludeMetrics },
                    set: { newValue in
                        Task {
                            await viewModel.updatePreferences(includeMetrics: newValue)
                        }
                    }
                ))
            } header: {
                Text("Data Display")
            } footer: {
                Text("Show specific numbers like mood scores and quest completion percentages in your stories.")
            }

            // Reset Section
            Section {
                Button(role: .destructive) {
                    Task {
                        await viewModel.resetToDefaults()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Reset to Defaults")
                        Spacer()
                    }
                }
                .disabled(viewModel.isSaving)
            } footer: {
                Text("Reset all preferences to warm tone, standard length, and metrics included.")
            }

            // Status Section
            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Story Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await viewModel.loadPreferences()
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showSuccessToast {
                successToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: viewModel.showSuccessToast)
            }
        }
    }

    // MARK: - Success Toast

    private var successToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("Preferences saved")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding()
    }
}

#Preview {
    NavigationStack {
        NarrativePreferencesViewPreview()
    }
}

private struct NarrativePreferencesViewPreview: View {
    var body: some View {
        NarrativePreferencesView(dataService: createMockDataService())
    }

    private func createMockDataService() -> SupabaseDataService {
        return SupabaseDataService(authService: DependencyContainer.preview.supabaseAuthService)
    }
}
