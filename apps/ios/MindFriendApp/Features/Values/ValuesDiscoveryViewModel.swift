//
//  ValuesDiscoveryViewModel.swift
//  MindFriendApp
//
//  ViewModel for 3-phase values discovery flow
//

import Foundation
import Combine

@MainActor
final class ValuesDiscoveryViewModel: ObservableObject {
    @Published var currentPhase: Int = 1
    @Published var allCards: [ValueCard] = []
    @Published var selectedCards: [ValueCard] = []
    @Published var rankedCards: [ValueCard] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var confidenceScore: Double?

    private let valuesService: ValuesService

    init(valuesService: ValuesService) {
        self.valuesService = valuesService
    }

    // MARK: - Load Cards

    func loadCards() async {
        isLoading = true
        error = nil

        do {
            allCards = try await valuesService.loadAllCards()
            isLoading = false
        } catch {
            self.error = "Failed to load values: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Phase 1: Select 8-12 Cards

    func toggleCardSelection(_ card: ValueCard) {
        if selectedCards.contains(where: { $0.id == card.id }) {
            selectedCards.removeAll { $0.id == card.id }
        } else {
            selectedCards.append(card)
        }
    }

    var canProceedFromPhase1: Bool {
        selectedCards.count >= 8 && selectedCards.count <= 12
    }

    func submitPhase1() async {
        guard canProceedFromPhase1 else { return }

        isLoading = true
        error = nil

        do {
            let cardIds = selectedCards.map { $0.valueKey }
            let response = try await valuesService.submitPhase1(selectedCardIds: cardIds)

            if response.success {
                currentPhase = 2
            } else {
                error = response.error ?? "Failed to save Phase 1"
            }

            isLoading = false
        } catch {
            self.error = "Network error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Phase 2: Rank Top 5

    func moveCard(from source: IndexSet, to destination: Int) {
        rankedCards.move(fromOffsets: source, toOffset: destination)
    }

    func selectCardForRanking(_ card: ValueCard) {
        if rankedCards.count < 5 && !rankedCards.contains(where: { $0.id == card.id }) {
            rankedCards.append(card)
        }
    }

    func removeFromRanking(_ card: ValueCard) {
        rankedCards.removeAll { $0.id == card.id }
    }

    var canProceedFromPhase2: Bool {
        rankedCards.count == 5
    }

    func submitPhase2() async {
        guard canProceedFromPhase2 else { return }

        isLoading = true
        error = nil

        do {
            let cardIds = rankedCards.map { $0.valueKey }
            let response = try await valuesService.submitPhase2(rankedCardIds: cardIds)

            if response.success {
                currentPhase = 3
            } else {
                error = response.error ?? "Failed to save Phase 2"
            }

            isLoading = false
        } catch {
            self.error = "Network error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Phase 3: Confirm

    func submitPhase3() async {
        guard rankedCards.count == 5 else { return }

        isLoading = true
        error = nil

        do {
            let cardIds = rankedCards.map { $0.valueKey }
            let response = try await valuesService.submitPhase3(confirmedCardIds: cardIds)

            if response.success {
                confidenceScore = response.confidenceScore
                // Navigation handled by parent view
            } else {
                error = response.error ?? "Failed to complete assessment"
            }

            isLoading = false
        } catch {
            self.error = "Network error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // MARK: - Reset

    func reset() {
        currentPhase = 1
        selectedCards = []
        rankedCards = []
        confidenceScore = nil
        error = nil
    }
}
