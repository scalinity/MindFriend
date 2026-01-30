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
                            .foregroundStyle(.blue)
                        Text("Estimated duration: \(selectedType.estimatedMinutes) minutes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                Section("What would you like to talk about?") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
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
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
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

                Section {
                    TextField("What's on your mind? (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Additional Notes")
                } footer: {
                    Text("This helps the listener understand your situation better.")
                }

                Section {
                    Toggle(isOn: $isAnonymous) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keep me anonymous")
                            Text("Your profile will be hidden from the listener")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

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
                }
            }
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
        case 4...6: return .orange
        case 7...8: return .yellow
        case 9...10: return .green
        default: return .gray
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
            HStack(spacing: 4) {
                Image(systemName: topic.icon)
                    .font(.caption2)
                Text(topic.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundStyle(isSelected ? .white : .primary)
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
        VStack(spacing: 24) {
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .presentationDetents([.medium])
    }

    private var matchedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Matched!")
                .font(.title.bold())

            if let listener = result.listener {
                VStack(spacing: 8) {
                    Text(listener.displayName ?? "A Listener")
                        .font(.headline)

                    if let rating = listener.rating, rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                        }
                        .font(.subheadline)
                    }

                    if let sessions = listener.sessionCount, sessions > 0 {
                        Text("\(sessions) sessions completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            Text("Your supporter is ready to talk")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Matched with a listener. \(result.listener?.displayName ?? "A listener") is ready to talk")
    }

    private var queuedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("In Queue")
                .font(.title.bold())

            Text("We're finding the right listener for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let wait = result.estimatedWait {
                VStack(spacing: 4) {
                    Text("Estimated wait")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("~\(wait) minutes")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            Text("We'll notify you when matched.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In queue. Estimated wait is about \(result.estimatedWait ?? 0) minutes. We'll notify you when matched.")
    }
}

extension SupportMatchResponse: Identifiable {
    var id: UUID { sessionId ?? UUID() }
}

#Preview("Request Support") {
    RequestSupportSheet(service: PeerSupportService(supabase: DependencyContainer.preview.supabase))
}
