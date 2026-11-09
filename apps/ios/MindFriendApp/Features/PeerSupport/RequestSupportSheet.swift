import SwiftUI
import Supabase

/// Sheet for requesting a peer support session
struct RequestSupportSheet: View {
    let service: PeerSupportService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: DBSupportSession.SessionType = .quick
    @State private var selectedTopics: Set<SupportTopic> = []
    @State private var mood: Double = 5
    @State private var notes = ""
    @State private var isAnonymous = false
    @State private var isRequesting = false
    @State private var matchResult: SupportMatchResponse?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Type of Support") {
                    Picker("Session Type", selection: $selectedType) {
                        Text("Quick Support").tag(DBSupportSession.SessionType.quick)
                        Text("Deep Conversation").tag(DBSupportSession.SessionType.deep)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Image(systemName: selectedType.icon)
                            .foregroundStyle(SupportTheme.accent)
                        Text("Estimated duration: \(selectedType.estimatedMinutes) minutes")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .padding(.top, SupportTheme.Spacing.xxs)
                }
                .listRowBackground(SupportTheme.surface)

                Section("What would you like to talk about?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: SupportTheme.Spacing.xs) {
                        ForEach(SupportTopic.allCases) { topic in
                            TopicChip(
                                topic: topic,
                                isSelected: selectedTopics.contains(topic)
                            ) {
                                if selectedTopics.contains(topic) {
                                    selectedTopics.remove(topic)
                                } else if selectedTopics.count < 3 {
                                    selectedTopics.insert(topic)
                                }
                            }
                        }
                    }

                    if selectedTopics.count == 3 {
                        Text("Maximum 3 topics selected")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .listRowBackground(SupportTheme.surface)

                Section {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        HStack {
                            Text("How are you feeling?")
                            Spacer()
                            Text("\(Int(mood))/10")
                                .font(.headline)
                                .foregroundStyle(moodColor)
                        }

                        Slider(value: $mood, in: 1...10, step: 1) {
                            Text("Mood")
                        }
                        .tint(moodColor)
                        .accessibilityLabel("Mood level")
                        .accessibilityValue("\(Int(mood)) out of 10")
                        .accessibilityHint("Slide to indicate how you're feeling, 1 is lowest and 10 is highest")
                    }
                } header: {
                    Text("Current Mood")
                }
                .listRowBackground(SupportTheme.surface)

                Section {
                    TextField("What's on your mind? (optional)", text: $notes, axis: .vertical)
                        .supportField()
                        .lineLimit(3...6)
                } header: {
                    Text("Additional Notes")
                } footer: {
                    Text("This helps the listener understand your situation better.")
                }
                .listRowBackground(SupportTheme.surface)

                Section {
                    Toggle(isOn: $isAnonymous) {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Keep me anonymous")
                            Text("Your profile will be hidden from the listener")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                }
                .listRowBackground(SupportTheme.surface)

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(SupportTheme.surface)
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportSheet()
            .navigationTitle("Request Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRequesting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Request") {
                        requestSupport()
                    }
                    .disabled(isRequesting || selectedTopics.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $matchResult) { result in
                MatchResultView(result: result) {
                    dismiss()
                }
            }
            .interactiveDismissDisabled(isRequesting)
        }
    }

    private var moodColor: Color {
        switch Int(mood) {
        case 1...3: return .red
        case 4...6: return SupportTheme.accent
        case 7...8: return SupportTheme.Celebration.gold
        case 9...10: return SupportTheme.accent
        default: return SupportTheme.textSecondary
        }
    }

    private func requestSupport() {
        isRequesting = true
        errorMessage = nil

        Task {
            do {
                let response = try await service.requestSupport(
                    sessionType: selectedType,
                    topics: Array(selectedTopics),
                    mood: Int(mood),
                    notes: notes.isEmpty ? nil : notes,
                    isAnonymous: isAnonymous
                )

                if response.success {
                    matchResult = response
                } else {
                    errorMessage = response.error ?? "Failed to request support"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isRequesting = false
        }
    }
}

// MARK: - Topic Chip

struct TopicChip: View {
    let topic: SupportTopic
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: topic.icon)
                    .font(.caption2)
                Text(topic.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(isSelected ? SupportTheme.accent : SupportTheme.textSecondary.opacity(0.2))
            .foregroundStyle(isSelected ? SupportTheme.textPrimary : SupportTheme.textPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topic.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Match Result View

struct MatchResultView: View {
    let result: SupportMatchResponse
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            if result.status == "matched" {
                matchedContent
            } else {
                queuedContent
            }

            Spacer()

            Button(result.status == "matched" ? "Start Session" : "Got It") {
                dismiss()
                onDismiss()
            }
            .buttonStyle(.supportPrimary)
            .controlSize(.large)
        }
        .padding()
        .presentationDetents([.medium])
    }

    private var matchedContent: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.accent)
                .accessibilityHidden(true)

            Text("Matched!")
                .font(.title.bold())

            if let listener = result.listener {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text(listener.displayName ?? "A Listener")
                        .font(.headline)

                    if let rating = listener.rating, rating > 0 {
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(SupportTheme.Celebration.gold)
                            Text(String(format: "%.1f", rating))
                        }
                        .font(.subheadline)
                    }

                    if let sessions = listener.sessionCount, sessions > 0 {
                        Text("\(sessions) sessions completed")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .padding()
                .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }

            Text("Your supporter is ready to talk")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Matched with a listener. \(result.listener?.displayName ?? "A listener") is ready to talk")
    }

    private var queuedContent: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "clock.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.accent)
                .accessibilityHidden(true)

            Text("In Queue")
                .font(.title.bold())

            Text("We're finding the right listener for you.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            if let wait = result.estimatedWait {
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("Estimated wait")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("~\(wait) minutes")
                        .font(.title3.bold())
                        .foregroundStyle(SupportTheme.accent)
                }
                .padding()
                .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }

            Text("We'll notify you when matched.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In queue. Estimated wait is about \(result.estimatedWait ?? 0) minutes. We'll notify you when matched.")
    }
}

extension SupportMatchResponse: Identifiable {
    var id: String { sessionId?.uuidString ?? "pending-\(estimatedWait ?? 0)" }
}

#Preview("Request Support") {
    RequestSupportSheet(service: PeerSupportService(supabase: DependencyContainer.preview.supabase))
}
