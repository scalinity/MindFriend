import SwiftUI

struct PathwayOnboardingFlow: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    let pathway: TransitionPathway

    @State private var transitionDate = Date()
    @State private var specificContext = ""
    @State private var goals: [String] = [""]
    @State private var isEnrolling = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("About Your Transition")) {
                    DatePicker("When did this begin?", selection: $transitionDate, displayedComponents: .date)

                    TextField("Tell us more (optional)", text: $specificContext, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(header: Text("Your Goals")) {
                    ForEach(goals.indices, id: \.self) { index in
                        TextField("Goal \(index + 1)", text: $goals[index])
                    }
                    Button("Add Goal") {
                        goals.append("")
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(pathway.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Begin Journey") {
                        Task { await enrollInPathway() }
                    }
                    .disabled(isEnrolling)
                }
            }
        }
    }

    func enrollInPathway() async {
        isEnrolling = true
        errorMessage = nil

        let personalization = PathwayPersonalization(
            transitionDate: transitionDate,
            specificContext: specificContext.isEmpty ? nil : specificContext,
            supportPeople: nil,
            goals: goals.filter { !$0.isEmpty }
        )

        do {
            _ = try await container.transitionService.enrollPathway(
                key: pathway.key,
                personalization: personalization
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isEnrolling = false
    }
}
