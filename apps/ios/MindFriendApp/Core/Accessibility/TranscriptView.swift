// Spec 14: Transcript View
// View and manage transcripts of audio/video content

import SwiftUI

struct TranscriptView: View {
    @State private var transcripts: [Transcript] = [
        Transcript(id: UUID(), title: "Daily Affirmation", duration: "2:30", type: "Audio"),
        Transcript(id: UUID(), title: "Meditation Guide", duration: "10:00", type: "Video"),
        Transcript(id: UUID(), title: "Exercise Tutorial", duration: "5:45", type: "Video")
    ]
    @State private var selectedTranscript: Transcript?
    @State private var searchText = ""

    var filteredTranscripts: [Transcript] {
        if searchText.isEmpty {
            return transcripts
        }
        return transcripts.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredTranscripts.isEmpty {
                    ContentUnavailableView("No Transcripts", systemImage: "doc.text", description: Text("Transcripts will appear here when available"))
                } else {
                    ForEach(filteredTranscripts) { transcript in
                        NavigationLink(destination: TranscriptDetailView(transcript: transcript)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(transcript.title)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                HStack {
                                    Label(transcript.type, systemImage: transcript.type == "Audio" ? "waveform.circle" : "video.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(transcript.duration)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search transcripts")
            .navigationTitle("Transcripts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TranscriptDetailView: View {
    let transcript: Transcript

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(transcript.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    HStack {
                        Label(transcript.type, systemImage: "info.circle")
                        Spacer()
                        Text(transcript.duration)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Divider()

                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
                    .lineSpacing(1.5)

                Spacer()
            }
            .padding()
        }
        .navigationTitle(transcript.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct Transcript: Identifiable {
    let id: UUID
    let title: String
    let duration: String
    let type: String
}

#Preview {
    TranscriptView()
}
