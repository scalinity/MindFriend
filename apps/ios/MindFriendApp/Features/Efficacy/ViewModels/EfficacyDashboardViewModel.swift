//
//  EfficacyDashboardViewModel.swift
//  MindFriendApp
//
//  Efficacy Dashboard ViewModel - State management for dashboard
//

import Foundation

@MainActor
final class EfficacyDashboardViewModel: ObservableObject {
    @Published private(set) var state: LoadingState = .loading

    private let efficacyEngine: InterventionEfficacyEngine

    enum LoadingState {
        case loading
        case loaded(EfficacyDashboardData)
        case error(String)
    }

    init(efficacyEngine: InterventionEfficacyEngine) {
        self.efficacyEngine = efficacyEngine
    }

    func loadDashboard() async {
        state = .loading

        do {
            let data = try await efficacyEngine.getDashboardData()
            state = .loaded(data)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
