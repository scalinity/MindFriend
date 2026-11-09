import SwiftUI
import LinkPresentation

/// Assessment results display with severity color-coding, trends, and resource links
@MainActor
struct ResultsView: View {
    let response: AssessmentResponse
    let template: AssessmentTemplate
    @ObservedObject var outcomeService: OutcomeTrackingService
    @Binding var isPresented: Bool

    @State private var showingGoalSheet = false
    @State private var isSharing = false
    @State private var recommendations: [AssessmentExerciseRecommendation] = []
    @State private var isLoadingRecommendations = false
    @State private var selectedExercise: Exercise?
    @State private var previousResponse: AssessmentResponse?
    @State private var isLoadingTrend = true
    @State private var trendUnavailable = false

    var recommendationService: AssessmentRecommendationService?

    var severityColor: Color {
        guard response.availableScore != nil else { return SupportTheme.accent }
        switch response.severityLevel.lowercased() {
        case "minimal": return SupportTheme.accent
        case "mild": return SupportTheme.accent
        case "moderate": return SupportTheme.accent
        case "moderately_severe", "moderately severe": return SupportTheme.accent
        case "severe": return SupportTheme.accent
        default: return SupportTheme.textSecondary
        }
    }

    var severityBackgroundColor: Color {
        severityColor.opacity(0.1)
    }

    /// Formatted severity level with proper capitalization
    var formattedSeverityLevel: String {
        guard response.availableScore != nil else { return "Unavailable" }
        let severity = response.severityLevel.lowercased()
        switch severity {
        case "moderately_severe":
            return "Moderately Severe"
        default:
            return severity.capitalized
        }
    }

    /// Description of what this assessment measures
    var assessmentDescription: String {
        switch template.code {
        case "PHQ9":
            return "The PHQ-9 screens for depression by measuring how often you've experienced symptoms like low mood, loss of interest, and changes in sleep or appetite over the past two weeks."
        case "GAD7":
            return "The GAD-7 screens for generalized anxiety disorder by measuring symptoms like excessive worry, restlessness, and difficulty relaxing over the past two weeks."
        case "WHO5":
            return "The WHO-5 measures your overall well-being and quality of life by asking about positive feelings like cheerfulness, calmness, and energy over the past two weeks. Higher scores indicate better well-being."
        case "PSS10":
            return "The PSS-10 measures your perceived stress level by asking how often you've felt overwhelmed, unable to cope, or out of control over the past month. Lower scores indicate less stress."
        default:
            return template.description ?? "This assessment helps track your mental wellness over time."
        }
    }

    var trendIndicator: (image: String, color: Color, label: String) {
        guard response.availableScore != nil else {
            return (image: "minus.circle.fill", color: SupportTheme.textSecondary, label: "No trend")
        }
        guard !isLoadingTrend else {
            return (image: "minus.circle.fill", color: SupportTheme.textSecondary, label: "Loading trend")
        }
        guard !trendUnavailable, let previousScore = previousResponse?.availableScore,
              let type = AssessmentType(rawValue: template.code) else {
            return (image: "minus.circle.fill", color: SupportTheme.textSecondary,
                    label: trendUnavailable ? "Trend unavailable" : "No earlier score")
        }
        let scoreDelta = type.improvement(from: previousScore, to: response.totalScore)

        if scoreDelta > 0 {
            return (image: type.higherScoresAreBetter ? "arrow.up.circle.fill" : "arrow.down.circle.fill", color: SupportTheme.accent, label: String(localized: "Improving"))
        } else if scoreDelta < 0 {
            return (image: type.higherScoresAreBetter ? "arrow.down.circle.fill" : "arrow.up.circle.fill", color: SupportTheme.accent, label: String(localized: "Worsening"))
        } else {
            return (image: "minus.circle.fill", color: SupportTheme.textSecondary, label: String(localized: "Stable"))
        }
    }

    var body: some View {
        ZStack {
            // Background
            SupportTheme.canvas
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Assessment Results")
                            .font(.system(.title3, design: .default).weight(.bold))
                            .foregroundColor(SupportTheme.accent)

                        Text(response.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .default).weight(.regular))
                            .foregroundColor(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title2))
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 4, x: 0, y: 2)

                // Scrollable content
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        // Score card (large)
                        VStack(spacing: SupportTheme.Spacing.m) {
                            VStack(spacing: SupportTheme.Spacing.xs) {
                                Text(template.name)
                                    .font(.system(.body, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.textSecondary)

                                HStack(alignment: .firstTextBaseline, spacing: SupportTheme.Spacing.xxs) {
                                    Text(response.availableScore.map(String.init) ?? "—")
                                        .font(.system(.largeTitle, design: .default).weight(.bold))
                                        .foregroundColor(severityColor)

                                    Text("/ \(AssessmentType(rawValue: template.code)?.maxScore ?? 27)")
                                        .font(.system(.title3, design: .default).weight(.regular))
                                        .foregroundColor(SupportTheme.textSecondary)
                                }
                            }

                            if let explanation = response.scoreStatus.explanation {
                                Text(explanation)
                                    .font(.footnote)
                                    .foregroundColor(SupportTheme.textSecondary)
                            }
                            Divider()
                                .padding(.vertical, SupportTheme.Spacing.xxs)

                            // Severity badge
                            VStack(spacing: SupportTheme.Spacing.xs) {
                                Text("Severity Level")
                                    .font(.system(.caption, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Circle()
                                        .fill(severityColor)
                                        .frame(width: 12, height: 12)

                                    Text(formattedSeverityLevel)
                                        .font(.system(.subheadline, design: .default).weight(.semibold))
                                        .foregroundColor(SupportTheme.accent)

                                    Spacer()
                                }
                            }
                        }
                        .padding(SupportTheme.Spacing.m)
                        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        // About this assessment
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(.subheadline))
                                    .foregroundColor(SupportTheme.accent)

                                Text("About this Assessment")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)
                            }

                            Text(assessmentDescription)
                                .font(.system(.caption, design: .default).weight(.regular))
                                .foregroundColor(SupportTheme.textSecondary)
                                .lineSpacing(3)
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.surface)
                        )
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        // Trend card
                        VStack(spacing: SupportTheme.Spacing.s) {
                            HStack {
                                Text("Progress Trend")
                                    .font(.system(.subheadline, design: .default).weight(.semibold))
                                    .foregroundColor(SupportTheme.accent)

                                Spacer()
                            }

                            HStack(spacing: SupportTheme.Spacing.s) {
                                Image(systemName: trendIndicator.image)
                                    .font(.system(.title3))
                                    .foregroundColor(trendIndicator.color)

                                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                    Text(trendIndicator.label)
                                        .font(.system(.subheadline, design: .default).weight(.semibold))
                                        .foregroundColor(trendIndicator.color)

                                    Text("vs last assessment")
                                        .font(.system(.caption, design: .default).weight(.regular))
                                        .foregroundColor(SupportTheme.textSecondary)
                                }

                                Spacer()
                            }
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        // Interpretation section
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("What this means")
                                .font(.system(.subheadline, design: .default).weight(.semibold))
                                .foregroundColor(SupportTheme.accent)

                            Text(interpretationText())
                                .font(.system(.subheadline, design: .default).weight(.regular))
                                .foregroundColor(SupportTheme.accent)
                                .lineLimit(nil)
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                        .padding(.horizontal, SupportTheme.Spacing.m)

                        // Exercise recommendations section
                        if !recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Image(systemName: "sparkles")
                                        .font(.system(.subheadline))
                                        .foregroundColor(SupportTheme.accent)

                                    Text("Recommended for You")
                                        .font(.system(.subheadline, design: .default).weight(.semibold))
                                        .foregroundColor(SupportTheme.accent)

                                    Spacer()
                                }

                                VStack(spacing: SupportTheme.Spacing.xs) {
                                    ForEach(recommendations) { rec in
                                        Button(action: {
                                            selectedExercise = rec.exercise
                                        }) {
                                            HStack(spacing: SupportTheme.Spacing.s) {
                                                Image(systemName: rec.exerciseType.icon)
                                                    .font(.system(.body).weight(.semibold))
                                                    .foregroundColor(SupportTheme.accent)
                                                    .frame(width: 32, height: 32)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                                            .fill(SupportTheme.accent.opacity(0.1))
                                                    )

                                                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                                    Text(rec.title)
                                                        .font(.system(.subheadline, design: .default).weight(.semibold))
                                                        .foregroundColor(SupportTheme.accent)

                                                    Text(rec.reason)
                                                        .font(.system(.caption, design: .default).weight(.regular))
                                                        .foregroundColor(SupportTheme.textSecondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }

                                                Spacer()

                                                Text(rec.durationLabel)
                                                    .font(.system(.caption, design: .default).weight(.medium))
                                                    .foregroundColor(SupportTheme.textSecondary)

                                                Image(systemName: "chevron.right")
                                                    .font(.system(.caption).weight(.semibold))
                                                    .foregroundColor(SupportTheme.textSecondary.opacity(0.5))
                                            }
                                            .padding(SupportTheme.Spacing.s)
                                            .background(
                                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                                    .fill(SupportTheme.surface)
                                                    .stroke(SupportTheme.textSecondary.opacity(0.15), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding(SupportTheme.Spacing.s)
                            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                            .padding(.horizontal, SupportTheme.Spacing.m)
                        } else if isLoadingRecommendations {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(SupportTheme.Spacing.m)
                                Spacer()
                            }
                            .padding(.horizontal, SupportTheme.Spacing.m)
                        }

                        // Resources section (if needed)
                        if isHighRisk() {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(.subheadline))
                                        .foregroundColor(SupportTheme.accent)

                                    Text("Support Resources")
                                        .font(.system(.subheadline, design: .default).weight(.semibold))
                                        .foregroundColor(SupportTheme.accent)
                                }

                                VStack(spacing: SupportTheme.Spacing.xs) {
                                    ResourceLink(
                                        icon: "phone.fill",
                                        title: "988 Suicide & Crisis Lifeline",
                                        subtitle: "Call or text 988 (US)",
                                        urlString: "tel:988"
                                    )

                                    ResourceLink(
                                        icon: "message.fill",
                                        title: "Crisis Text Line",
                                        subtitle: "Text HOME to 741741",
                                        urlString: "sms:741741&body=HOME"
                                    )

                                    ResourceLink(
                                        icon: "globe",
                                        title: "Find Local Support",
                                        subtitle: "Visit samhsa.gov",
                                        urlString: "https://www.samhsa.gov/find-help/national-helpline"
                                    )
                                }
                            }
                            .padding(SupportTheme.Spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.accent.opacity(0.05))
                                    .stroke(SupportTheme.accent.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, SupportTheme.Spacing.m)
                        }

                        // Action buttons
                        VStack(spacing: SupportTheme.Spacing.xs) {
                            Button(action: {
                                showingGoalSheet = true
                            }) {
                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Image(systemName: "target")
                                        .font(.system(.subheadline).weight(.semibold))

                                    Text("Set Outcome Goal")
                                        .font(.system(.subheadline, design: .default).weight(.semibold))
                                }
                                .foregroundColor(SupportTheme.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.s)
                                .background(
                                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                        .fill(SupportTheme.accent)
                                )
                            }

                            .disabled(response.availableScore == nil)
                            Button(action: {
                                isSharing = true
                            }) {
                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(.subheadline).weight(.semibold))

                                    Text("Share Results")
                                        .font(.system(.subheadline, design: .default).weight(.semibold))
                                }
                                .foregroundColor(SupportTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.s)
                                .background(
                                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                        .fill(SupportTheme.surface)
                                        .stroke(SupportTheme.textSecondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                        .disabled(response.availableScore == nil)
                        .padding(SupportTheme.Spacing.m)
                    }
                    .padding(.vertical, SupportTheme.Spacing.m)
                }

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingGoalSheet) {
            GoalSettingView(
                response: response,
                template: template,
                outcomeService: outcomeService,
                isPresented: $showingGoalSheet
            )
        }
        .sheet(isPresented: $isSharing) {
            ResultsShareSheet(
                assessmentName: template.name,
                score: response.totalScore,
                maxScore: AssessmentType(rawValue: template.code)?.maxScore ?? 27,
                severityLevel: formattedSeverityLevel,
                date: response.completedAt
            )
        }
        .sheet(item: $selectedExercise) { exercise in
            ExercisePlayerView(exercise: exercise)
        }
        .task(id: response.id) {
            isLoadingTrend = true
            trendUnavailable = false
            previousResponse = nil
            do {
                let previous = try await outcomeService.getPreviousAssessmentResponse(to: response)
                guard !Task.isCancelled else { return }
                previousResponse = previous
            } catch {
                guard !Task.isCancelled else { return }
                trendUnavailable = true
            }
            isLoadingTrend = false
            await loadRecommendations()
        }
    }

    private func loadRecommendations() async {
        guard response.availableScore != nil, let service = recommendationService else { return }
        isLoadingRecommendations = true
        defer { isLoadingRecommendations = false }

        do {
            recommendations = try await service.getRecommendations(
                assessmentCode: template.code,
                severityLevel: response.severityLevel,
                maxCount: 3
            )
        } catch {
            print("Failed to load recommendations: \(error)")
        }
    }

    private func interpretationText() -> String {
        guard response.availableScore != nil else { return response.scoreStatus.explanation ?? "Score unavailable." }
        let severity = response.severityLevel.lowercased()
        switch severity {
        case "minimal":
            return "Your score suggests minimal symptoms. Continue practicing good self-care habits and check in regularly."
        case "mild":
            return "Your score suggests mild symptoms. Consider exploring coping strategies and reaching out if you need support."
        case "moderate":
            return "Your score suggests moderate symptoms. Speaking with a therapist or counselor could be helpful."
        case "moderately_severe", "moderately severe":
            return "Your score suggests moderately severe symptoms. Professional support is recommended."
        case "severe":
            return "Your score suggests severe symptoms. Please reach out to a mental health professional."
        default:
            return "Review your results with a healthcare provider."
        }
    }

    private func isHighRisk() -> Bool {
        let severity = response.severityLevel.lowercased()
        return severity == "severe" || severity == "moderately_severe" || severity == "moderately severe"
    }
}

// MARK: - Supporting Views

struct ResourceLink: View {
    let icon: String
    let title: String
    let subtitle: String
    let urlString: String

    var body: some View {
        Button(action: {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: SupportTheme.Spacing.s) {
                Image(systemName: icon)
                    .font(.system(.body).weight(.semibold))
                    .foregroundColor(SupportTheme.accent)
                    .frame(minWidth: 24)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(title)
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundColor(SupportTheme.accent)

                    Text(subtitle)
                        .font(.system(.caption, design: .default).weight(.regular))
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(.caption).weight(.semibold))
                    .foregroundColor(SupportTheme.textSecondary)
            }
            .padding(SupportTheme.Spacing.s)
            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        }
    }
}

struct ResultsShareSheet: UIViewControllerRepresentable {
    let assessmentName: String
    let score: Int
    let maxScore: Int
    let severityLevel: String
    let date: Date

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let itemSource = AssessmentResultsItemSource(
            assessmentName: assessmentName,
            score: score,
            maxScore: maxScore,
            severityLevel: severityLevel,
            date: date
        )
        let controller = UIActivityViewController(activityItems: [itemSource], applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Custom activity item source that provides proper metadata for the share sheet
final class AssessmentResultsItemSource: NSObject, UIActivityItemSource {
    let assessmentName: String
    let score: Int
    let maxScore: Int
    let severityLevel: String
    let date: Date

    init(assessmentName: String, score: Int, maxScore: Int, severityLevel: String, date: Date) {
        self.assessmentName = assessmentName
        self.score = score
        self.maxScore = maxScore
        self.severityLevel = severityLevel
        self.date = date
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return shareText
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return shareText
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "My \(assessmentName) Results"
    }

    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "My \(assessmentName) Results"

        // Use the app icon
        if let appIcon = UIImage(named: "AppIcon") ?? Bundle.main.icon {
            metadata.iconProvider = NSItemProvider(object: appIcon)
        }

        return metadata
    }

    /// Cached DateFormatter for share text (DateFormatter is expensive to create)
    private static let shareFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var shareText: String {
        return """
        My \(assessmentName) Results

        Score: \(score)/\(maxScore)
        Level: \(severityLevel.capitalized)
        Date: \(Self.shareFormatter.string(from: date))

        Tracked with MindFriend
        """
    }
}

// Helper to get app icon from bundle
private extension Bundle {
    var icon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return nil
    }
}

#if DEBUG
#Preview {
    ResultsView(
        response: AssessmentResponse(
            id: UUID(),
            userId: UUID(),
            assessmentTemplateId: UUID(),
            answers: ["1": 1, "2": 2],
            totalScore: 12,
            severityLevel: "moderate",
            isBaseline: true,
            notes: nil,
            completedAt: Date(),
            createdAt: Date()
        ),
        template: AssessmentTemplate(
            id: UUID(),
            code: "PHQ9",
            name: "PHQ-9",
            description: "Depression screening",
            questions: [],
            scoringRanges: [],
            recommendedFrequencyDays: 14,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        ),
        outcomeService: OutcomeTrackingService(supabase: .mock, authService: SupabaseAuthService()),
        isPresented: .constant(true)
    )
}
#endif
