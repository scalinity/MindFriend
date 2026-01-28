//
//  LanguageSettingsView.swift
//  MindFriendApp
//
//  Created by dev-pipeline on 2026-01-19.
//  UI for selecting app language
//

import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject var localization: LocalizationService
    @Environment(\.dismiss) var dismiss

    @State private var availableLanguages: [SupportedLanguage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showRestartAlert = false
    @State private var selectedLanguageName = ""

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            } else {
                Section {
                    ForEach(availableLanguages) { language in
                        LanguageRow(
                            language: language,
                            isSelected: language.code == localization.currentLanguage,
                            onSelect: {
                                Task {
                                    await selectLanguage(language)
                                }
                            }
                        )
                        .disabled(isSaving)
                    }
                }

                Section {
                    Text("Some content may not be available in all languages. We're always adding more!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("App Language")
        .task {
            await loadLanguages()
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                localization.forceLanguageRestart()
            }
            Button("Later", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("To fully apply \(selectedLanguageName), the app needs to restart. Restart now?")
        }
    }

    private func loadLanguages() async {
        do {
            availableLanguages = try await localization.fetchAvailableLanguages()
            isLoading = false
        } catch {
            errorMessage = "Unable to load languages. Please try again."
            isLoading = false
        }
    }

    private func selectLanguage(_ language: SupportedLanguage) async {
        guard language.code != localization.currentLanguage else { return }

        // Store the name before async call
        let languageName = language.nativeName
        
        isSaving = true
        do {
            let languageChanged = try await localization.setLanguage(language.code)
            
            await MainActor.run {
                isSaving = false
                
                if languageChanged {
                    // Show restart prompt
                    selectedLanguageName = languageName
                    showRestartAlert = true
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Unable to change language. Please try again."
                isSaving = false
            }
        }
    }
}

struct LanguageRow: View {
    let language: SupportedLanguage
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.nativeName)
                        .font(.body)
                        .foregroundColor(.primary)

                    if language.translationCoverage < 100 {
                        Text("\(Int(language.translationCoverage))% translated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("100% translated")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LanguageSettingsView()
            .environmentObject(LocalizationService.shared)
    }
}
