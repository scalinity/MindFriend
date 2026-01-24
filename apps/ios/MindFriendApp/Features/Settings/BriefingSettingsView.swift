//
//  BriefingSettingsView.swift
//  MindFriendApp
//
//  F009: Briefing Preferences UI
//  User settings for daily briefing
//

import SwiftUI

/// Settings view for briefing preferences
struct BriefingSettingsView: View {
    @ObservedObject var viewModel: DailyBriefingViewModel
    @ObservedObject var calendarService: CalendarService

    @State private var isRequestingCalendarAccess = false

    var body: some View {
        Form {
            // Enable/Disable Briefing
            Section {
                Toggle("Enable Daily Briefing", isOn: binding(\.enabled))
            } header: {
                Text("Briefing")
            } footer: {
                Text("Receive a personalized morning briefing with mood prediction, quest, and calendar events.")
            }

            // Calendar Integration
            Section {
                Toggle("Include Calendar Events", isOn: binding(\.includeCalendar))
                    .disabled(!(viewModel.preferences?.enabled ?? true))

                calendarPermissionRow

                Picker("Lookahead Window", selection: binding(\.calendarLookaheadHours)) {
                    Text("24 hours").tag(24)
                    Text("48 hours").tag(48)
                }
                .disabled(!(viewModel.preferences?.includeCalendar ?? true))
            } header: {
                Text("Calendar")
            } footer: {
                Text("Show upcoming events in your briefing.")
            }

            // Phase 2: Notification Time
            Section {
                Text("Notification delivery coming in Phase 2")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } header: {
                Text("Notifications")
            }
        }
        .navigationTitle("Daily Briefing")
        .task {
            await viewModel.loadPreferences()
        }
    }

    // MARK: - Calendar Permission Row

    @ViewBuilder
    private var calendarPermissionRow: some View {
        HStack {
            Text("Calendar Access")
            Spacer()
            Group {
                switch calendarService.authorizationStatus {
                case .authorized, .fullAccess:
                    Label("Authorized", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .denied, .restricted:
                    Label("Denied", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                case .notDetermined, .writeOnly:
                    Button("Request Access") {
                        requestCalendarAccess()
                    }
                    .buttonStyle(.bordered)
                @unknown default:
                    Text("Unknown")
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Helpers

    /// Create a binding to a preference property
    private func binding<T>(_ keyPath: WritableKeyPath<BriefingPreferences, T>) -> Binding<T> {
        Binding(
            get: {
                viewModel.preferences?[keyPath: keyPath] ?? BriefingPreferences.default[keyPath: keyPath]
            },
            set: { newValue in
                guard var prefs = viewModel.preferences else { return }
                prefs[keyPath: keyPath] = newValue
                Task {
                    await viewModel.updatePreferences(prefs)
                }
            }
        )
    }

    /// Request calendar access
    private func requestCalendarAccess() {
        isRequestingCalendarAccess = true
        Task {
            do {
                _ = try await calendarService.requestAccess()
            } catch {
                print("Calendar access request failed: \(error)")
            }
            isRequestingCalendarAccess = false
        }
    }
}
