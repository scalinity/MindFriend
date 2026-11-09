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

                        .supportField()
                        .lineLimit(2...4)
                }
                .listRowBackground(SupportTheme.surface)

                // Questions
                Section {
                    ForEach(Array(editorVM.questions.enumerated()), id: \.offset) { index, question in
                        HStack {
                            Image(systemName: question.promptType.icon)
                                .foregroundStyle(SupportTheme.accent)

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
                .listRowBackground(SupportTheme.surface)

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
                .listRowBackground(SupportTheme.surface)

                // Preview
                if !editorVM.questions.isEmpty {
                    Section("Preview") {
                        ForEach(editorVM.questions) { question in
                            HStack {
                                Image(systemName: question.promptType.icon)
                                    .foregroundStyle(SupportTheme.textSecondary)
                                Text(question.questionText)
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(SupportTheme.surface)
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
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
                            .padding(.horizontal, SupportTheme.Spacing.s)
                            .padding(.vertical, SupportTheme.Spacing.xs)
                            .background(editorVM.reminderDays.contains(day) ? SupportTheme.accent : SupportTheme.textSecondary.opacity(0.2))
                            .foregroundStyle(editorVM.reminderDays.contains(day) ? SupportTheme.textPrimary : SupportTheme.textPrimary)
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
                                .foregroundStyle(SupportTheme.accent)
                                .frame(width: 30)

                            VStack(alignment: .leading) {
                                Text(type.displayName)
                                    .font(.headline)
                                    .foregroundStyle(SupportTheme.textPrimary)

                                Text("Add a \(type.displayName.lowercased()) question")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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
                VStack(spacing: SupportTheme.Spacing.l) {
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
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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
        VStack(spacing: SupportTheme.Spacing.l) {
            // Stats card
            statsCard(recap)

            // Member participation
            memberParticipationSection(recap)

            // Highlights
            if !recap.sharedHighlights.isEmpty {
                highlightsSection(recap)
            }

        }
    }

    private func statsCard(_ recap: CircleRecap) -> some View {
        HStack(spacing: SupportTheme.Spacing.l) {
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
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    private func memberParticipationSection(_ recap: CircleRecap) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Member Activity")
                .font(.headline)

            ForEach(recap.memberParticipations) { member in
                HStack {
                    Circle()
                        .fill(SupportTheme.textSecondary.opacity(0.3))
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
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    if member.wasActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SupportTheme.accent)
                    }
                }
            }
        }
        .padding()
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    private func highlightsSection(_ recap: CircleRecap) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Circle Highlights")
                .font(.headline)

            ForEach(recap.sharedHighlights) { highlight in
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    Image(systemName: highlightIcon(highlight.type))
                        .foregroundStyle(SupportTheme.accent)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(highlight.memberName)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)

                        Text(highlight.content)
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
        }
    }



    private var emptyRecapState: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No Recap Available")
                .font(.headline)

            Text("Complete check-ins with your circle to generate weekly recaps")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
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
