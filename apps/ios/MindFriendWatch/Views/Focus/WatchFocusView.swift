import SwiftUI

struct WatchFocusView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Focus Session")
                .font(.headline)

            Text("10 minutes")
                .font(.title)

            Button("Start") {
                dismiss()
            }
            .padding()
        }
    }
}
