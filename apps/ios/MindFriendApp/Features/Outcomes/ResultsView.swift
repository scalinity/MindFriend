import SwiftUI

/// Assessment results display with severity color-coding, trends, and resource links
@MainActor
struct ResultsView: View {
    let response: AssessmentResponse
    let template: AssessmentTemplate
    @ObservedObject var outcomeService: OutcomeTrackingService
    @Binding var isPresented: Bool
    
    @State private var showingGoalSheet = false
    @State private var isSharing = false
    
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
            return (image: "arrow.down.circle.fill", color: Color(red: 0.2, green: 0.6, blue: 0.4), label: "Improving")
        } else if scoreDelta > 0 {
            return (image: "arrow.up.circle.fill", color: Color(red: 1.0, green: 0.2, blue: 0.2), label: "Worsening")
        } else {
            return (image: "dash.circle.fill", color: Color.gray, label: "Stable")
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
                                    
                                    Text("/ 100")
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
                                    
                                    Text(response.severityLevel)
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
                                        subtitle: "Call or text 988 (US)"
                                    )
                                    
                                    ResourceLink(
                                        icon: "message.fill",
                                        title: "Crisis Text Line",
                                        subtitle: "Text HOME to 741741"
                                    )
                                    
                                    ResourceLink(
                                        icon: "globe",
                                        title: "Find Local Support",
                                        subtitle: "Visit samhsa.gov"
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
            ShareSheet(
                items: [generatePDF()]
            )
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
    
    private func generatePDF() -> Data {
        // Placeholder - would generate actual PDF with assessment results
        return "Assessment Results PDF".data(using: .utf8) ?? Data()
    }
}

// MARK: - Supporting Views

struct ResourceLink: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        Button(action: {}) {
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

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
