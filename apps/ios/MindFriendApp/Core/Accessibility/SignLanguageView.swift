// Spec 14: Sign Language Videos
// Browse and select sign language videos by type and language preference

import SwiftUI

struct SignLanguageView: View {
    @State private var selectedLanguage = "en"
    @State private var selectedType = "general"
    @State private var searchText = ""

    let signLanguageVideos = [
        SignLanguageVideoItem(id: UUID(), title: "Welcome to MindFriend", type: "general", language: "en", duration: "1:30"),
        SignLanguageVideoItem(id: UUID(), title: "How to Use Chat", type: "tutorial", language: "en", duration: "2:45"),
        SignLanguageVideoItem(id: UUID(), title: "Daily Quests Explained", type: "tutorial", language: "en", duration: "3:15"),
        SignLanguageVideoItem(id: UUID(), title: "Mood Tracking Basics", type: "tutorial", language: "en", duration: "2:00"),
        SignLanguageVideoItem(id: UUID(), title: "Meditation Guides", type: "exercise", language: "en", duration: "5:30"),
        SignLanguageVideoItem(id: UUID(), title: "Breathing Techniques", type: "exercise", language: "en", duration: "4:15"),
        SignLanguageVideoItem(id: UUID(), title: "Grounding Exercises", type: "exercise", language: "en", duration: "3:45"),
        SignLanguageVideoItem(id: UUID(), title: "Crisis Support Resources", type: "support", language: "en", duration: "2:30")
    ]

    var filteredVideos: [SignLanguageVideoItem] {
        signLanguageVideos.filter { video in
            (video.language == selectedLanguage) &&
            (selectedType == "all" || video.type == selectedType) &&
            (searchText.isEmpty || video.title.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Language") {
                    Picker("Preferred Language", selection: $selectedLanguage) {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("ASL (American)").tag("asl")
                        Text("BSL (British)").tag("bsl")
                    }
                    .pickerStyle(.menu)
                }

                Section("Video Type") {
                    Picker("Filter by Type", selection: $selectedType) {
                        Text("All Videos").tag("all")
                        Text("General").tag("general")
                        Text("Tutorials").tag("tutorial")
                        Text("Exercises").tag("exercise")
                        Text("Support").tag("support")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Available Videos") {
                    if filteredVideos.isEmpty {
                        ContentUnavailableView(
                            "No Videos Found",
                            systemImage: "hand.raised.fill",
                            description: Text("No sign language videos available for your selection")
                        )
                    } else {
                        ForEach(filteredVideos) { video in
                            NavigationLink(destination: SignLanguageVideoPlayerView(video: video)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.title)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    HStack {
                                        Label(video.type.capitalized, systemImage: "video.fill")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(video.duration)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search videos")
            .navigationTitle("Sign Language Videos")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SignLanguageVideoPlayerView: View {
    let video: SignLanguageVideoItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Color.gray.opacity(0.3)
                    .frame(height: 300)
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("Sign Language Video")
                        .font(.headline)
                    Text("Video player would display here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 12) {
                Text(video.title)
                    .font(.title2)
                    .fontWeight(.bold)
                HStack {
                    Label(video.type.capitalized, systemImage: "video.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(video.duration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            Spacer()
        }
        .padding()
        .navigationTitle(video.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SignLanguageVideoItem: Identifiable {
    let id: UUID
    let title: String
    let type: String
    let language: String
    let duration: String
}

#Preview {
    SignLanguageView()
}
