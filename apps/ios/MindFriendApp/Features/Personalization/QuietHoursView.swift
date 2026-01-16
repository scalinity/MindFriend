// QuietHoursView.swift
// Smart Personalization: Quiet hours configuration

import SwiftUI

struct SmartQuietHoursView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date()
    @State private var hasInitialized = false

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        List {
            Section {
                DatePicker(
                    "Start",
                    selection: $startTime,
                    displayedComponents: .hourAndMinute
                )
                .accessibilityLabel("Quiet hours start time")

                DatePicker(
                    "End",
                    selection: $endTime,
                    displayedComponents: .hourAndMinute
                )
                .accessibilityLabel("Quiet hours end time")
            } footer: {
                Text("We won't send notifications during quiet hours. Default is 10 PM to 7 AM.")
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title)
                        .foregroundStyle(.indigo)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quiet Hours Active")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(quietHoursSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Quiet Hours")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasInitialized, let profile = personalizationService.preferenceProfile {
                startTime = timeFromString(profile.quietHoursStart) ?? defaultStartTime
                endTime = timeFromString(profile.quietHoursEnd) ?? defaultEndTime
                hasInitialized = true
            }
        }
        .onChange(of: startTime) { _, _ in
            if hasInitialized {
                updateQuietHours()
            }
        }
        .onChange(of: endTime) { _, _ in
            if hasInitialized {
                updateQuietHours()
            }
        }
    }

    private var quietHoursSummary: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let startStr = formatter.string(from: startTime)
        let endStr = formatter.string(from: endTime)

        return "From \(startStr) to \(endStr)"
    }

    private var defaultStartTime: Date {
        var components = DateComponents()
        components.hour = 22
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private var defaultEndTime: Date {
        var components = DateComponents()
        components.hour = 7
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func updateQuietHours() {
        Task {
            if var profile = personalizationService.preferenceProfile {
                profile.quietHoursStart = timeToString(startTime)
                profile.quietHoursEnd = timeToString(endTime)
                try? await personalizationService.updatePreferenceProfile(profile)
            }
        }
    }

    private func timeFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: string)
    }

    private func timeToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        SmartQuietHoursView()
            .environmentObject(DependencyContainer())
    }
}
