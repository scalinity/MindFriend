import SwiftUI

/// Indicator shown when AI companion used memory in a response
struct MemoryUsageIndicator: View {
    let memoryIds: [String]
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.caption2)
                Text("Memory used")
                    .font(.caption2)
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Popover showing which memories were used
struct MemoryUsagePopover: View {
    @EnvironmentObject private var memoryService: CompanionMemoryService
    let memoryIds: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("Memories Used")
                    .font(.headline)
            }

            if usedMemories.isEmpty {
                Text("Memory details not available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(usedMemories) { memory in
                    HStack(spacing: 8) {
                        Image(systemName: memory.category.icon)
                            .foregroundStyle(memory.category.color)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(memory.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(memory.content)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 300)
    }

    private var usedMemories: [CompanionMemory] {
        memoryService.memories.filter { memoryIds.contains($0.id) }
    }
}

/// Small inline indicator for use in message bubbles
struct MemoryUsedBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "brain.head.profile")
            Image(systemName: "sparkle")
        }
        .font(.system(size: 10))
        .foregroundStyle(.purple)
    }
}

// MARK: - Preview

#Preview("Indicator") {
    MemoryUsageIndicator(memoryIds: ["1", "2", "3"])
}

#Preview("Badge") {
    MemoryUsedBadge()
}
