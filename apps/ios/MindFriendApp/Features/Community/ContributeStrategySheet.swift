import SwiftUI
import Supabase

/// Sheet for contributing a new coping strategy
struct ContributeStrategySheet: View {
    @EnvironmentObject private var wisdomService: WisdomService
    @Environment(\.dismiss) private var dismiss

    var preselectedCategory: StrategyCategory?

    @State private var selectedCategory: StrategyCategory = .general
    @State private var strategyText = ""
    @State private var context = ""
    @State private var isSubmitting = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?

    private let maxStrategyLength = 500
    private let maxContextLength = 200

    var body: some View {
        NavigationStack {
            Form {
                // Category Section
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(StrategyCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.iconName)
                                .tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Category")
                } footer: {
                    Text("Choose the emotion or situation this strategy helps with.")
                }

                // Strategy Section
                Section {
                    TextEditor(text: $strategyText)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if strategyText.isEmpty {
                                Text("Share a coping strategy that helps you...")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    HStack {
                        Text("Your Strategy")
                        Spacer()
                        Text("\(strategyText.count)/\(maxStrategyLength)")
                            .font(.caption)
                            .foregroundColor(strategyText.count > maxStrategyLength ? .red : .secondary)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tips for a good strategy:")
                        Text("• Be specific and actionable")
                        Text("• Focus on what worked for you")
                        Text("• Don't include personal details")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Context Section (Optional)
                Section {
                    TextField("e.g., \"When I'm feeling overwhelmed at work\"", text: $context)
                } header: {
                    HStack {
                        Text("Context (Optional)")
                        Spacer()
                        Text("\(context.count)/\(maxContextLength)")
                            .font(.caption)
                            .foregroundColor(context.count > maxContextLength ? .red : .secondary)
                    }
                } footer: {
                    Text("Add context to help others understand when this strategy works best.")
                }

                // Privacy Notice
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.title2)
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Anonymous Contribution")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Your strategy will be reviewed before publishing. Your identity is never attached.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Error Message
                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Share Strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        submitStrategy()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit || isSubmitting)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView("Submitting...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear {
                if let category = preselectedCategory {
                    selectedCategory = category
                }
            }
            .alert("Strategy Submitted", isPresented: $showingSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Thank you for sharing! Your strategy will be reviewed and published soon.")
            }
        }
    }

    private var canSubmit: Bool {
        !strategyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        strategyText.count >= 20 &&
        strategyText.count <= maxStrategyLength &&
        context.count <= maxContextLength
    }

    private func submitStrategy() {
        errorMessage = nil
        isSubmitting = true

        Task {
            do {
                try await wisdomService.submitStrategy(
                    category: selectedCategory,
                    strategyText: strategyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    context: context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : context.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                isSubmitting = false
                showingSuccess = true
            } catch let error as WisdomError {
                isSubmitting = false
                errorMessage = error.localizedDescription
            } catch {
                isSubmitting = false
                errorMessage = "Failed to submit. Please try again."
            }
        }
    }
}

#Preview {
    ContributeStrategySheet()
        .environmentObject(WisdomService(supabase: DependencyContainer.shared.supabaseClient))
}
