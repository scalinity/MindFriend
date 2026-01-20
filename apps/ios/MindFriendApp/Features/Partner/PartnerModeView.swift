import SwiftUI

/// Main container view for Partner Mode
/// Routes to onboarding or dashboard based on partner state
struct PartnerModeView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var viewModel: PartnerModeViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = viewModel {
                    contentView(viewModel: viewModel)
                } else {
                    loadingView
                }
            }
            .navigationTitle("Partner Mode")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            if viewModel == nil {
                viewModel = PartnerModeViewModel(dataService: container.supabaseDataService)
            }
            await viewModel?.loadPartnerData()
        }
    }

    @ViewBuilder
    private func contentView(viewModel: PartnerModeViewModel) -> some View {
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
        .alert("Error", isPresented: .constant(viewModel.showError)) {
            Button("OK", role: .cancel) {
                viewModel.showError = false
            }
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
