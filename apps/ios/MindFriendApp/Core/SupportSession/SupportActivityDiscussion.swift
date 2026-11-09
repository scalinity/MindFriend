import Foundation

extension SupportActivityTemplateKey {
    var title: String {
        switch self {
        case .groundPresentV1: return "Notice what is around you"
        case .untangleThoughtV1: return "Untangle a thought"
        case .chooseStepV1: return "Choose one next step"
        }
    }

    var intention: String {
        switch self {
        case .groundPresentV1: return "Settle for a moment"
        case .untangleThoughtV1: return "Untangle a thought"
        case .chooseStepV1: return "Choose a next step"
        }
    }

    var prompts: [(id: String, text: String)] {
        switch self {
        case .groundPresentV1:
            return [("see", "Notice up to five things you can see."),
                    ("feel", "Notice up to four things you can feel."),
                    ("hear", "Notice up to three things you can hear."),
                    ("smell", "Notice up to two things you can smell."),
                    ("taste", "Notice one thing you can taste, or one neutral detail around you.")]
        case .untangleThoughtV1:
            return [("on_mind", "What is on your mind?"),
                    ("certain_unclear", "What feels certain, and what is still unclear?"),
                    ("fairer_way", "What would be a fairer or more useful way to say it?")]
        case .chooseStepV1:
            return [("action", "What is one small thing you could do?")]
        }
    }
}


struct SupportDiscussionField: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let text: String
}

struct SupportActivityDiscussionSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let activityID: UUID
    let activityRevision: Int64
    let sessionID: UUID
    let sessionRevision: Int64
    let sessionIsClosed: Bool
    let title: String
    let fields: [SupportDiscussionField]
    let existingDraft: String
}

struct SupportChatDraftHandoff: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let conversationID: UUID?
    let text: String
}

enum SupportActivityDiscussion {
    /// The existing context contract accepts at most 1,000 text units. Keep the full answers in the journal;
    /// expose and persist exactly this excerpt when the person includes it in later session context.
    static func reflectionPreview(_ activity: SupportActivity, note: String) -> String {
        let fields = fields(activity).filter { $0.id != "reflection_note" }
        let full = message(title: activity.templateKey.title, fields: fields, selected: Set(fields.map(\.id)),
            question: note, existingDraft: "")
        var result = "", units = 0
        for character in full {
            let size = String(character).utf16.count
            guard units + size <= SupportSessionLimits.shareableNoteMaxCharacters else { break }
            result.append(character)
            units += size
        }
        return result
    }

    static func fields(_ activity: SupportActivity) -> [SupportDiscussionField] {
        var fields = activity.templateKey.prompts.compactMap { prompt -> SupportDiscussionField? in
            let text = activity.kind == .chooseStep
                ? (activity.step?.actionText ?? activity.checkpoint.responses[prompt.id] ?? "")
                : (activity.checkpoint.responses[prompt.id] ?? "")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .init(id: prompt.id, label: prompt.text, text: text)
        }
        if let note = activity.reflection?.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(.init(id: "reflection_note", label: "Your reflection note", text: note))
        }
        return fields
    }

    static func message(title: String, fields: [SupportDiscussionField], selected: Set<String>,
                        question: String, existingDraft: String) -> String {
        var parts = [String]()
        if !existingDraft.isEmpty { parts.append(existingDraft) }
        let chosen = fields.filter { selected.contains($0.id) }
        if !chosen.isEmpty {
            parts.append("From “\(title)”:" + "\n\n" + chosen.map { $0.label + "\n" + $0.text }.joined(separator: "\n\n"))
        }
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty { parts.append(question) }
        return parts.joined(separator: "\n\n")
    }
}

/// One neutral event row per actual activity. No answer text is copied into the conversation.
struct SupportActivityChatEvent: Identifiable, Equatable, Sendable {
    let activityID: UUID
    let sessionID: UUID
    let template: SupportActivityTemplateKey
    let status: SupportActivityStatus
    let stepState: SupportStepState?
    let reflection: SupportReflectionOutcome?
    let answersShared: Bool
    let date: Date
    var id: String { "activity:" + activityID.uuidString.lowercased() }

    static func rows(in journal: SupportJournal, sessionID: UUID) -> [Self] {
        journal.activities(in: sessionID).map { activity in
            let meaningful: [SupportEventKind] = [.activityStarted, .activityCompleted, .activityStopped,
                .activityDiscarded, .stepSaved, .reflected]
            let date = journal.events(for: sessionID).filter { $0.activityID == activity.id && meaningful.contains($0.kind) }
                .map(\.occurredAt).max() ?? activity.updatedAt
            return Self(activityID: activity.id, sessionID: sessionID, template: activity.templateKey,
                status: activity.status, stepState: activity.step?.state, reflection: activity.reflection?.outcome,
                answersShared: activity.reflection?.includeWrittenAnswers ?? false, date: date)
        }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }
}
