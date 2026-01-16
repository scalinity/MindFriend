import SwiftUI

/// View for managing family members
struct FamilyMembersView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var members: [FamilyWellnessMember] = []
    @State private var isLoading = false
    let familyGroup: FamilyWellnessGroup

    var body: some View {
        ZStack {
            if members.isEmpty && !isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                    Text("No family members yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
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
        .navigationTitle("Family Members")
        .task {
            await loadMembers()
        }
    }

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            members = try await container.familyService.fetchFamilyMembers()
        } catch {
            print("Failed to load members: \(error)")
        }
    }
}

// MARK: - Member Row View

struct MemberRowView: View {
    let member: FamilyWellnessMember

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            VStack(alignment: .center) {
                Text(String(member.nickname?.prefix(1).uppercased() ?? "?"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(roleColor(member.role))
                    .clipShape(Circle())
            }

            // Member Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.nickname ?? "Family Member")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(member.role.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(roleColor(member.role).opacity(0.1))
                        .foregroundStyle(roleColor(member.role))
                        .cornerRadius(4)
                }

                if let age = member.calculatedAge {
                    Text("Age \(age)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Sharing preferences
                HStack(spacing: 8) {
                    if member.shareMoodWithFamily {
                        Label("Mood", systemImage: "smiley")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    if member.shareActivityWithFamily {
                        Label("Activity", systemImage: "figure.walk")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if member.shareAchievementsWithFamily {
                        Label("Achievements", systemImage: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.white)
        .cornerRadius(12)
    }

    private func roleColor(_ role: FamilyRole) -> Color {
        switch role {
        case .admin: return .red
        case .parent: return .blue
        case .teen: return .green
        case .child: return .purple
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
