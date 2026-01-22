//
//  ValuesCompassView.swift
//  MindFriendApp
//
//  Display user's values compass with export functionality
//

import SwiftUI

struct ValuesCompassView: View {
    @StateObject private var viewModel: ValuesCompassViewModel
    @State private var showShareSheet = false
    @State private var compassImage: UIImage?

    init(valuesService: ValuesService) {
        _viewModel = StateObject(wrappedValue: ValuesCompassViewModel(valuesService: valuesService))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title
                Text("Your Values Compass")
                    .font(.title.bold())

                // Compass visualization
                if !viewModel.rankedValues.isEmpty {
                    CompassRenderer(values: viewModel.rankedValues)
                        .frame(height: 350)
                        .padding()
                }

                // Top 5 list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Top 5 Values")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(Array(viewModel.topValues.enumerated()), id: \.element.id) { index, card in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(categoryColor(for: card.category)))

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: card.icon)
                                    Text(card.displayName)
                                        .font(.headline)
                                }

                                Text(card.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        exportCompass()
                    } label: {
                        Label("Export Compass", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .task {
            await viewModel.loadUserValues()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = compassImage {
                ShareSheet(items: [image])
            }
        }
    }

    private func categoryColor(for category: ValueCategory) -> Color {
        switch category {
        case .personal: return .blue
        case .relationships: return .pink
        case .work: return .orange
        case .growth: return .green
        }
    }

    private func exportCompass() {
        let renderer = CompassRenderer(values: viewModel.rankedValues)
        compassImage = renderer.snapshot()
        showShareSheet = true
    }
}

@MainActor
final class ValuesCompassViewModel: ObservableObject {
    @Published var topValues: [ValueCard] = []
    @Published var rankedValues: [CompassRenderer.RankedValue] = []
    @Published var isLoading = false
    @Published var error: String?

    private let valuesService: ValuesService

    init(valuesService: ValuesService) {
        self.valuesService = valuesService
    }

    func loadUserValues() async {
        isLoading = true

        do {
            // Get user's values
            guard let userValues = try await valuesService.getUserValues() else {
                isLoading = false
                return
            }

            // Load full card details
            let allCards = try await valuesService.loadAllCards()

            topValues = userValues.topValues.compactMap { valueKey in
                allCards.first(where: { $0.valueKey == valueKey })
            }

            // Convert to ranked values for compass
            rankedValues = topValues.enumerated().map { index, card in
                CompassRenderer.RankedValue(
                    id: card.id,
                    displayName: card.displayName,
                    category: card.category,
                    rank: index + 1
                )
            }

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
