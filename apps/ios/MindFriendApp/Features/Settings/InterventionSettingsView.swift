//  InterventionSettingsView.swift
//  MindFriendApp
//
//  Created by Context-Aware Interventions Feature
//  User preferences UI for intervention delivery settings

import EventKit
import SwiftUI

struct InterventionSettingsView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: InterventionSettingsViewModel
    @State private var showSettingsAlert = false

    init() {
        _viewModel = StateObject(wrappedValue: InterventionSettingsViewModel())
    }

    var body: some View {
        Form {
            interventionDeliverySection

            if viewModel.enabled {
                notificationsSection
                calendarTriggersSection
                mlTimingInsightsSection
                quietHoursSection
                recentInterventionsSection
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Intervention Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadPreferences(
                service: dependencies.interventionService,
                calendarMonitor: dependencies.calendarTriggerMonitor,
                timingAnalyzer: dependencies.optimalTimingAnalyzer,
                notificationManager: dependencies.interventionNotificationManager
            )
        }
        .onChange(of: viewModel.enabled) { _, newValue in
            Task {
                await viewModel.savePreferences(
                    service: dependencies.interventionService,
                    calendarMonitor: dependencies.calendarTriggerMonitor
                )
            }
        }
        .onChange(of: viewModel.maxDaily) { _, _ in
            Task {
                await viewModel.savePreferences(
                    service: dependencies.interventionService,
                    calendarMonitor: dependencies.calendarTriggerMonitor
                )
            }
        }
        .onChange(of: viewModel.quietHoursEnabled) { _, _ in
            Task {
                await viewModel.savePreferences(
                    service: dependencies.interventionService,
                    calendarMonitor: dependencies.calendarTriggerMonitor
                )
            }
        }
        .onChange(of: viewModel.quietStart) { _, _ in
            Task {
                await viewModel.savePreferences(
                    service: dependencies.interventionService,
                    calendarMonitor: dependencies.calendarTriggerMonitor
                )
            }
        }
        .onChange(of: viewModel.quietEnd) { _, _ in
            Task {
                await viewModel.savePreferences(
                    service: dependencies.interventionService,
                    calendarMonitor: dependencies.calendarTriggerMonitor
                )
            }
        }
        .onChange(of: viewModel.calendarTriggersEnabled) { _, _ in
            Task {
                await viewModel.savePreferences(
                    service: dependencies.interventionService,
                    calendarMonitor: dependencies.calendarTriggerMonitor
                )
            }
        }
        .onChange(of: viewModel.leadTimeMinutes) { _, _ in
            Task {
                await viewModel.saveCalendarConfig(monitor: dependencies.calendarTriggerMonitor)
            }
        }
        .onChange(of: viewModel.selectedCalendarIds) { _, _ in
            Task {
                await viewModel.saveCalendarConfig(monitor: dependencies.calendarTriggerMonitor)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh calendar permission when returning from Settings
            Task {
                await viewModel.refreshCalendarPermission(monitor: dependencies.calendarTriggerMonitor)
            }
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private var interventionDeliverySection: some View {
        Section("Intervention Delivery") {
            Toggle("Enable Smart Interventions", isOn: $viewModel.enabled)
                .tint(SupportTheme.accent)

            if viewModel.enabled {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    HStack {
                        Text("Daily Limit")
                        Spacer()
                        Text("\(viewModel.maxDaily)")
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                    Slider(value: $viewModel.maxDailyDouble, in: 1...10, step: 1)
                        .tint(SupportTheme.accent)
                    Text("Maximum interventions per day")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }
        }
        .listRowBackground(SupportTheme.surface)
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Push Notifications")
                        .font(.body)
                    Text(viewModel.notificationStatus)
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                if !viewModel.hasNotificationPermission {
                    Button("Enable") {
                        Task {
                            await viewModel.requestNotificationPermission(
                                manager: dependencies.interventionNotificationManager)
                        }
                    }
                    .buttonStyle(.supportSecondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SupportTheme.accent)
                }
            }
        }
        .listRowBackground(SupportTheme.surface)
    }

    @ViewBuilder
    private var calendarTriggersSection: some View {
        Section {
            Toggle("Calendar Event Armor", isOn: $viewModel.calendarTriggersEnabled)
                .tint(SupportTheme.accent)

            if viewModel.calendarTriggersEnabled {
                calendarPermissionContent
            }
        } header: {
            Text("Calendar Triggers")
        } footer: {
            if viewModel.calendarTriggersEnabled {
                Text(
                    "MindFriend will proactively offer calming interventions before meetings, deadlines, and other stressful calendar events."
                )
            }
        }
        .listRowBackground(SupportTheme.surface)
    }

    @ViewBuilder
    private var calendarPermissionContent: some View {
        if !viewModel.hasCalendarPermission {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                if viewModel.calendarPermissionDenied {
                    if viewModel.hasWriteOnlyAccess {
                        Text(
                            "MindFriend needs full calendar access to detect upcoming events. You currently have write-only access."
                        )
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                        Text("Go to: Settings → Privacy & Security → Calendars → MindFriend → Full Access")
                            .font(.caption)
                            .foregroundColor(SupportTheme.accent)
                    } else {
                        Text("Calendar access was denied.")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                        Text("Go to: Settings → Privacy & Security → Calendars → MindFriend")
                            .font(.caption)
                            .foregroundColor(SupportTheme.accent)
                    }

                    Button("Open Settings") {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    }
                    .buttonStyle(.supportSecondary)
                } else {
                    Button("Grant Calendar Access") {
                        print("[Calendar] Button tapped!")
                        Task {
                            await viewModel.requestCalendarPermission(monitor: dependencies.calendarTriggerMonitor)
                            if !viewModel.hasCalendarPermission {
                                viewModel.checkCalendarPermissionStatus()
                            }
                        }
                    }
                    .buttonStyle(.supportSecondary)
                }
            }
        } else {
            calendarConfigContent
        }
    }

    @ViewBuilder
    private var calendarConfigContent: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                HStack {
                    Text("Armor Lead Time")
                    Spacer()
                    Text("\(viewModel.leadTimeMinutes) min")
                        .foregroundColor(SupportTheme.textSecondary)
                }
                Slider(value: $viewModel.leadTimeDouble, in: 30...60, step: 5)
                    .tint(SupportTheme.accent)
                Text("How early to deliver calming interventions before stressful events")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            if viewModel.availableCalendars.isEmpty {
                Text("No calendars available")
                    .foregroundColor(SupportTheme.textSecondary)
                    .font(.caption)
            } else {
                NavigationLink {
                    CalendarSelectionView(
                        availableCalendars: viewModel.availableCalendars,
                        selectedCalendarIds: $viewModel.selectedCalendarIds
                    )
                } label: {
                    HStack {
                        Text("Monitored Calendars")
                        Spacer()
                        Text("\(viewModel.selectedCalendarIds.count)")
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mlTimingInsightsSection: some View {
        Section {
            if viewModel.hasMinimumTimingData {
                mlTimingDataContent
            } else {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Learning your preferences...")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                    Text("After 2 weeks of intervention history, MindFriend will learn your optimal timing patterns.")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }
        } header: {
            Text("ML Timing Insights")
        } footer: {
            if viewModel.hasMinimumTimingData {
                Text(
                    "Based on your completion and rating patterns, interventions are more likely during your best times."
                )
            }
        }
        .listRowBackground(SupportTheme.surface)
    }

    @ViewBuilder
    private var mlTimingDataContent: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Your best times for wellness moments:")
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)

            if !viewModel.bestHours.isEmpty {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(viewModel.bestHours, id: \.self) { hour in
                        Text(viewModel.formatHour(hour))
                            .font(.caption)
                            .padding(.horizontal, SupportTheme.Spacing.xs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .foregroundColor(SupportTheme.accent)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }

            if !viewModel.worstHours.isEmpty {
                Text("Times you typically dismiss:")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
                    .padding(.top, SupportTheme.Spacing.xxs)

                HStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(viewModel.worstHours, id: \.self) { hour in
                        Text(viewModel.formatHour(hour))
                            .font(.caption)
                            .padding(.horizontal, SupportTheme.Spacing.xs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .foregroundColor(SupportTheme.accent)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var quietHoursSection: some View {
        Section("Quiet Hours") {
            Toggle("Enable Quiet Hours", isOn: $viewModel.quietHoursEnabled)
                .tint(SupportTheme.accent)

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
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .listRowBackground(SupportTheme.surface)
    }

    @ViewBuilder
    private var recentInterventionsSection: some View {
        Section("Recent Interventions") {
            if viewModel.recentDeliveries.isEmpty {
                Text("No recent interventions")
                    .foregroundColor(SupportTheme.textSecondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.recentDeliveries.prefix(10)) { delivery in
                    DeliveryHistoryRow(delivery: delivery)
                }
            }
        }
        .listRowBackground(SupportTheme.surface)
    }
}

// MARK: - Delivery History Row

struct DeliveryHistoryRow: View {
    let delivery: InterventionDelivery

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
            HStack {
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)

                Spacer()

                if delivery.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SupportTheme.accent)
                } else if delivery.dismissedAt != nil {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(SupportTheme.accent)
                }
            }

            if let rating = delivery.rating {
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: index <= rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(
                                index <= rating ? SupportTheme.Celebration.gold : SupportTheme.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
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

    // Calendar triggers
    @Published var calendarTriggersEnabled: Bool = false
    @Published var hasCalendarPermission: Bool = false
    @Published var calendarPermissionDenied: Bool = false
    @Published var hasWriteOnlyAccess: Bool = false
    @Published var availableCalendars: [EKCalendar] = []
    @Published var selectedCalendarIds: Set<String> = []
    @Published var leadTimeMinutes: Int = 45

    // Notifications
    @Published var hasNotificationPermission: Bool = false
    @Published var notificationStatus: String = "Not enabled"

    // ML Timing
    @Published var hasMinimumTimingData: Bool = false
    @Published var bestHours: [Int] = []
    @Published var worstHours: [Int] = []

    // Helper for slider bindings (Slider requires Double)
    var maxDailyDouble: Double {
        get { Double(maxDaily) }
        set { maxDaily = Int(newValue) }
    }

    var leadTimeDouble: Double {
        get { Double(leadTimeMinutes) }
        set { leadTimeMinutes = Int(newValue) }
    }

    private var loadedPreferences: InterventionPreferences?
    private var loadedCalendarConfig: CalendarTriggerConfig?

    func loadPreferences(
        service: InterventionService,
        calendarMonitor: CalendarTriggerMonitor,
        timingAnalyzer: OptimalTimingAnalyzer,
        notificationManager: InterventionNotificationManager
    ) async {
        do {
            // Load intervention preferences
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

            // Load calendar permissions and config
            self.hasCalendarPermission = calendarMonitor.hasCalendarPermission()
            self.checkCalendarPermissionStatus()

            if hasCalendarPermission {
                // Get available calendars from EventKit
                let eventStore = EKEventStore()
                self.availableCalendars = eventStore.calendars(for: .event)

                // Load calendar config
                let config = try await calendarMonitor.getTriggerConfig()
                self.calendarTriggersEnabled = !config.enabledCalendarIds.isEmpty
                self.selectedCalendarIds = Set(config.enabledCalendarIds)
                self.leadTimeMinutes = config.leadTimeMinutes
                self.loadedCalendarConfig = config
            }

            // Load notification permission
            self.hasNotificationPermission = await notificationManager.hasNotificationPermission()
            self.notificationStatus = hasNotificationPermission ? "Enabled" : "Disabled"

            // Load ML timing insights
            do {
                self.hasMinimumTimingData = try await timingAnalyzer.hasMinimumData()

                if hasMinimumTimingData {
                    self.bestHours = timingAnalyzer.getBestHours()
                    self.worstHours = timingAnalyzer.getWorstHours()
                }
            } catch {
                // Not enough data yet
                self.hasMinimumTimingData = false
            }

        } catch {
            print("Error loading preferences: \(error)")
        }
    }

    func savePreferences(
        service: InterventionService,
        calendarMonitor: CalendarTriggerMonitor
    ) async {
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

    func saveCalendarConfig(monitor: CalendarTriggerMonitor) async {
        do {
            var config = loadedCalendarConfig ?? CalendarTriggerConfig.default
            config.enabledCalendarIds = Array(selectedCalendarIds)
            config.leadTimeMinutes = leadTimeMinutes

            try await monitor.updateTriggerConfig(config)
            self.loadedCalendarConfig = config
        } catch {
            print("Error saving calendar config: \(error)")
        }
    }

    func requestCalendarPermission(monitor: CalendarTriggerMonitor) async {
        let status = EKEventStore.authorizationStatus(for: .event)

        // Check if we need to direct user to Settings instead of requesting
        var needsSettings = false
        if #available(iOS 17.0, *) {
            needsSettings = (status == .denied || status == .writeOnly)
        } else {
            needsSettings = (status == .denied)
        }

        if needsSettings {
            self.hasCalendarPermission = false
            self.calendarPermissionDenied = true
            return
        }

        let granted = await monitor.requestCalendarPermission()

        self.hasCalendarPermission = granted
        checkCalendarPermissionStatus()

        if granted {
            let eventStore = EKEventStore()
            self.availableCalendars = eventStore.calendars(for: .event)
        }
    }

    func checkCalendarPermissionStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            // On iOS 17+, we need fullAccess. Both denied and writeOnly are insufficient.
            self.hasCalendarPermission = (status == .fullAccess)
            self.hasWriteOnlyAccess = (status == .writeOnly)
            self.calendarPermissionDenied = (status == .denied || status == .writeOnly)
        } else {
            self.hasCalendarPermission = (status == .authorized)
            self.hasWriteOnlyAccess = false
            self.calendarPermissionDenied = (status == .denied)
        }
        print(
            "[Calendar] Permission status - hasPermission: \(hasCalendarPermission), writeOnly: \(hasWriteOnlyAccess), denied: \(calendarPermissionDenied), rawStatus: \(status.rawValue)"
        )
    }

    func refreshCalendarPermission(monitor: CalendarTriggerMonitor) async {
        let previouslyHadPermission = hasCalendarPermission
        self.hasCalendarPermission = monitor.hasCalendarPermission()
        self.checkCalendarPermissionStatus()

        // If permission was just granted (user came back from Settings), refresh monitor and load calendars
        if hasCalendarPermission && !previouslyHadPermission {
            // Refresh the shared CalendarTriggerMonitor's event store to recognize new permission
            monitor.refreshEventStore()

            // Load calendars using a fresh event store
            let eventStore = EKEventStore()
            self.availableCalendars = eventStore.calendars(for: .event)
            print(
                "[Calendar] Permission granted from Settings, refreshed monitor and loaded \(availableCalendars.count) calendars"
            )
        }
    }

    func requestNotificationPermission(manager: InterventionNotificationManager) async {
        let granted = await manager.requestNotificationPermission()
        self.hasNotificationPermission = granted
        self.notificationStatus = granted ? "Enabled" : "Denied"
    }

    func formatHour(_ hour: Int) -> String {
        return OptimalTimingAnalyzer.formatHour(hour)
    }
}

// MARK: - Calendar Selection View

struct CalendarSelectionView: View {
    let availableCalendars: [EKCalendar]
    @Binding var selectedCalendarIds: Set<String>

    var body: some View {
        List {
            ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                Button {
                    toggleCalendar(calendar)
                } label: {
                    HStack {
                        // Calendar color indicator
                        Circle()
                            .fill(SupportTheme.accent)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(calendar.title)
                                .foregroundColor(SupportTheme.textPrimary)
                            if !calendar.source.title.isEmpty {
                                Text(calendar.source.title)
                                    .font(.caption)
                                    .foregroundColor(SupportTheme.textSecondary)
                            }
                        }

                        Spacer()

                        if selectedCalendarIds.contains(calendar.calendarIdentifier) {
                            Image(systemName: "checkmark")
                                .foregroundColor(SupportTheme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Select Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selectedCalendarIds.count == availableCalendars.count ? "Deselect All" : "Select All") {
                    if selectedCalendarIds.count == availableCalendars.count {
                        selectedCalendarIds.removeAll()
                    } else {
                        selectedCalendarIds = Set(availableCalendars.map { $0.calendarIdentifier })
                    }
                }
            }
        }
    }

    private func toggleCalendar(_ calendar: EKCalendar) {
        if selectedCalendarIds.contains(calendar.calendarIdentifier) {
            selectedCalendarIds.remove(calendar.calendarIdentifier)
        } else {
            selectedCalendarIds.insert(calendar.calendarIdentifier)
        }
    }
}

#Preview {
    NavigationStack {
        InterventionSettingsView()
            .environmentObject(DependencyContainer.preview)
    }
}
