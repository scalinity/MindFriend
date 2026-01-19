import SwiftUI

/// A carousel displaying user testimonials for social proof
struct TestimonialsCarousel: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var testimonials: [Testimonial] = []
    @State private var currentIndex = 0
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Users Say")
                .font(.headline)
                .padding(.horizontal)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
            } else if testimonials.isEmpty {
                EmptyView()
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(testimonials.enumerated()), id: \.element.id) { index, testimonial in
                        TestimonialCard(testimonial: testimonial)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 180)
            }
        }
        .task {
            await loadTestimonials()
        }
    }

    private func loadTestimonials() async {
        isLoading = true
        defer { isLoading = false }

        do {
            testimonials = try await container.supabaseDataService.getTestimonials()
        } catch {
            Log.ui.error("Failed to load testimonials", error: error)
            testimonials = []
        }
    }
}

/// A card displaying a single testimonial
struct TestimonialCard: View {
    let testimonial: Testimonial

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Stars
            HStack(spacing: 2) {
                ForEach(0..<5) { i in
                    Image(systemName: i < testimonial.rating ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            .accessibilityLabel("\(testimonial.rating) out of 5 stars")

            Text("\"\(testimonial.content)\"")
                .font(.subheadline)
                .italic()
                .lineLimit(4)

            HStack {
                Text("— \(testimonial.displayName)")
                    .font(.caption)
                    .fontWeight(.medium)
                if let location = testimonial.location {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    TestimonialsCarousel()
        .environmentObject(DependencyContainer.preview)
}
