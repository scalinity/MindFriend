import SwiftUI

struct RewriteFeedbackView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rewriteHistoryId: String
    let onSubmit: (Int, String?) -> Void
    let onSkip: () -> Void

    @State private var rating: Int = 0
    @State private var comment: String = ""
    @State private var showCommentField: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: SupportTheme.Spacing.l) {
                Text("How was this rewrite?")
                    .font(.headline)

                starRatingSection

                if showCommentField || rating <= 3 {
                    commentSection
                }

                submitSection
            }
            .padding()
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                }
            }
        }
    }

    private var starRatingSection: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        rating = star
                        showCommentField = star <= 3
                    }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 32))
                        .foregroundColor(SupportTheme.Celebration.gold)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .accessibilityLabel("\(star) of 5 stars")
                .accessibilityAddTraits(star == rating ? .isSelected : [])
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("What could be improved?")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)

            TextField("Optional feedback...", text: $comment, axis: .vertical)

                .supportField()
                .lineLimit(3...6)
        }
    }

    private var submitSection: some View {
        Button {
            onSubmit(rating, comment.isEmpty ? nil : comment)
        } label: {
            Text("Submit")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.supportPrimary)
        .disabled(rating == 0)
    }
}

#Preview {
    RewriteFeedbackView(
        rewriteHistoryId: "test-id",
        onSubmit: { rating, comment in
            print("Rating: \(rating), Comment: \(comment ?? "none")")
        },
        onSkip: {
            print("Skipped")
        }
    )
}
