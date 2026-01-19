//
//  OfflineBanner.swift
//  MindFriendApp
//
//  Banner and indicator views for offline status
//

import SwiftUI

// MARK: - Offline Banner

/// Banner displayed when the device is offline
struct OfflineBanner: View {
    @StateObject private var offlineService = OfflineContentService.shared
    @State private var isExpanded = false

    var body: some View {
        if !offlineService.isOnline {
            VStack(spacing: 0) {
                // Compact banner
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.subheadline)

                        Text("You're offline")
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        if offlineService.pendingSyncCount > 0 {
                            Text("\(offlineService.pendingSyncCount) pending")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // Expanded content
                if isExpanded {
                    OfflineInfoContent()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Offline Info Content

private struct OfflineInfoContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Available offline
            VStack(alignment: .leading, spacing: 8) {
                Label("Available offline", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                ForEach([OfflineFeature.downloadedContent, .moodCheckIn, .questCompletion, .exerciseTracking], id: \.self) { feature in
                    FeatureAvailabilityRow(feature: feature, isAvailable: true)
                }
            }

            Divider()

            // Requires internet
            VStack(alignment: .leading, spacing: 8) {
                Label("Requires internet", systemImage: "wifi")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach([OfflineFeature.aiChat, .voiceMode, .circles], id: \.self) { feature in
                    FeatureAvailabilityRow(feature: feature, isAvailable: false)
                }
            }

            // Downloads button
            NavigationLink {
                OfflineDownloadsView()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("View Downloaded Content")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
    }
}

// MARK: - Feature Availability Row

private struct FeatureAvailabilityRow: View {
    let feature: OfflineFeature
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isAvailable ? "checkmark" : "xmark")
                .font(.caption)
                .foregroundStyle(isAvailable ? .green : .red)
                .frame(width: 16)

            Text(feature.displayName)
                .font(.subheadline)
                .foregroundStyle(isAvailable ? .primary : .secondary)
        }
        .padding(.leading, 8)
    }
}

// MARK: - Compact Offline Indicator

/// Small indicator for navigation bar or status display
struct OfflineIndicator: View {
    @StateObject private var offlineService = OfflineContentService.shared

    var body: some View {
        if !offlineService.isOnline {
            HStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                    .font(.caption2)
                Text("Offline")
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Sync Status Banner

/// Banner showing sync status
struct SyncStatusBanner: View {
    @StateObject private var syncManager = SyncQueueManager.shared

    var body: some View {
        if syncManager.pendingSyncCount > 0 || syncManager.isSyncing {
            HStack(spacing: 8) {
                if syncManager.isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }

                Text(syncManager.syncStatusMessage)
                    .font(.subheadline)

                Spacer()

                if !syncManager.isSyncing && syncManager.pendingSyncCount > 0 {
                    Button("Sync Now") {
                        Task {
                            await syncManager.syncNow()
                        }
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Connection Type Badge

/// Badge showing current connection type
struct ConnectionTypeBadge: View {
    @StateObject private var connectivity = ConnectivityMonitor.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: connectivity.connectionType.icon)
                .font(.caption2)
            Text(connectivity.connectionType.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch connectivity.connectionType {
        case .wifi:
            return .green.opacity(0.15)
        case .cellular:
            return .blue.opacity(0.15)
        case .none:
            return .red.opacity(0.15)
        default:
            return .gray.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch connectivity.connectionType {
        case .wifi:
            return .green
        case .cellular:
            return .blue
        case .none:
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Download Button

/// Reusable download button for content items
struct DownloadButton: View {
    let content: any DownloadableContent
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var offlineService = OfflineContentService.shared
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if downloadManager.isDownloaded(contentId: content.id) {
                // Downloaded state
                Menu {
                    Button(role: .destructive) {
                        Task {
                            try? await offlineService.deleteDownload(contentId: content.id)
                        }
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } label: {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            } else if let task = downloadManager.downloadTask(for: content.id) {
                // Downloading state
                HStack(spacing: 8) {
                    if task.status == .downloading {
                        ProgressView(value: task.progress)
                            .frame(width: 40)
                    }

                    Button {
                        downloadManager.cancelDownload(taskId: task.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Available for download
                Button {
                    Task {
                        do {
                            try await offlineService.download(content)
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title3)
                        Text(ByteCountFormatter.string(fromByteCount: content.estimatedSize, countStyle: .file))
                            .font(.caption2)
                    }
                    .foregroundStyle(.accent)
                }
            }
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Offline Banner") {
    VStack {
        OfflineBanner()
        Spacer()
    }
}

#Preview("Indicators") {
    VStack(spacing: 20) {
        OfflineIndicator()
        ConnectionTypeBadge()
        SyncStatusBanner()
    }
    .padding()
}
#endif
