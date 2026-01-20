//
//  ValuesDiscoveryView.swift
//  MindFriendApp
//
//  3-phase values discovery flow
//

import SwiftUI

struct ValuesDiscoveryView: View {
    @StateObject private var viewModel: ValuesDiscoveryViewModel
    @Environment(\.dismiss) private var dismiss

    init(valuesService: ValuesService) {
        _viewModel = StateObject(wrappedValue: ValuesDiscoveryViewModel(valuesService: valuesService))
    }

    var body: View {
        NavigationStack {
            ZStack {
                switch viewModel.currentPhase {
                case 1:
                    phase1View
                case 2:
                    phase2View
                case 3:
                    phase3View
                default:
                    EmptyView()
                }

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
            .navigationTitle("Discover Your Values")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadCards()
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") {
                    viewModel.error = nil
                }
            } message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Phase 1: Select 8-12 Values

    private var phase1View: View {
        VStack(spacing: 20) {
            // Progress
            progressBar(phase: 1)

            // Instructions
            Text("Select 8-12 values that are most important to you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("\(viewModel.selectedCards.count) selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(viewModel.canProceedFromPhase1 ? .green : .secondary)

            // Cards grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                    ForEach(viewModel.allCards) { card in
                        ValueCardView(
                            card: card,
                            isSelected: viewModel.selectedCards.contains(where: { $0.id == card.id }),
                            rank: nil,
                            onTap: {
                                viewModel.toggleCardSelection(card)
                            }
                        )
                    }
                }
                .padding()
            }

            // Next button
            Button {
                Task {
                    await viewModel.submitPhase1()
                }
            } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canProceedFromPhase1 ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!viewModel.canProceedFromPhase1)
            .padding()
        }
    }

    // MARK: - Phase 2: Rank Top 5

    private var phase2View: View {
        VStack(spacing: 20) {
            progressBar(phase: 2)

            Text("Rank your top 5 values")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Selected values for ranking
            List {
                ForEach(viewModel.rankedCards.indices, id: \.self) { index in
                    HStack {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.blue))

                        Text(viewModel.rankedCards[index].displayName)
                            .font(.body)

                        Spacer()

                        Button {
                            viewModel.removeFromRanking(viewModel.rankedCards[index])
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .onMove(perform: viewModel.moveCard)
            }
            .frame(height: 300)

            // Available cards
            Text("Tap to add (\(5 - viewModel.rankedCards.count) remaining)")
                .font(.caption.weight(.semibold))

            ScrollView(.horizontal) {
                HStack {
                    ForEach(viewModel.selectedCards.filter { card in
                        !viewModel.rankedCards.contains(where: { $0.id == card.id })
                    }) { card in
                        Button {
                            viewModel.selectCardForRanking(card)
                        } label: {
                            VStack {
                                Image(systemName: card.icon)
                                    .font(.title2)
                                Text(card.displayName)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Button {
                Task {
                    await viewModel.submitPhase2()
                }
            } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canProceedFromPhase2 ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!viewModel.canProceedFromPhase2)
            .padding()
        }
    }

    // MARK: - Phase 3: Confirm

    private var phase3View: View {
        VStack(spacing: 20) {
            progressBar(phase: 3)

            Text("Confirm your top 5 values")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(viewModel.rankedCards.enumerated()), id: \.element.id) { index, card in
                    HStack {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.blue))

                        VStack(alignment: .leading) {
                            Text(card.displayName)
                                .font(.headline)
                            Text(card.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                Task {
                    await viewModel.submitPhase3()
                    if viewModel.confidenceScore != nil {
                        dismiss()
                    }
                }
            } label: {
                Text("Complete Discovery")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding()
        }
    }

    // MARK: - Helper Views

    private func progressBar(phase: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { p in
                RoundedRectangle(cornerRadius: 4)
                    .fill(p <= phase ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 6)
            }
        }
        .padding(.horizontal)
    }
}
