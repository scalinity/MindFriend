//
//  OfflineDownloadsView.swift
//  MindFriendApp
//
//  View for managing downloaded offline content
//

import SwiftUI

/// Main view for managing downloaded content
struct OfflineDownloadsView: View {
    @StateObject private var offlineService = OfflineContentService.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var showDeleteAllConfirmation = false
    @State private var showStorageSettings = false
    @State private var storageInfo: StorageInfo?

    var body: some View {
        List {
            // Storage section
            Section {
                StorageUsageRow(
                    storageInfo: storageInfo,
                    onManageTapped: { showStorageSettings = true }
                )
            } header: {
                Text("Storage")
            }

            // Download settings section
            Section {
                DownloadSettingsRow(settings: downloadManager.settings)
            } header: {
                Text("Download Settings")
            }

            // Active downloads section
            if !downloadManager.activeTasks.isEmpty {
                Section {
                    ForEach(downloadManager.activeTasks) { task in
                        ActiveDownloadRow(task: task)
                    }
                } header: {
                    Text("Active Downloads")
                }
            }

            // Downloaded content section
            Section {
                if downloadManager.downloads.isEmpty {
                    EmptyDownloadsRow()
                } else {
                    ForEach(downloadManager.downloads) { content in
                        DownloadedContentRow(content: content)
                    }
                    .onDelete(perform: deleteDownloads)
                }
            } header: {
                Text("Downloaded Content (\(downloadManager.downloads.count))")
            }

            // Delete all button
            if !downloadManager.downloads.isEmpty {
                Section {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete All Downloads")
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .task {
            storageInfo = await offlineService.getStorageInfo()
        }
        .refreshable {
            storageInfo = await offlineService.getStorageInfo()
        }
        .sheet(isPresented: $showStorageSettings) {
            NavigationStack {
                OfflineStorageSettingsView()
            }
        }
        .confirmationDialog(
            "Delete All Downloads?",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task {
                    try? await offlineService.deleteAllDownloads()
                    storageInfo = await offlineService.getStorageInfo()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded content. You can re-download content anytime.")
        }
    }

    private func deleteDownloads(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let content = downloadManager.downloads[index]
                try? await offlineService.deleteDownload(contentId: content.id)
            }
            storageInfo = await offlineService.getStorageInfo()
        }
    }
}

// MARK: - Storage Usage Row

private struct StorageUsageRow: View {
    let storageInfo: StorageInfo?
    let onManageTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let info = storageInfo {
                HStack {
                    Text("Used")
                    Spacer()
                    Text("\(info.usedFormatted) of \(info.limitFormatted)")
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: info.usagePercentage)
                    .tint(progressColor(for: info))

                HStack {
                    Text("\(info.itemCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Manage Storage") {
                        onManageTapped()
                    }
                    .font(.caption)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private func progressColor(for info: StorageInfo) -> Color {
        if info.isOverLimit {
            return .red
        } else if info.isNearLimit {
            return .orange
        } else {
            return .accentColor
        }
    }
}

// MARK: - Download Settings Row

private struct DownloadSettingsRow: View {
    let settings: DownloadSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundStyle(settings.wifiOnlyDownloads ? .green : .secondary)
                Text("WiFi only")
                Spacer()
                Text(settings.wifiOnlyDownloads ? "On" : "Off")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Active Download Row

private struct ActiveDownloadRow: View {
    let task: DownloadTask
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: task.contentType.icon)
                    .foregroundStyle(.accent)

                VStack(alignment: .leading) {
                    Text(task.title)
                        .font(.headline)

                    Text(task.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Action button
                Button {
                    handleAction()
                } label: {
                    Image(systemName: actionIcon)
                        .font(.title3)
                }
                .buttonStyle(.borderless)
            }

            if task.status == .downloading {
                ProgressView(value: task.progress)
                    .tint(.accent)

                HStack {
                    Text("\(task.progressPercentage)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(task.formattedEstimatedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if task.status == .failed, let error = task.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var actionIcon: String {
        switch task.status {
        case .queued, .downloading:
            return "xmark.circle"
        case .paused:
            return "play.circle"
        case .failed:
            return "arrow.clockwise.circle"
        default:
            return "xmark.circle"
        }
    }

    private func handleAction() {
        switch task.status {
        case .queued, .downloading:
            downloadManager.cancelDownload(taskId: task.id)
        case .paused:
            downloadManager.resumeDownload(taskId: task.id)
        case .failed:
            downloadManager.resumeDownload(taskId: task.id)
        default:
            break
        }
    }
}

// MARK: - Downloaded Content Row

private struct DownloadedContentRow: View {
    let content: DownloadedContent
    @StateObject private var offlineService = OfflineContentService.shared
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: content.contentType.icon)
                .font(.title2)
                .foregroundStyle(.accent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.headline)

                HStack {
                    Text(content.contentType.displayName)
                    Text("•")
                    Text(content.formattedSize)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("Downloaded \(content.downloadedAgo)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Delete Download?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await offlineService.deleteDownload(contentId: content.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \"\(content.title)\" from downloads?")
        }
    }
}

// MARK: - Empty Downloads Row

private struct EmptyDownloadsRow: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No Downloaded Content")
                .font(.headline)

            Text("Download exercises, meditations, and sleep content to use offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        OfflineDownloadsView()
    }
}
#endif
