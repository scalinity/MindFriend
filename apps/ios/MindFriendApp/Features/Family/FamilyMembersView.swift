import SwiftUI

/// View for managing family members
struct FamilyMembersView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var members: [FamilyWellnessMember] = []
    @State private var isLoading = false
    @State private var loadError: String?
    let familyGroup: FamilyWellnessGroup

    var body: some View {
        ZStack {
            if members.isEmpty && !isLoading {
                VStack(spacing: SupportTheme.Spacing.m) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("No family members yet")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SupportTheme.surface)
            } else {
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(members, id: \.id) { member in
                            MemberRowView(member: member)
                        }
                    }
                    .padding()
                }
            }

            if isLoading {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let loadError {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Label("Family members unavailable", systemImage: "exclamationmark.triangle")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    Text(loadError)
                    Button("Try Again") { Task { await loadMembers() } }
                        .buttonStyle(.supportSecondary)
                }
                .supportCard()
                .padding(SupportTheme.Spacing.m)
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Family Members")
        .task {
            await loadMembers()
        }
    }

    private func loadMembers() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            members = try await container.familyService.fetchFamilyMembers()
        } catch {
            loadError = error.localizedDescription
            Log.family.error("Failed to load members", error: error)
        }
    }
}

// MARK: - Member Row View

struct MemberRowView: View {
    let member: FamilyWellnessMember

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            // Avatar
            VStack(alignment: .center) {
                Text(String(member.nickname?.prefix(1).uppercased() ?? "?"))
                    .font(.headline)
                    .foregroundStyle(SupportTheme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(roleColor(member.role))
                    .clipShape(Circle())
            }

            // Member Info
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack {
                    Text(member.nickname ?? "Family Member")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(member.role.displayName)
                        .font(.caption)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(roleColor(member.role).opacity(0.1))
                        .foregroundStyle(roleColor(member.role))
                        .cornerRadius(SupportTheme.controlRadius)
                }

                if let age = member.calculatedAge {
                    Text("Age \(age)")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                // Sharing preferences
                HStack(spacing: SupportTheme.Spacing.xs) {
                    if member.shareMoodWithFamily {
                        Label("Mood", systemImage: "smiley")
                            .font(.caption2)
                            .foregroundStyle(SupportTheme.accent)
                    }
                    if member.shareActivityWithFamily {
                        Label("Activity", systemImage: "figure.walk")
                            .font(.caption2)
                            .foregroundStyle(SupportTheme.accent)
                    }
                    if member.shareAchievementsWithFamily {
                        Label("Achievements", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(SupportTheme.accent)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
    }

    private func roleColor(_ role: FamilyRole) -> Color {
        switch role {
        case .admin: return .red
        case .parent: return SupportTheme.accent
        case .teen: return SupportTheme.accent
        case .child: return SupportTheme.accent
        }
    }
}

#Preview {
    NavigationStack {
        FamilyMembersView(
            familyGroup: .init(
                id: "test",
                name: "Test Family",
                adminUserId: "admin",
                circleId: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        .environmentObject(DependencyContainer.preview)
    }
}
