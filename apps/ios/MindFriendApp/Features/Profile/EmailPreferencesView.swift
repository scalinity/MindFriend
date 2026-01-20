import SwiftUI

struct EmailPreferencesView: View {
  @StateObject private var viewModel: EmailPreferencesViewModel
  @Environment(\.dismiss) var dismiss
  @State private var showUnsubscribeConfirmation = false

  init(supabaseDataService: SupabaseDataService, authService: SupabaseAuthService) {
    _viewModel = StateObject(
      wrappedValue: EmailPreferencesViewModel(supabaseDataService: supabaseDataService)
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        ScrollView {
          VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
              Text("Email Preferences")
                .font(.title2)
                .fontWeight(.bold)

              Text("Manage how you receive emails from MindFriend")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top)

            // Messages
            if let errorMessage = viewModel.errorMessage {
              HStack {
                Image(systemName: "exclamationmark.circle.fill")
                  .foregroundColor(.red)
                Text(errorMessage)
                  .font(.callout)
                Spacer()
              }
              .padding()
              .background(Color.red.opacity(0.1))
              .cornerRadius(8)
              .padding(.horizontal)
            }

            if let successMessage = viewModel.successMessage {
              HStack {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                Text(successMessage)
                  .font(.callout)
                Spacer()
              }
              .padding()
              .background(Color.green.opacity(0.1))
              .cornerRadius(8)
              .padding(.horizontal)
            }

            // Timezone & Send Time
            VStack(spacing: 16) {
              SectionHeader(title: "Delivery Schedule")

              // Timezone Picker
              VStack(alignment: .leading, spacing: 8) {
                Text("Timezone")
                  .font(.subheadline)
                  .fontWeight(.semibold)

                Picker("Timezone", selection: $viewModel.timezone) {
                  ForEach(SUPPORTED_TIMEZONES, id: \.self) { tz in
                    Text(tz).tag(tz)
                  }
                }
                .pickerStyle(.navigationLink)
                .frame(maxWidth: .infinity, alignment: .leading)
              }

              // Send Hour Slider
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  Text("Preferred Send Time")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                  Spacer()
                  Text("\(viewModel.preferredSendHour):00")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
                }

                Slider(value: Binding(
                    get: { Double(viewModel.preferredSendHour) },
                    set: { viewModel.preferredSendHour = Int($0) }
                ), in: 0...23, step: 1)
                  .tint(.accentColor)
              }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Email Types
            VStack(spacing: 16) {
              SectionHeader(title: "Email Types")

              Toggle("Weekly Summary", isOn: $viewModel.weeklySummary)
              Toggle("Streak Celebration", isOn: $viewModel.streakCelebration)
              Toggle("Achievement Unlock", isOn: $viewModel.achievementUnlock)
              Toggle("Lapsed User Nudge", isOn: $viewModel.lapsedNudge)
              Toggle("Monthly Report", isOn: $viewModel.monthlyReport)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Subscription Status
            if let prefs = viewModel.emailPreferences, prefs.unsubscribedAt != nil {
              VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                  Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                  VStack(alignment: .leading, spacing: 4) {
                    Text("Unsubscribed")
                      .font(.subheadline)
                      .fontWeight(.semibold)
                    Text(prefs.unsubscribeReason ?? "You are unsubscribed from all emails")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                  Spacer()
                }

                Button(action: { Task { await viewModel.resubscribe() } }) {
                  Text("Resubscribe")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(viewModel.isLoading)
              }
              .padding()
              .background(Color.orange.opacity(0.1))
              .cornerRadius(12)
              .padding(.horizontal)
            } else {
              // Unsubscribe Button
              Button(role: .destructive, action: { showUnsubscribeConfirmation = true }) {
                HStack {
                  Image(systemName: "xmark.circle.fill")
                  Text("Unsubscribe from All Emails")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemRed))
                .foregroundColor(.white)
                .cornerRadius(8)
              }
              .disabled(viewModel.isLoading)
              .padding(.horizontal)
            }

            Spacer()
              .frame(height: 40)
          }
          .padding(.bottom, 20)
        }

        // Floating Save Button
        if viewModel.emailPreferences != nil {
          VStack {
            Spacer()

            Button(action: { Task { await viewModel.saveEmailPreferences() } }) {
              if viewModel.isLoading {
                ProgressView()
                  .progressViewStyle(.circular)
              } else {
                Text("Save Changes")
              }
            }
            .font(.callout)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(viewModel.isLoading)
            .padding()
            .background(Color(.systemBackground))
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        Task { await viewModel.loadEmailPreferences() }
      }
      .confirmationDialog(
        "Unsubscribe from All Emails",
        isPresented: $showUnsubscribeConfirmation,
        actions: {
          Button("Unsubscribe", role: .destructive) {
            Task { await viewModel.unsubscribeFromAllEmails() }
          }
          Button("Cancel", role: .cancel) {}
        },
        message: {
          Text(
            "You will no longer receive any emails from MindFriend. You can resubscribe anytime."
          )
        }
      )
    }
  }
}

// MARK: - Section Header

struct SectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.subheadline)
      .fontWeight(.semibold)
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Preview

#Preview {
  // TODO: EmailPreferencesView needs proper service initialization
  Text("Email Preferences")
}
