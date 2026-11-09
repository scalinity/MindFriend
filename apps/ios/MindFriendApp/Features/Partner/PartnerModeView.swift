import SwiftUI

/// Main container view for Partner Mode
/// Routes to onboarding or dashboard based on partner state
struct PartnerModeView: View {
    @EnvironmentObject var container: DependencyContainer

    var body: some View {
        PartnerModeContentView(dataService: container.supabaseDataService)
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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
        .safeAreaInset(edge: .bottom) {
            if viewModel.showError {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SupportTheme.textPrimary)
                    Button("OK") { viewModel.showError = false }
                        .buttonStyle(.supportSecondary)
                }
                .supportCard()
                .padding(SupportTheme.Spacing.m)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PartnerModeView()
        .environmentObject(DependencyContainer())
}
