import SwiftUI

struct RewriteFeedbackView: View {
    let rewriteHistoryId: String
    let onSubmit: (Int, String?) -> Void
    let onSkip: () -> Void

    @State private var rating: Int = 0
    @State private var comment: String = ""
    @State private var showCommentField: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("How was this rewrite?")
                    .font(.headline)

                starRatingSection

                if showCommentField || rating <= 3 {
                    commentSection
                }

                submitSection
            }
            .padding()
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
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    withAnimation {
                        rating = star
                        showCommentField = star <= 3
                    }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 32))
                        .foregroundColor(.yellow)
                }
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What could be improved?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextField("Optional feedback...", text: $comment, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)
        }
    }

    private var submitSection: some View {
        Button {
            onSubmit(rating, comment.isEmpty ? nil : comment)
        } label: {
            Text("Submit")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(rating > 0 ? Color.blue : Color.gray)
                .cornerRadius(12)
        }
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
