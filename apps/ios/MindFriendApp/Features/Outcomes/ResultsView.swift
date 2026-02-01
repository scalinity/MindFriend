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

    var recommendationService: AssessmentRecommendationService?
    
    var severityColor: Color {
        switch response.severityLevel.lowercased() {
        case "minimal": return Color(red: 0.2, green: 0.6, blue: 0.4)
        case "mild": return Color(red: 0.3, green: 0.7, blue: 0.5)
        case "moderate": return Color(red: 0.95, green: 0.7, blue: 0.0)
        case "moderately_severe", "moderately severe": return Color(red: 1.0, green: 0.5, blue: 0.0)
        case "severe": return Color(red: 1.0, green: 0.2, blue: 0.2)
        default: return Color.gray
        }
    }
    
    var severityBackgroundColor: Color {
        severityColor.opacity(0.1)
    }

    /// Formatted severity level with proper capitalization
    var formattedSeverityLevel: String {
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
        let recentHistory = outcomeService.recentResponses
            .filter { $0.assessmentTemplateId == response.assessmentTemplateId }
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(5)
        
        guard recentHistory.count >= 2 else {
            return (image: "dash.circle.fill", color: Color.gray, label: "No trend")
        }
        
        let previousScore = recentHistory.dropFirst().first?.totalScore ?? response.totalScore
        let scoreDelta = response.totalScore - previousScore
        
        if scoreDelta < 0 {
            return (image: "arrow.down.circle.fill", color: Color(red: 0.2, green: 0.6, blue: 0.4), label: String(localized: "Improving"))
        } else if scoreDelta > 0 {
            return (image: "arrow.up.circle.fill", color: Color(red: 1.0, green: 0.2, blue: 0.2), label: String(localized: "Worsening"))
        } else {
            return (image: "dash.circle.fill", color: Color.gray, label: String(localized: "Stable"))
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.92, green: 0.96, blue: 0.98)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Assessment Results")
                            .font(.system(size: 18, weight: .bold, design: .default))
                            .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                        
                        Text(response.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                }
                .padding(20)
                .background(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 20) {
                        // Score card (large)
                        VStack(spacing: 16) {
                            VStack(spacing: 8) {
                                Text(template.name)
                                    .font(.system(size: 16, weight: .semibold, design: .default))
                                    .foregroundColor(.gray)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(response.totalScore)")
                                        .font(.system(size: 56, weight: .bold, design: .default))
                                        .foregroundColor(severityColor)
                                    
                                    Text("/ \(AssessmentType(rawValue: template.code)?.maxScore ?? 27)")
                                        .font(.system(size: 18, weight: .regular, design: .default))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Severity badge
                            VStack(spacing: 8) {
                                Text("Severity Level")
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(severityColor)
                                        .frame(width: 12, height: 12)

                                    Text(formattedSeverityLevel)
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))

                                    Spacer()
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, 20)

                        // About this assessment
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.4, green: 0.5, blue: 0.7))

                                Text("About this Assessment")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            }

                            Text(assessmentDescription)
                                .font(.system(size: 13, weight: .regular, design: .default))
                                .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.95, green: 0.96, blue: 0.98))
                        )
                        .padding(.horizontal, 20)

                        // Trend card
                        VStack(spacing: 12) {
                            HStack {
                                Text("Progress Trend")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Image(systemName: trendIndicator.image)
                                    .font(.system(size: 20))
                                    .foregroundColor(trendIndicator.color)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trendIndicator.label)
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                        .foregroundColor(trendIndicator.color)
                                    
                                    Text("vs last assessment")
                                        .font(.system(size: 12, weight: .regular, design: .default))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, 20)
                        
                        // Interpretation section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What this means")
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                            
                            Text(interpretationText())
                                .font(.system(size: 14, weight: .regular, design: .default))
                                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                                .lineLimit(nil)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal, 20)

                        // Exercise recommendations section
                        if !recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.4))

                                    Text("Recommended for You")
                                        .font(.system(size: 14, weight: .semibold, design: .default))
                                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))

                                    Spacer()
                                }

                                VStack(spacing: 8) {
                                    ForEach(recommendations) { rec in
                                        Button(action: {
                                            selectedExercise = rec.exercise
                                        }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: rec.exerciseType.icon)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(rec.exerciseType.themeColor)
                                                    .frame(width: 32, height: 32)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(rec.exerciseType.themeColor.opacity(0.1))
                                                    )

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(rec.title)
                                                        .font(.system(size: 14, weight: .semibold, design: .default))
                                                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))

                                                    Text(rec.reason)
                                                        .font(.system(size: 12, weight: .regular, design: .default))
                                                        .foregroundColor(.gray)
                                                        .lineLimit(1)
                                                }

                                                Spacer()

                                                Text(rec.durationLabel)
                                                    .font(.system(size: 12, weight: .medium, design: .default))
                                                    .foregroundColor(.gray)

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.gray.opacity(0.5))
                                            }
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color.white)
                                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            )
                            .padding(.horizontal, 20)
                        } else if isLoadingRecommendations {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        // Resources section (if needed)
                        if isHighRisk() {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
                                    
                                    Text("Support Resources")
                                        .font(.system(size: 14, weight: .semibold, design: .default))
                                        .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
                                }
                                
                                VStack(spacing: 8) {
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
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 1.0, green: 0.2, blue: 0.2).opacity(0.05))
                                    .stroke(Color(red: 1.0, green: 0.2, blue: 0.2).opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Action buttons
                        VStack(spacing: 10) {
                            Button(action: {
                                showingGoalSheet = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "target")
                                        .font(.system(size: 14, weight: .semibold))
                                    
                                    Text("Set Outcome Goal")
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.2, green: 0.6, blue: 0.4))
                                )
                            }
                            
                            Button(action: {
                                isSharing = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .semibold))
                                    
                                    Text("Share Results")
                                        .font(.system(size: 15, weight: .semibold, design: .default))
                                }
                                .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                        .padding(20)
                    }
                    .padding(.vertical, 20)
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
        .task {
            await loadRecommendations()
        }
    }

    private func loadRecommendations() async {
        guard let service = recommendationService else { return }
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.2, blue: 0.2))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
            )
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

    private var shareText: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        return """
        My \(assessmentName) Results

        Score: \(score)/\(maxScore)
        Level: \(severityLevel.capitalized)
        Date: \(dateFormatter.string(from: date))

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
