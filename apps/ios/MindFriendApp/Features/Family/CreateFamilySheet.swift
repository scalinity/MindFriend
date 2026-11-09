import SwiftUI

/// Sheet for creating a new family group
struct CreateFamilySheet: View {
    @EnvironmentObject private var container: DependencyContainer
    @Binding var isPresented: Bool

    @State private var familyName = ""
    @State private var childAgeFilter = "18"
    @State private var maxMembers = "6"
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Family Information") {
                TextField("Family Name", text: $familyName)
                    .supportField()
                    .textContentType(.givenName)
            }
            .listRowBackground(SupportTheme.surface)

            Section("Settings") {
                Picker("Default Content Age Filter", selection: $childAgeFilter) {
                    Text("4+").tag("4")
                    Text("6+").tag("6")
                    Text("13+").tag("13")
                    Text("18+").tag("18")
                }

                Picker("Maximum Members", selection: $maxMembers) {
                    ForEach(2...10, id: \.self) { count in
                        Text("\(count)").tag(String(count))
                    }
                }
            }
            .listRowBackground(SupportTheme.surface)

            Section("About Family Groups") {
                Text("Family groups let you:")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    + Text("\n • View family members' wellness progress\n • Create shared challenges\n • Do together sessions\n • Receive alerts about family members")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .listRowBackground(SupportTheme.surface)

            Section {
                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(action: createFamily) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Create Family")
                    }
                }
                .buttonStyle(.supportPrimary)
                .disabled(familyName.isEmpty || isLoading)
            }
            .listRowBackground(SupportTheme.surface)
        }
        .dismissKeyboardOnSwipe()
        .onTapGesture {
            hideKeyboard()
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportSheet()
        .navigationTitle("Create Family")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { isPresented = false }
            }
        }
    }

    private func createFamily() {
        isLoading = true
        error = nil

        Task {
            do {
                let ageFilter = Int(childAgeFilter) ?? 18
                let maxMembersCount = Int(maxMembers) ?? 6

                _ = try await container.familyService.createFamily(
                    name: familyName,
                    defaultChildAgeFilter: ageFilter,
                    maxMembers: maxMembersCount
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
        CreateFamilySheet(isPresented: .constant(true))
            .environmentObject(DependencyContainer.preview)
    }
}
