import SwiftUI

struct HealthKitConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthKit: HealthKitService
    var onConnected: (() -> Void)?

    @State private var isConnecting = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 24) {

                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.pink.gradient)

                Text("Connect Apple Health")
                    .font(.title.bold())

                Text("Powered by HealthKit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)

                Text("Choose the data MindFriend may read from Apple Health. Recorded samples can help you explore patterns; they do not establish how you feel. Apple keeps your read choices private.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(HealthKitDataType.allCases, id: \.self) { type in
                        HealthDataTypeRow(type: type)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 12) {
                    if let error = error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        connect()
                    } label: {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isConnecting || !healthKit.isHealthKitAvailable)

                    if !healthKit.isHealthKitAvailable {
                        Text("HealthKit is not available on this device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
              .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        error = nil

        Task {
            do {
                // Explicit Connect: the only action that enables sync (also after a disconnect).
                try await healthKit.connect()
                try await healthKit.syncBiometrics(days: 30)
                onConnected?()
                dismiss()
            } catch {
                self.error = error
            }
            isConnecting = false
        }
    }
}

struct HealthDataTypeRow: View {
    let type: HealthKitDataType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundStyle(.pink)
                .frame(width: 32)

            VStack(alignment: .leading) {
                Text(type.displayName)
                    .font(.subheadline.bold())
                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HealthKitConnectionSheet(healthKit: HealthKitService())
}
