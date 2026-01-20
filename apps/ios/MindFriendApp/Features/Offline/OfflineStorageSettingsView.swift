//
//  OfflineStorageSettingsView.swift
//  MindFriendApp
//
//  View for managing offline storage settings and cache
//

import SwiftUI

/// View for managing offline storage settings
struct OfflineStorageSettingsView: View {
    @StateObject private var offlineService = OfflineContentService.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLimit: StorageLimitOption = .default
    @State private var wifiOnlyEnabled = true
    @State private var autoDeleteEnabled = true
    @State private var storageBreakdown: StorageBreakdown?
    @State private var showClearCacheConfirmation = false
    @State private var isClearing = false

    var body: some View {
        List {
            // Storage limit section
            Section {
                ForEach(StorageLimitOption.allCases, id: \.self) { option in
                    StorageLimitRow(
                        option: option,
                        isSelected: selectedLimit == option,
                        onSelect: {
                            selectedLimit = option
                            Task {
                                await offlineService.updateStorageLimit(option)
                            }
                        }
                    )
                }
            } header: {
                Text("Storage Limit")
            } footer: {
                Text("Downloaded content will be automatically managed to stay within this limit.")
            }

            // Download preferences section
            Section {
                Toggle("WiFi Only Downloads", isOn: $wifiOnlyEnabled)
                    .onChange(of: wifiOnlyEnabled) { _, newValue in
                        Task {
                            var settings = offlineService.getDownloadSettings()
                            settings.wifiOnlyDownloads = newValue
                            await offlineService.updateDownloadSettings(settings)
                        }
                    }

                Toggle("Auto-Delete Old Content", isOn: $autoDeleteEnabled)
                    .onChange(of: autoDeleteEnabled) { _, newValue in
                        Task {
                            var settings = offlineService.getDownloadSettings()
                            settings.autoDeleteUnused = newValue
                            await offlineService.updateDownloadSettings(settings)
                        }
                    }
            } header: {
                Text("Download Preferences")
            } footer: {
                if wifiOnlyEnabled {
                    Text("Downloads will only start when connected to WiFi.")
                } else {
                    Text("Downloads may use cellular data.")
                }
            }

            // Storage breakdown section
            Section {
                if let breakdown = storageBreakdown {
                    StorageBreakdownView(breakdown: breakdown)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            } header: {
                Text("Storage Breakdown")
            }

            // Cache management section
            Section {
                Button {
                    Task {
                        await offlineService.invalidateAllCaches()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Cached Data")
                    }
                }

                Button(role: .destructive) {
                    showClearCacheConfirmation = true
                } label: {
                    HStack {
                        if isClearing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Clear All Offline Data")
                    }
                }
                .disabled(isClearing)
            } header: {
                Text("Cache Management")
            } footer: {
                Text("Clearing offline data will remove all downloads and cached content. You can re-download content anytime.")
            }
        }
        .navigationTitle("Storage Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await loadSettings()
            await loadStorageBreakdown()
        }
        .confirmationDialog(
            "Clear All Offline Data?",
            isPresented: $showClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task {
                    await clearAllData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded content and cached data. This action cannot be undone.")
        }
    }

    private func loadSettings() async {
        let settings = offlineService.getDownloadSettings()
        wifiOnlyEnabled = settings.wifiOnlyDownloads
        autoDeleteEnabled = settings.autoDeleteUnused

        // Find matching storage limit option
        let currentLimit = offlineService.storageLimit
        selectedLimit = StorageLimitOption.allCases.first { $0.bytes == currentLimit } ?? .default
    }

    private func loadStorageBreakdown() async {
        let info = await offlineService.getStorageInfo()
        let downloads = offlineService.getDownloadedContent()

        // Calculate breakdown by type
        var byType: [OfflineContentType: Int64] = [:]
        for content in downloads {
            byType[content.contentType, default: 0] += content.fileSize
        }

        storageBreakdown = StorageBreakdown(
            total: info.used,
            limit: info.limit,
            byType: byType,
            cacheSize: await getCacheSize()
        )
    }

    private func getCacheSize() async -> Int64 {
        await OfflineCacheService.shared.getCacheSize()
    }

    private func clearAllData() async {
        isClearing = true
        defer { isClearing = false }

        try? await offlineService.deleteAllDownloads()
        await offlineService.invalidateAllCaches()
        await loadStorageBreakdown()
    }
}

// MARK: - Storage Limit Row

private struct StorageLimitRow: View {
    let option: StorageLimitOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .foregroundStyle(.primary)

                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Storage Breakdown View

private struct StorageBreakdownView: View {
    let breakdown: StorageBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Overall usage bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Total Used")
                        .font(.subheadline)
                    Spacer()
                    Text("\(breakdown.totalFormatted) of \(breakdown.limitFormatted)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))

                        // Segments
                        HStack(spacing: 1) {
                            ForEach(breakdown.segments, id: \.type) { segment in
                                Rectangle()
                                    .fill(segment.type.color)
                                    .frame(width: geometry.size.width * segment.percentage)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(height: 8)
            }

            // Legend
            VStack(alignment: .leading, spacing: 8) {
                ForEach(breakdown.segments, id: \.type) { segment in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(segment.type.color)
                            .frame(width: 10, height: 10)

                        Text(segment.type.displayName)
                            .font(.caption)

                        Spacer()

                        Text(segment.sizeFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Cache row
                if breakdown.cacheSize > 0 {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 10, height: 10)

                        Text("Cached Data")
                            .font(.caption)

                        Spacer()

                        Text(ByteCountFormatter.string(fromByteCount: breakdown.cacheSize, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Storage Breakdown Model

private struct StorageBreakdown {
    let total: Int64
    let limit: Int64
    let byType: [OfflineContentType: Int64]
    let cacheSize: Int64

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var limitFormatted: String {
        ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
    }

    var segments: [StorageSegment] {
        byType.map { type, size in
            StorageSegment(
                type: type,
                size: size,
                percentage: limit > 0 ? CGFloat(size) / CGFloat(limit) : 0
            )
        }
        .sorted { $0.size > $1.size }
    }
}

private struct StorageSegment {
    let type: OfflineContentType
    let size: Int64
    let percentage: CGFloat

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Content Type Color Extension

private extension OfflineContentType {
    var color: Color {
        switch self {
        case .exercise:
            return .blue
        case .sleepStory:
            return .indigo
        case .soundscape:
            return .green
        case .programModule:
            return .teal
        }
    }
}

// MARK: - Storage Limit Option Extension

private extension StorageLimitOption {
    var description: String {
        switch self {
        case .small:
            return "Minimal storage use"
        case .medium:
            return "Recommended for most users"
        case .large:
            return "More content available offline"
        case .extraLarge:
            return "Maximum offline content"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        OfflineStorageSettingsView()
    }
}
#endif
