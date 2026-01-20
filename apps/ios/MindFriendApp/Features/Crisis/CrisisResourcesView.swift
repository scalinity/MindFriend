import SwiftUI

struct CrisisResourcesView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    @State private var resources: [CrisisResource] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Emergency banner
                    EmergencyBanner()

                    // Message
                    VStack(spacing: 12) {
                        Text("You're not alone")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("If you're experiencing a mental health crisis, please reach out to one of these resources. Help is available 24/7.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)

                    NavigationLink {
                        SafetyPlanView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "heart.shield.fill")
                                .font(.title3)
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("View My Safety Plan")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Personal steps you chose for difficult moments")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)

                    // Resources list
                    if isLoading {
                        ProgressView()
                            .padding(.top, 20)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(resources) { resource in
                                CrisisResourceCard(resource: resource)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Additional support
                    VStack(spacing: 12) {
                        Text("Additional Support")
                            .font(.headline)

                        Text("Remember that MindFriend is not a replacement for professional mental health care. If you need ongoing support, please consult a healthcare provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    Spacer(minLength: 32)
                }
                .padding(.vertical)
            }
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
            resources = try await container.supabaseDataService.getCrisisResources()
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
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text("Emergency?")
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            Text("If you are in immediate danger, call your local emergency services (911 in the US)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: "tel://911") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Call Emergency Services")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.white)
                    .foregroundStyle(.red)
                    .cornerRadius(25)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct CrisisResourceCard: View {
    let resource: CrisisResource

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(resource.name)
                    .font(.headline)
                Spacer()
                Text(resource.countryCode)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }

            Text(resource.available)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let phone = resource.phone {
                    Button {
                        if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(phone, systemImage: "phone.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
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
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
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
        )
    ]
}

#Preview {
    CrisisResourcesView()
        .environmentObject(DependencyContainer())
}
