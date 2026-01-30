import SwiftUI

/// Main container view for Partner Mode
/// Routes to onboarding or dashboard based on partner state
struct PartnerModeView: View {
    @EnvironmentObject var container: DependencyContainer

    var body: some View {
        PartnerModeContentView(dataService: container.supabaseDataService)
            .navigationTitle("Partner Mode")
    }
}

/// Inner view that owns the StateObject for proper observation
private struct PartnerModeContentView: View {
    @StateObject private var viewModel: PartnerModeViewModel

    init(dataService: SupabaseDataService) {
        _viewModel = StateObject(wrappedValue: PartnerModeViewModel(dataService: dataService))
    }

    var body: some View {
        Group {
            switch viewModel.partnerState {
            case .loading:
                loadingView

            case .noPartner:
                PartnerOnboardingView(viewModel: viewModel)

            case .pendingInvite(let code, let expiresAt):
                PartnerOnboardingView(viewModel: viewModel, pendingCode: code, expiresAt: expiresAt)

            case .hasPartner(let partnerInfo):
                PartnerDashboardView(viewModel: viewModel, partnerInfo: partnerInfo)
            }
        }
        .task {
            await viewModel.loadPartnerData()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PartnerModeView()
        .environmentObject(DependencyContainer())
}
