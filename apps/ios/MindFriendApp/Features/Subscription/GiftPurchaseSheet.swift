import SwiftUI

/// Gift purchases are unavailable while the payment flow is being completed.
struct GiftPurchaseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Gifting is temporarily unavailable",
                systemImage: "gift",
                description: Text("Please check back later to send or redeem a gift.")
            )
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Gift a Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    GiftPurchaseSheet()
}
