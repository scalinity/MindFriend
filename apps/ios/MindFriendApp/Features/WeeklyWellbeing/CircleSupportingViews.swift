import SwiftUI

// MARK: - Circle Template Editor View

struct CircleTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editorVM = CircleTemplateEditorViewModel()
    @ObservedObject var viewModel: CircleHabitsViewModel

    @State private var showingQuestionPicker = false

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                Section("Template Info") {
                    TextField("Template Name", text: $editorVM.name)

                    TextField("Description (optional)", text: $editorVM.description, axis: .vertical)
                        .lineLimit(2...4)
                }

                // Questions
                Section {
                    ForEach(Array(editorVM.questions.enumerated()), id: \.offset) { index, question in
                        HStack {
                            Image(systemName: question.promptType.icon)
                                .foregroundStyle(.blue)

                            Text(question.questionText)
                                .font(.subheadline)

                            Spacer()

                            if question.isRequired {
                                Text("Required")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        Button(role: .destructive) {
                            editorVM.removeQuestion(at: index)
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.caption)
                        }
                    }

                    Button {
                        showingQuestionPicker = true
                    } label: {
                        Label("Add Question", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Questions")
                } footer: {
                    Text("Add questions to gather insights from your circle")
                }

                // Reminder schedule
                Section("Reminder Schedule") {
                    Toggle("Active", isOn: $editorVM.isActive)

                    DatePicker(
                        "Reminder Time",
                        selection: .constant(Date()),
                        displayedComponents: .hourAndMinute
                    )

                    dayPicker
                }

                // Preview
                if !editorVM.questions.isEmpty {
                    Section("Preview") {
                        ForEach(editorVM.questions) { question in
                            HStack {
                                Image(systemName: question.promptType.icon)
                                    .foregroundStyle(.secondary)
                                Text(question.questionText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveTemplate()
                        dismiss()
                    }
                    .disabled(!editorVM.isValid)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingQuestionPicker) {
                QuestionTypePicker { type in
                    editorVM.addQuestion(type)
                }
            }
        }
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminder Days")
                .font(.subheadline)

            HStack {
                ForEach(1...7, id: \.self) { day in
                    Button {
                        if editorVM.reminderDays.contains(day) {
                            editorVM.reminderDays.remove(day)
                        } else {
                            editorVM.reminderDays.insert(day)
                        }
                    } label: {
                        Text(dayAbbreviation(day))
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(editorVM.reminderDays.contains(day) ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundStyle(editorVM.reminderDays.contains(day) ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private func dayAbbreviation(_ day: Int) -> String {
        // Convert 1-based day (1-7) to 0-based index (0-6)
        let symbols = Self.dayFormatter.shortWeekdaySymbols
        return String(symbols?[((day - 1) % 7)].prefix(2) ?? "")
    }

    private func saveTemplate() {
        let _ = CircleTemplate(
            id: UUID(),
            circleId: UUID(), // Will be set by backend
            name: editorVM.name,
            description: editorVM.description.isEmpty ? nil : editorVM.description,
            questions: editorVM.questions.enumerated().map { index, input in
                TemplateQuestion(
                    id: UUID(),
                    questionText: input.questionText,
                    promptType: input.promptType,
                    order: input.order,
                    isRequired: input.isRequired
                )
            },
            reminderDays: Array(editorVM.reminderDays).sorted(),
            reminderTime: editorVM.reminderTime,
            isActive: editorVM.isActive,
            createdAt: Date()
        )

        // This would be called with the actual container
        Task {
            // await viewModel.createTemplate(template, container: container)
        }
    }
}

// MARK: - Question Type Picker

struct QuestionTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (QuestionPromptType) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(QuestionPromptType.allCases, id: \.self) { type in
                    Button {
                        onSelect(type)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 30)

                            VStack(alignment: .leading) {
                                Text(type.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text("Add a \(type.displayName.lowercased()) question")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Question Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Circle Recap View

struct CircleRecapView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CircleHabitsViewModel

    @State private var selectedCircleId: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Circle selector
                    circleSelector

                    // Recap content
                    if let recap = currentRecap {
                        recapContent(recap)
                    } else {
                        emptyRecapState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weekly Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var circleSelector: some View {
        Picker("Circle", selection: $selectedCircleId) {
            Text("All Circles").tag(nil as UUID?)
            // Add circle options here
        }
        .pickerStyle(.menu)
    }

    private var currentRecap: CircleRecap? {
        guard let circleId = selectedCircleId else {
            return viewModel.recaps.first
        }
        return viewModel.recaps.first { $0.circleId == circleId }
    }

    private func recapContent(_ recap: CircleRecap) -> some View {
        VStack(spacing: 20) {
            // Stats card
            statsCard(recap)

            // Member participation
            memberParticipationSection(recap)

            // Highlights
            if !recap.sharedHighlights.isEmpty {
                highlightsSection(recap)
            }

            // Streak status
            streakStatusCard(recap.streakStatus)
        }
    }

    private func statsCard(_ recap: CircleRecap) -> some View {
        HStack(spacing: 20) {
            statItem(value: "\(recap.totalCheckins)", label: "Check-ins")

            Divider()
                .frame(height: 40)

            statItem(value: "\(recap.memberParticipations.count)", label: "Members Active")

            Divider()
                .frame(height: 40)

            statItem(
                value: "\(recap.memberParticipations.filter { $0.wasActive }.count)",
                label: "Participated"
            )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func memberParticipationSection(_ recap: CircleRecap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Member Activity")
                .font(.headline)

            ForEach(recap.memberParticipations) { member in
                HStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(member.memberName.prefix(1)))
                                .font(.headline)
                        )

                    VStack(alignment: .leading) {
                        Text(member.memberName)
                            .font(.subheadline)

                        Text("\(member.checkinsCompleted) check-ins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if member.wasActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func highlightsSection(_ recap: CircleRecap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Circle Highlights")
                .font(.headline)

            ForEach(recap.sharedHighlights) { highlight in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: highlightIcon(highlight.type))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlight.memberName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(highlight.content)
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func streakStatusCard(_ status: StreakStatus) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)

                Text("Your Streak")
                    .font(.headline)

                Spacer()

                Text("\(status.currentStreak) days")
                    .font(.title3)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyRecapState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Recap Available")
                .font(.headline)

            Text("Complete check-ins with your circle to generate weekly recaps")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    private func highlightIcon(_ type: HighlightType) -> String {
        switch type {
        case .gratitude: return "heart.fill"
        case .win: return "star.fill"
        case .intention: return "target"
        case .reflection: return "mirror"
        case .mood: return "face.smiling"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Template Editor") {
    CircleTemplateEditorView(viewModel: .preview)
}

#Preview("Recap") {
    CircleRecapView(viewModel: .preview)
}
#endif
