import SwiftUI

struct CrisisResourcesView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    @State private var resources: [CrisisResource] = CrisisResource.fallbackResources
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Emergency banner
                    EmergencyBanner()

                    // Message
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("You're not alone")
                            .font(.title2)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.bold)

                        Text(
                            "If you're experiencing a mental health crisis, please reach out to one of these resources. Help is available 24/7."
                        )
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    NavigationLink {
                        SafetyPlanView()
                    } label: {
                        HStack(spacing: SupportTheme.Spacing.s) {
                            Image(systemName: "heart.shield.fill")
                                .font(.title3)
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                Text("View My Safety Plan")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                    .foregroundStyle(SupportTheme.textPrimary)
                                Text("Personal steps you chose for difficult moments")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .supportCard()
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)

                    // Resources list
                    if isLoading && resources.isEmpty {
                        ProgressView()
                            .padding(.top, SupportTheme.Spacing.l)
                    } else {
                        VStack(spacing: SupportTheme.Spacing.m) {
                            ForEach(resources) { resource in
                                CrisisResourceCard(resource: resource)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Additional support
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("Additional Support")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Text(
                            "Remember that MindFriend is not a replacement for professional mental health care. If you need ongoing support, please consult a healthcare provider."
                        )
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    }
                    .supportCard()
                    .padding(.horizontal)

                    Spacer(minLength: SupportTheme.Spacing.xl)
                }
                .padding(.vertical)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Crisis Resources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadResources()
            }
        }
    }

    private func loadResources() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await container.supabaseDataService.getCrisisResources()
            if !fetched.isEmpty { resources = fetched }
        } catch {
            // Load fallback resources
            resources = CrisisResource.fallbackResources
        }
    }
}

struct CrisisResourcesResponse: Decodable {
    let resources: [CrisisResource]
}

struct EmergencyBanner: View {
    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SupportTheme.textPrimary)
                Text("Emergency?")
                    .fontWeight(.bold)
                    .foregroundStyle(SupportTheme.textPrimary)
            }

            Text("If you are in immediate danger, call your local emergency services (911 in the US)")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.9))
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: "tel://911") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Call Emergency Services")
                    .fontWeight(.semibold)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .padding(.vertical, SupportTheme.Spacing.s)
                    .background(SupportTheme.textPrimary)
                    .foregroundStyle(.red)
                    .cornerRadius(SupportTheme.controlRadius)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red)
        .cornerRadius(SupportTheme.controlRadius)
        .padding(.horizontal)
    }
}

struct CrisisResourceCard: View {
    let resource: CrisisResource

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text(resource.name)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(resource.countryCode)
                    .font(.caption)
                    .padding(.horizontal, SupportTheme.Spacing.xs)
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)
            }

            Text(resource.available)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            HStack(spacing: SupportTheme.Spacing.s) {
                if let phone = resource.phone {
                    Button {
                        if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(phone, systemImage: "phone.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.supportSecondary)
                }

                if let sms = resource.sms {
                    Button {
                        if let url = URL(string: "sms:\(sms)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Text", systemImage: "message.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.supportSecondary)
                }

                if let chat = resource.chat {
                    Button {
                        if let url = URL(string: chat) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Chat", systemImage: "bubble.left.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.supportSecondary)
                }
            }
        }
        .supportCard()
    }
}

extension CrisisResource {
    static let fallbackResources: [CrisisResource] = [
        CrisisResource(
            id: "1",
            country: "United States",
            countryCode: "US",
            name: "National Suicide Prevention Lifeline",
            phone: "988",
            sms: "988",
            chat: "https://988lifeline.org/chat",
            available: "24/7"
        ),
        CrisisResource(
            id: "2",
            country: "United States",
            countryCode: "US",
            name: "Crisis Text Line",
            phone: nil,
            sms: "741741",
            chat: nil,
            available: "24/7"
        ),
        CrisisResource(
            id: "3",
            country: "International",
            countryCode: "INT",
            name: "International Association for Suicide Prevention",
            phone: nil,
            sms: nil,
            chat: "https://www.iasp.info/resources/Crisis_Centres/",
            available: "Directory of crisis centers worldwide"
        ),
    ]
}

#Preview {
    CrisisResourcesView()
        .environmentObject(DependencyContainer())
}
