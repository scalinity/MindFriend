import SwiftUI

/// Main container view for Partner Mode
/// Routes to onboarding or dashboard based on partner state
struct PartnerModeView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var viewModel: PartnerModeViewModel?

    var body: some View {
        Group {
            if let viewModel = viewModel {
                contentView(viewModel: viewModel)
            } else {
                loadingView
            }
        }
        .navigationTitle("Partner Mode")
        .task {
            if viewModel == nil {
                viewModel = PartnerModeViewModel(dataService: container.supabaseDataService)
            }
            await viewModel?.loadPartnerData()
        }
    }

    @ViewBuilder
    private func contentView(viewModel: PartnerModeViewModel) -> some View {
        ZStack {
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

            // Show loading overlay when isLoading is true (initial data fetch)
            if viewModel.isLoading && viewModel.partnerState == .noPartner {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                loadingView
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.showError },
            set: { viewModel.showError = $0 }
        )) {
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
