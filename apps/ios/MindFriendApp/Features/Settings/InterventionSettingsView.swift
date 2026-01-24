//  InterventionSettingsView.swift
//  MindFriendApp
//
//  Created by Context-Aware Interventions Feature
//  User preferences UI for intervention delivery settings

import SwiftUI

struct InterventionSettingsView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: InterventionSettingsViewModel

    init() {
        _viewModel = StateObject(wrappedValue: InterventionSettingsViewModel())
    }

    var body: some View {
        Form {
            Section("Intervention Delivery") {
                Toggle("Enable Smart Interventions", isOn: $viewModel.enabled)
                    .tint(.blue)

                if viewModel.enabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Daily Limit")
                            Spacer()
                            Text("\(viewModel.maxDaily)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.maxDailyDouble, in: 1...10, step: 1)
                            .tint(.blue)
                        Text("Maximum interventions per day")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if viewModel.enabled {
                Section("Quiet Hours") {
                    Toggle("Enable Quiet Hours", isOn: $viewModel.quietHoursEnabled)
                        .tint(.blue)

                    if viewModel.quietHoursEnabled {
                        DatePicker(
                            "Start",
                            selection: $viewModel.quietStart,
                            displayedComponents: .hourAndMinute
                        )

                        DatePicker(
                            "End",
                            selection: $viewModel.quietEnd,
                            displayedComponents: .hourAndMinute
                        )

                        Text("No interventions will be delivered during quiet hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Recent Interventions") {
                    if viewModel.recentDeliveries.isEmpty {
                        Text("No recent interventions")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.recentDeliveries.prefix(10)) { delivery in
                            DeliveryHistoryRow(delivery: delivery)
                        }
                    }
                }
            }
        }
        .navigationTitle("Intervention Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadPreferences(service: dependencies.interventionService)
        }
        .onChange(of: viewModel.enabled) { _, newValue in
            Task {
                await viewModel.savePreferences(service: dependencies.interventionService)
            }
        }
        .onChange(of: viewModel.maxDaily) { _, _ in
            Task {
                await viewModel.savePreferences(service: dependencies.interventionService)
            }
        }
        .onChange(of: viewModel.quietHoursEnabled) { _, _ in
            Task {
                await viewModel.savePreferences(service: dependencies.interventionService)
            }
        }
        .onChange(of: viewModel.quietStart) { _, _ in
            Task {
                await viewModel.savePreferences(service: dependencies.interventionService)
            }
        }
        .onChange(of: viewModel.quietEnd) { _, _ in
            Task {
                await viewModel.savePreferences(service: dependencies.interventionService)
            }
        }
    }
}

// MARK: - Delivery History Row

struct DeliveryHistoryRow: View {
    let delivery: InterventionDelivery

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if delivery.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if delivery.dismissedAt != nil {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.orange)
                }
            }

            if let rating = delivery.rating {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: index <= rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(index <= rating ? .yellow : .gray)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: delivery.deliveredAt, relativeTo: Date())
    }
}

// MARK: - View Model

@MainActor
final class InterventionSettingsViewModel: ObservableObject {
    @Published var enabled: Bool = true
    @Published var maxDaily: Int = 5
    @Published var quietHoursEnabled: Bool = false
    @Published var quietStart: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @Published var quietEnd: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()
    @Published var recentDeliveries: [InterventionDelivery] = []

    // Helper for slider binding (Slider requires Double)
    var maxDailyDouble: Double {
        get { Double(maxDaily) }
        set { maxDaily = Int(newValue) }
    }

    private var loadedPreferences: InterventionPreferences?

    func loadPreferences(service: InterventionService) async {
        do {
            try await service.loadPreferences()

            if let prefs = service.preferences {
                self.enabled = prefs.enabled
                self.maxDaily = prefs.maxDaily
                self.quietHoursEnabled = prefs.quietHoursStart != nil

                if let start = prefs.quietStartTime {
                    self.quietStart = start
                }
                if let end = prefs.quietEndTime {
                    self.quietEnd = end
                }

                self.loadedPreferences = prefs
            }

            // Load recent deliveries
            try await service.loadRecentDeliveries()
            self.recentDeliveries = service.recentDeliveries

        } catch {
            print("Error loading preferences: \(error)")
        }
    }

    func savePreferences(service: InterventionService) async {
        do {
            var prefs = loadedPreferences ?? InterventionPreferences.default
            prefs.enabled = enabled
            prefs.maxDaily = maxDaily

            if quietHoursEnabled {
                prefs.setQuietHours(start: quietStart, end: quietEnd)
            } else {
                prefs.setQuietHours(start: nil, end: nil)
            }

            try await service.updatePreferences(prefs)
            self.loadedPreferences = prefs

        } catch {
            print("Error saving preferences: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        InterventionSettingsView()
            .environmentObject(DependencyContainer.preview)
    }
}
