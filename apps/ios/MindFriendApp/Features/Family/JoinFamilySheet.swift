import SwiftUI

/// Sheet for joining an existing family via invite code
struct JoinFamilySheet: View {
    @EnvironmentObject private var container: DependencyContainer
    @Binding var isPresented: Bool

    @State private var inviteCode = ""
    @State private var nickname = ""
    @State private var birthDate: Date?
    @State private var showDatePicker = false
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Join Information") {
                TextField("Invite Code", text: $inviteCode)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                TextField("Your Nickname (optional)", text: $nickname)
                    .textContentType(.name)
            }

            Section("Birth Date (optional)") {
                Button(action: { showDatePicker.toggle() }) {
                    HStack {
                        Text("Birth Date")
                        Spacer()
                        if let birthDate = birthDate {
                            Text(birthDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not set")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if showDatePicker {
                    DatePicker(
                        "Select birth date",
                        selection: Binding(
                            get: { birthDate ?? Date() },
                            set: { birthDate = $0 }
                        ),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                }
            }

            Section("About Invite Codes") {
                Text("Ask your family admin for the invite code to join their family group. Your age will help determine which content is appropriate for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(action: joinFamily) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Join Family")
                    }
                }
                .disabled(inviteCode.isEmpty || isLoading)
            }
        }
        .dismissKeyboardOnSwipe()
        .onTapGesture {
            hideKeyboard()
        }
        .navigationTitle("Join Family")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { isPresented = false }
            }
        }
    }

    private func joinFamily() {
        isLoading = true
        error = nil

        Task {
            do {
                _ = try await container.familyService.joinFamily(
                    inviteCode: inviteCode,
                    nickname: nickname.isEmpty ? nil : nickname,
                    birthDate: birthDate
                )

                await MainActor.run {
                    isLoading = false
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        JoinFamilySheet(isPresented: .constant(true))
            .environmentObject(DependencyContainer.preview)
    }
}
