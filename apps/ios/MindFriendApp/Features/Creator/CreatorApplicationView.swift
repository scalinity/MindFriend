// CreatorApplicationView.swift
// Application form for becoming a content creator

import SwiftUI
import PhotosUI

struct CreatorApplicationView: View {
    @ObservedObject var creatorService: CreatorService
    @Environment(\.dismiss) var dismiss

    @State private var fullName = ""
    @State private var email = ""
    @State private var location = ""
    @State private var professionalBackground = ""
    @State private var teachingPhilosophy = ""
    @State private var experienceYears: Int = 0

    // License information
    @State private var selectedLicenseType: LicenseType = .other
    @State private var licenseNumber = ""
    @State private var licenseState = ""
    @State private var certifications: [Certification] = []

    // Specialties and approach
    @State private var selectedSpecialties: Set<Specialty> = []
    @State private var selectedApproaches: Set<TherapeuticApproach> = []

    // Credentials
    @State private var portfolioLinks: [String] = [""]
    @State private var sampleContentUrls: [String] = [""]
    @State private var credentialDocuments: [PhotosPickerItem] = []

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                // Personal Information Section
                Section("Personal Information") {
                    TextField("Full Name", text: $fullName)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Location (City, State/Province)", text: $location)
                }

                // Professional Background Section
                Section("Professional Background") {
                    TextEditor(text: $professionalBackground)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if professionalBackground.isEmpty {
                                    Text("Describe your professional background, credentials, and experience...")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                }
                            },
                            alignment: .topLeading
                        )

                    Picker("Years of Experience", selection: $experienceYears) {
                        Text("0-2 years").tag(0)
                        Text("3-5 years").tag(3)
                        Text("6-10 years").tag(6)
                        Text("10+ years").tag(10)
                    }
                }

                // License Information Section
                Section("License Information") {
                    Picker("License Type", selection: $selectedLicenseType) {
                        ForEach(LicenseType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    if selectedLicenseType.requiresLicenseNumber {
                        TextField("License Number", text: $licenseNumber)
                            .textInputAutocapitalization(.characters)
                        TextField("State/Province of Licensing", text: $licenseState)
                    }
                }

                // Certifications Section
                Section("Certifications") {
                    ForEach($certifications) { $cert in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Certification Name", text: $cert.name)
                            TextField("Issuing Organization", text: $cert.issuer)
                            TextField("Year Obtained", text: $cert.yearObtained)
                                .keyboardType(.numberPad)
                        }
                    }
                    .onDelete { indexSet in
                        certifications.remove(atOffsets: indexSet)
                    }

                    Button("Add Certification") {
                        certifications.append(Certification())
                    }
                }

                // Specialties Section
                Section("Specialties") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                        ForEach(Specialty.allCases) { specialty in
                            SpecialtyToggle(
                                specialty: specialty,
                                isSelected: selectedSpecialties.contains(specialty)
                            ) {
                                if selectedSpecialties.contains(specialty) {
                                    selectedSpecialties.remove(specialty)
                                } else {
                                    selectedSpecialties.insert(specialty)
                                }
                            }
                        }
                    }
                }

                // Therapeutic Approaches Section
                Section("Therapeutic Approaches") {
                    ForEach(TherapeuticApproach.allCases) { approach in
                        Button {
                            if selectedApproaches.contains(approach) {
                                selectedApproaches.remove(approach)
                            } else {
                                selectedApproaches.insert(approach)
                            }
                        } label: {
                            HStack {
                                Text(approach.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedApproaches.contains(approach) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.gray)
                                }
                            }
                        }
                    }
                }

                // Teaching Philosophy Section
                Section("Teaching Philosophy") {
                    TextEditor(text: $teachingPhilosophy)
                        .frame(minHeight: 80)
                        .overlay(
                            Group {
                                if teachingPhilosophy.isEmpty {
                                    Text("Describe your teaching philosophy and approach to wellness...")
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                }
                            },
                            alignment: .topLeading
                        )
                }

                // Portfolio Section
                Section("Portfolio Links") {
                    ForEach($portfolioLinks.indices, id: \.self) { index in
                        TextField("Portfolio URL", text: $portfolioLinks[index])
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                    .onDelete { indexSet in
                        portfolioLinks.remove(atOffsets: indexSet)
                    }

                    Button("Add Link") {
                        portfolioLinks.append("")
                    }
                }

                // Sample Content Section
                Section("Sample Content") {
                    ForEach($sampleContentUrls.indices, id: \.self) { index in
                        TextField("Sample Content URL", text: $sampleContentUrls[index])
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                    .onDelete { indexSet in
                        sampleContentUrls.remove(atOffsets: indexSet)
                    }

                    Button("Add Sample") {
                        sampleContentUrls.append("")
                    }
                }

                // Credential Documents Upload Section
                Section("Verification Documents") {
                    PhotosPicker(
                        selection: $credentialDocuments,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Upload Credentials", systemImage: "doc.badge.plus")
                    }

                    if !credentialDocuments.isEmpty {
                        Text("\(credentialDocuments.count) file(s) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Upload copies of your professional licenses or certifications for verification.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Error Message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                // Submit Button
                Section {
                    Button(action: submitApplication) {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Application")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSubmitting || !isFormValid)
                }
            }
            .navigationTitle("Creator Application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Application Submitted", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your application has been submitted. We'll review it within 7 business days and send you an email with the outcome.")
            }
        }
    }

    private var isFormValid: Bool {
        !fullName.isEmpty &&
        !email.isEmpty &&
        email.contains("@") &&
        !professionalBackground.isEmpty &&
        professionalBackground.count >= 10
    }

    private func submitApplication() {
        isSubmitting = true
        errorMessage = nil

        let filteredPortfolio = portfolioLinks.filter { !$0.isEmpty }
        let filteredSamples = sampleContentUrls.filter { !$0.isEmpty }

        Task {
            do {
                // For now, we store the application data as JSON in a simple table
                // In production, this would call the submit-creator-application edge function
                let applicationData: [String: Any] = [
                    "full_name": fullName,
                    "email": email,
                    "location": location,
                    "professional_background": professionalBackground,
                    "teaching_philosophy": teachingPhilosophy,
                    "experience_years": experienceYears,
                    "license_type": selectedLicenseType.rawValue,
                    "license_number": licenseNumber,
                    "license_state": licenseState,
                    "certifications": certifications.map { ["name": $0.name, "issuer": $0.issuer, "year": $0.yearObtained] },
                    "specialties": Array(selectedSpecialties.map { $0.rawValue }),
                    "approaches": Array(selectedApproaches.map { $0.rawValue }),
                    "portfolio_links": filteredPortfolio,
                    "sample_content_urls": filteredSamples
                ]

                // Submit to creator_applications table
                let jsonData = try JSONSerialization.data(withJSONObject: applicationData)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

                try await creatorService.submitApplication(applicationData: jsonString)

                isSubmitting = false
                showingSuccess = true
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Specialty Toggle

struct SpecialtyToggle: View {
    let specialty: Specialty
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                Text(specialty.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .blue : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreatorApplicationView(creatorService: CreatorService(supabase: supabase))
}
