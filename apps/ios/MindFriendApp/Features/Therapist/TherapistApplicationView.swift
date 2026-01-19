//
//  TherapistApplicationView.swift
//  MindFriendApp
//
//  Therapist/Coach Marketplace - Application Form
//

import SwiftUI

struct TherapistApplicationView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = TherapistApplicationViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // Profile Type Section
                Section {
                    Picker("I am a", selection: $viewModel.profileType) {
                        ForEach(TherapistProfileType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    Text(viewModel.profileType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Personal Info Section
                Section("Personal Information") {
                    TextField("Display Name", text: $viewModel.displayName)
                        .textContentType(.name)

                    VStack(alignment: .leading) {
                        Text("Bio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.bio)
                            .frame(minHeight: 100)
                    }

                    Text("\(viewModel.bio.count)/50 characters minimum")
                        .font(.caption)
                        .foregroundStyle(viewModel.bio.count >= 50 ? .secondary : .red)
                }

                // Credentials Section
                Section("Credentials") {
                    ForEach(viewModel.selectedCredentials, id: \.self) { credential in
                        HStack {
                            Text(credential)
                            Spacer()
                            Button {
                                viewModel.removeCredential(credential)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Menu {
                        ForEach(TherapistCredential.allCases.filter {
                            !viewModel.selectedCredentials.contains($0.rawValue)
                        }, id: \.self) { credential in
                            Button(credential.fullName) {
                                viewModel.addCredential(credential.rawValue)
                            }
                        }
                    } label: {
                        Label("Add Credential", systemImage: "plus.circle")
                    }
                }

                // Specialties Section
                Section("Specialties") {
                    ForEach(viewModel.selectedSpecialties, id: \.self) { specialty in
                        if let spec = TherapistSpecialty(rawValue: specialty) {
                            HStack {
                                Image(systemName: spec.icon)
                                Text(spec.displayName)
                                Spacer()
                                Button {
                                    viewModel.removeSpecialty(specialty)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    Menu {
                        ForEach(TherapistSpecialty.allCases.filter {
                            !viewModel.selectedSpecialties.contains($0.rawValue)
                        }, id: \.self) { specialty in
                            Button {
                                viewModel.addSpecialty(specialty.rawValue)
                            } label: {
                                Label(specialty.displayName, systemImage: specialty.icon)
                            }
                        }
                    } label: {
                        Label("Add Specialty", systemImage: "plus.circle")
                    }
                }

                // Therapeutic Approaches Section
                Section("Therapeutic Approaches (Optional)") {
                    ForEach(viewModel.selectedApproaches, id: \.self) { approach in
                        HStack {
                            Text(approach)
                            Spacer()
                            Button {
                                viewModel.removeApproach(approach)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    Menu {
                        ForEach(TherapeuticApproach.allCases.filter {
                            !viewModel.selectedApproaches.contains($0.rawValue)
                        }, id: \.self) { approach in
                            Button(approach.displayName) {
                                viewModel.addApproach(approach.rawValue)
                            }
                        }
                    } label: {
                        Label("Add Approach", systemImage: "plus.circle")
                    }
                }

                // License Section (for therapists)
                if viewModel.profileType == .therapist {
                    Section("License Information") {
                        TextField("License Number", text: $viewModel.licenseNumber)

                        Picker("License State", selection: $viewModel.licenseState) {
                            Text("Select State").tag("")
                            ForEach(USState.allCases, id: \.self) { state in
                                Text(state.fullName).tag(state.rawValue)
                            }
                        }
                    }
                }

                // Languages Section
                Section("Languages") {
                    ForEach(viewModel.languages, id: \.self) { language in
                        HStack {
                            Text(language)
                            Spacer()
                            if language != "English" {
                                Button {
                                    viewModel.removeLanguage(language)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    HStack {
                        TextField("Add language", text: $viewModel.newLanguage)
                        Button {
                            viewModel.addLanguage()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(viewModel.newLanguage.isEmpty)
                    }
                }

                // Rates Section
                Section("Session Rates (USD)") {
                    HStack {
                        Text("30 min")
                        Spacer()
                        TextField("Rate", text: $viewModel.rate30Min)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("45 min")
                        Spacer()
                        TextField("Rate", text: $viewModel.rate45Min)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("60 min")
                        Spacer()
                        TextField("Rate", text: $viewModel.rate60Min)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Text("Set at least one rate. Rates can be changed later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Submit Section
                Section {
                    Button {
                        Task {
                            await viewModel.submitApplication()
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Application")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSubmitting)
                } footer: {
                    Text("Your application will be reviewed by our team. You'll be notified once approved.")
                }
            }
            .navigationTitle("Become a Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                viewModel.therapistService = dependencies.therapistService
            }
            .alert("Application Submitted", isPresented: $viewModel.showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for applying! We'll review your application and get back to you within 5-7 business days.")
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class TherapistApplicationViewModel: ObservableObject {
    var therapistService: TherapistService?

    @Published var profileType: TherapistProfileType = .therapist
    @Published var displayName = ""
    @Published var bio = ""

    @Published var selectedCredentials: [String] = []
    @Published var selectedSpecialties: [String] = []
    @Published var selectedApproaches: [String] = []

    @Published var licenseNumber = ""
    @Published var licenseState = ""

    @Published var languages: [String] = ["English"]
    @Published var newLanguage = ""

    @Published var rate30Min = ""
    @Published var rate45Min = ""
    @Published var rate60Min = ""

    @Published var isSubmitting = false
    @Published var showSuccess = false
    @Published var showError = false
    @Published var errorMessage = ""

    var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        bio.count >= 50 &&
        !selectedCredentials.isEmpty &&
        !selectedSpecialties.isEmpty &&
        (profileType == .coach || (!licenseNumber.isEmpty && !licenseState.isEmpty)) &&
        hasAtLeastOneRate
    }

    private var hasAtLeastOneRate: Bool {
        !rate30Min.isEmpty || !rate45Min.isEmpty || !rate60Min.isEmpty
    }

    func addCredential(_ credential: String) {
        if !selectedCredentials.contains(credential) {
            selectedCredentials.append(credential)
        }
    }

    func removeCredential(_ credential: String) {
        selectedCredentials.removeAll { $0 == credential }
    }

    func addSpecialty(_ specialty: String) {
        if !selectedSpecialties.contains(specialty) {
            selectedSpecialties.append(specialty)
        }
    }

    func removeSpecialty(_ specialty: String) {
        selectedSpecialties.removeAll { $0 == specialty }
    }

    func addApproach(_ approach: String) {
        if !selectedApproaches.contains(approach) {
            selectedApproaches.append(approach)
        }
    }

    func removeApproach(_ approach: String) {
        selectedApproaches.removeAll { $0 == approach }
    }

    func addLanguage() {
        let trimmed = newLanguage.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !languages.contains(trimmed) {
            languages.append(trimmed)
            newLanguage = ""
        }
    }

    func removeLanguage(_ language: String) {
        languages.removeAll { $0 == language }
    }

    func submitApplication() async {
        guard let service = therapistService, isValid else { return }

        isSubmitting = true

        let input = TherapistApplicationInput(
            profileType: profileType.rawValue,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            bio: bio,
            credentials: selectedCredentials,
            specialties: selectedSpecialties,
            approaches: selectedApproaches.isEmpty ? nil : selectedApproaches,
            languages: languages,
            licenseNumber: licenseNumber.isEmpty ? nil : licenseNumber,
            licenseState: licenseState.isEmpty ? nil : licenseState,
            rate30Min: Decimal(string: rate30Min),
            rate45Min: Decimal(string: rate45Min),
            rate60Min: Decimal(string: rate60Min)
        )

        do {
            _ = try await service.submitApplication(input)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSubmitting = false
    }
}

#Preview {
    TherapistApplicationView()
        .environmentObject(DependencyContainer.preview)
}
