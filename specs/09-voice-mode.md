# 09 - Voice Mode (Big Bet)

## Overview

Talk to your AI companion instead of typing. Voice mode transforms MindFriend from a text-based app into a conversational experience—like having a supportive friend on call. This is particularly valuable during moments when typing feels difficult: while walking, lying in bed anxious at night, or during emotional overwhelm.

**Priority:** Future (Big Bet)
**Impact:** Differentiation ↑↑↑, Engagement ↑↑, Accessibility ↑↑
**Complexity:** High

---

## User Stories

### Core Voice Experience

- As a **user walking**, I want to talk to my AI companion hands-free so that I can process my thoughts while moving
- As a **user in bed at 3am**, I want to speak quietly to MindFriend so that I can get support without fully waking up
- As a **user feeling overwhelmed**, I want to just talk (not type) so that I can express myself more naturally

### Accessibility

- As a **user with motor difficulties**, I want voice input so that I can use the app without typing
- As a **user with visual impairment**, I want audio responses so that I don't need to read the screen
- As a **user with dyslexia**, I want to speak instead of write so that communication is easier

### Mode Flexibility

- As a **user in a quiet environment**, I want to switch to text mode so that I'm not disturbing others
- As a **user in public**, I want headphone support so that my conversation stays private

---

## Product Requirements

### Must Have (MVP)

1. **Speech-to-Text Input**
   - Push-to-talk button in chat view
   - Real-time transcription display
   - Support for continuous dictation
   - Automatic punctuation

2. **Text-to-Speech Output**
   - AI responses read aloud automatically
   - Natural-sounding voice (iOS system or premium voice)
   - Pause/stop controls
   - Speed adjustment (0.75x to 1.5x)

3. **Voice Mode Toggle**
   - Easy switch between voice and text modes
   - Remember user's preference
   - Per-conversation setting option

4. **Basic Voice Settings**
   - Enable/disable voice output
   - Voice speed slider
   - Auto-play responses toggle

### Nice to Have (V2)

1. **Hands-Free Mode**
   - "Hey MindFriend" wake word activation
   - Continuous listening mode
   - Background audio support

2. **Premium Voices**
   - Multiple voice options (warm, calm, professional)
   - Male/female voice choices
   - Custom voice personalities

3. **Voice Emotion Detection**
   - Detect stress/anxiety in user's voice
   - Adjust AI response tone accordingly
   - Log emotional markers for insights

4. **Audio Sessions**
   - Voice-only guided exercises
   - Breathing exercise with audio cues
   - Meditation with voice guidance

5. **Transcript Export**
   - Save voice conversations as text
   - Share conversation summaries
   - Journal entry creation from voice

6. **Multi-Language Voice**
   - Speech recognition for other languages
   - TTS in user's preferred language
   - Real-time translation option

### Out of Scope

- Video calling
- Human therapist voice calls
- Voice cloning/custom voice synthesis
- Real-time voice modification
- Group voice conversations
- Voice messages to circles (use existing text)

---

## Technical Design

### Data Model Changes

#### Migration: `20250115000009_voice_mode.sql`

```sql
-- Voice settings per user
CREATE TABLE voice_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  voice_enabled BOOLEAN DEFAULT TRUE,
  voice_speed FLOAT DEFAULT 1.0,
  auto_play_responses BOOLEAN DEFAULT TRUE,
  preferred_voice TEXT DEFAULT 'system', -- 'system', 'premium_calm', etc.
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Track voice usage for analytics
CREATE TABLE voice_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  input_duration_seconds INT DEFAULT 0, -- Total speech input time
  output_duration_seconds INT DEFAULT 0, -- Total TTS output time
  messages_count INT DEFAULT 0
);

-- Optional: Voice emotion markers (V2)
CREATE TABLE voice_emotion_markers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  detected_emotion TEXT, -- 'calm', 'anxious', 'stressed', 'happy'
  confidence FLOAT,
  audio_features JSONB, -- pitch, tempo, volume variance
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_voice_settings_user_id ON voice_settings(user_id);
CREATE INDEX idx_voice_sessions_user_id ON voice_sessions(user_id);
CREATE INDEX idx_voice_sessions_conversation_id ON voice_sessions(conversation_id);

-- RLS
ALTER TABLE voice_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_emotion_markers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own voice settings" ON voice_settings
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users view own voice sessions" ON voice_sessions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users view own emotion markers" ON voice_emotion_markers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM messages
      WHERE id = message_id
      AND EXISTS (
        SELECT 1 FROM conversations
        WHERE id = messages.conversation_id
        AND user_id = auth.uid()
      )
    )
  );
```

### iOS Implementation

#### Speech Recognition Service

**File:** `apps/ios/MindFriendApp/Core/Services/SpeechService.swift`

```swift
import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechService: ObservableObject {
    // MARK: - Published Properties
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var isAuthorized = false
    @Published var isSpeaking = false
    @Published var speechProgress: Double = 0

    // MARK: - Private Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechSynthesizerDelegate?

    // MARK: - Settings
    var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    var autoPlayResponses = true

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechDelegate = SpeechSynthesizerDelegate(service: self)
        synthesizer.delegate = speechDelegate
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        // Speech recognition authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        // Microphone authorization
        let micStatus: Bool
        if #available(iOS 17.0, *) {
            micStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            micStatus = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        isAuthorized = speechStatus == .authorized && micStatus
    }

    // MARK: - Speech-to-Text

    func startListening() throws {
        guard isAuthorized else {
            throw SpeechError.notAuthorized
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        // Cancel any existing task
        stopListening()

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }

            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    func clearTranscription() {
        transcribedText = ""
    }

    // MARK: - Text-to-Speech

    func speak(_ text: String) {
        // Stop any current speech
        stopSpeaking()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = speechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Use a natural voice if available
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        speechProgress = 0
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func continueSpeaking() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Progress Tracking

    func updateProgress(_ progress: Double) {
        speechProgress = progress
    }

    func finishedSpeaking() {
        isSpeaking = false
        speechProgress = 0
    }
}

// MARK: - Speech Synthesizer Delegate

private class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    weak var service: SpeechService?

    init(service: SpeechService) {
        self.service = service
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            service?.finishedSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let progress = Double(characterRange.location + characterRange.length) / Double(utterance.speechString.count)
        Task { @MainActor in
            service?.updateProgress(progress)
        }
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case requestCreationFailed
    case audioSessionFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition is not authorized. Please enable it in Settings."
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .requestCreationFailed:
            return "Failed to create speech recognition request."
        case .audioSessionFailed:
            return "Failed to configure audio session."
        }
    }
}
```

#### Voice Models

```swift
// Models.swift additions

struct VoiceSettings: Codable {
    let id: UUID
    let userId: UUID
    var voiceEnabled: Bool
    var voiceSpeed: Double
    var autoPlayResponses: Bool
    var preferredVoice: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case voiceEnabled = "voice_enabled"
        case voiceSpeed = "voice_speed"
        case autoPlayResponses = "auto_play_responses"
        case preferredVoice = "preferred_voice"
    }
}

struct VoiceSession: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let conversationId: UUID?
    let startedAt: Date
    var endedAt: Date?
    var inputDurationSeconds: Int
    var outputDurationSeconds: Int
    var messagesCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case conversationId = "conversation_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case inputDurationSeconds = "input_duration_seconds"
        case outputDurationSeconds = "output_duration_seconds"
        case messagesCount = "messages_count"
    }
}
```

#### Voice Chat View

**File:** `apps/ios/MindFriendApp/Features/Chat/VoiceChatView.swift`

```swift
import SwiftUI

struct VoiceChatView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var speechService = SpeechService()
    @ObservedObject var viewModel: ChatViewModel

    @State private var voiceMode = true
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Mode toggle
            modeToggle

            // Chat messages
            messagesList

            // Voice input area
            if voiceMode {
                voiceInputArea
            } else {
                textInputArea
            }
        }
        .navigationTitle("AI Companion")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            VoiceSettingsView()
        }
        .task {
            await speechService.requestAuthorization()
        }
        .onChange(of: viewModel.lastAIMessage) { _, newMessage in
            if voiceMode && speechService.autoPlayResponses, let message = newMessage {
                speechService.speak(message.content)
            }
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        Picker("Input Mode", selection: $voiceMode) {
            Label("Voice", systemImage: "mic.fill").tag(true)
            Label("Text", systemImage: "keyboard").tag(false)
        }
        .pickerStyle(.segmented)
        .padding()
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        VoiceMessageBubble(
                            message: message,
                            isSpeaking: speechService.isSpeaking && viewModel.lastAIMessage?.id == message.id,
                            onPlayTap: {
                                speechService.speak(message.content)
                            },
                            onStopTap: {
                                speechService.stopSpeaking()
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastId = viewModel.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Voice Input Area

    private var voiceInputArea: some View {
        VStack(spacing: 16) {
            // Transcription preview
            if !speechService.transcribedText.isEmpty {
                transcriptionPreview
            }

            // Voice controls
            HStack(spacing: 32) {
                // Cancel button (when listening)
                if speechService.isListening {
                    Button {
                        speechService.stopListening()
                        speechService.clearTranscription()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                }

                // Main microphone button
                microphoneButton

                // Send button (when we have text)
                if !speechService.transcribedText.isEmpty && !speechService.isListening {
                    Button {
                        sendVoiceMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.accentColor)
                    }
                }
            }

            // Status text
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var transcriptionPreview: some View {
        Text(speechService.transcribedText)
            .font(.body)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }

    private var microphoneButton: some View {
        Button {
            toggleListening()
        } label: {
            ZStack {
                Circle()
                    .fill(speechService.isListening ? Color.red : Color.accentColor)
                    .frame(width: 72, height: 72)

                if speechService.isListening {
                    // Pulsing animation when listening
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 4)
                        .frame(width: 88, height: 88)
                        .scaleEffect(speechService.isListening ? 1.2 : 1.0)
                        .opacity(speechService.isListening ? 0 : 1)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: speechService.isListening
                        )
                }

                Image(systemName: speechService.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            }
        }
        .disabled(!speechService.isAuthorized)
    }

    private var statusText: String {
        if !speechService.isAuthorized {
            return "Microphone access required"
        } else if speechService.isListening {
            return "Listening..."
        } else if !speechService.transcribedText.isEmpty {
            return "Tap send or continue speaking"
        } else {
            return "Tap to speak"
        }
    }

    // MARK: - Text Input (Fallback)

    private var textInputArea: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.accentColor)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func toggleListening() {
        if speechService.isListening {
            speechService.stopListening()
        } else {
            do {
                try speechService.startListening()
            } catch {
                print("Failed to start listening: \(error)")
            }
        }
    }

    private func sendVoiceMessage() {
        let text = speechService.transcribedText
        speechService.clearTranscription()
        viewModel.inputText = text
        Task { await viewModel.sendMessage() }
    }
}

// MARK: - Voice Message Bubble

struct VoiceMessageBubble: View {
    let message: Message
    let isSpeaking: Bool
    let onPlayTap: () -> Void
    let onStopTap: () -> Void

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(isUser ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(isUser ? .white : .primary)
                    .cornerRadius(16)

                // Play button for AI messages
                if !isUser {
                    Button {
                        isSpeaking ? onStopTap() : onPlayTap()
                    } label: {
                        Label(
                            isSpeaking ? "Stop" : "Play",
                            systemImage: isSpeaking ? "stop.fill" : "play.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
```

#### Voice Settings View

**File:** `apps/ios/MindFriendApp/Features/Profile/VoiceSettingsView.swift`

```swift
import SwiftUI

struct VoiceSettingsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var voiceEnabled = true
    @State private var voiceSpeed: Double = 1.0
    @State private var autoPlayResponses = true

    @StateObject private var speechService = SpeechService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Voice Mode", isOn: $voiceEnabled)
                } footer: {
                    Text("When enabled, you can speak to your AI companion and hear responses.")
                }

                Section("Speech Output") {
                    Toggle("Auto-Play AI Responses", isOn: $autoPlayResponses)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Speech Speed")
                            Spacer()
                            Text(speedLabel)
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $voiceSpeed, in: 0.5...2.0, step: 0.25)
                    }

                    Button {
                        speechService.speechRate = Float(voiceSpeed) * AVSpeechUtteranceDefaultSpeechRate
                        speechService.speak("This is how I'll sound at this speed.")
                    } label: {
                        Label("Test Voice", systemImage: "play.circle")
                    }
                }

                Section("Privacy") {
                    NavigationLink {
                        VoicePrivacyInfoView()
                    } label: {
                        Label("How Voice Data is Used", systemImage: "lock.shield")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        // Clear any stored voice data
                    } label: {
                        Label("Clear Voice History", systemImage: "trash")
                    }
                } footer: {
                    Text("Voice input is processed on-device and not stored on our servers.")
                }
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }

    private var speedLabel: String {
        switch voiceSpeed {
        case 0.5: return "0.5x (Slow)"
        case 0.75: return "0.75x"
        case 1.0: return "1x (Normal)"
        case 1.25: return "1.25x"
        case 1.5: return "1.5x"
        case 1.75: return "1.75x"
        case 2.0: return "2x (Fast)"
        default: return "\(voiceSpeed)x"
        }
    }

    private func saveSettings() {
        Task {
            // Save to Supabase
            try? await container.supabaseDataService.saveVoiceSettings(
                VoiceSettings(
                    id: UUID(),
                    userId: UUID(), // Get from auth
                    voiceEnabled: voiceEnabled,
                    voiceSpeed: voiceSpeed,
                    autoPlayResponses: autoPlayResponses,
                    preferredVoice: "system"
                )
            )
        }
    }
}

struct VoicePrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Voice Data Privacy")
                        .font(.title2.bold())

                    Text("MindFriend takes your privacy seriously. Here's how we handle voice data:")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    PrivacyPoint(
                        icon: "iphone",
                        title: "On-Device Processing",
                        description: "Speech recognition happens entirely on your device using Apple's built-in technology. Your voice never leaves your phone."
                    )

                    PrivacyPoint(
                        icon: "text.bubble",
                        title: "Text Only",
                        description: "Only the transcribed text is sent to our AI for response. We never receive or store audio recordings."
                    )

                    PrivacyPoint(
                        icon: "speaker.wave.2",
                        title: "Local Text-to-Speech",
                        description: "AI responses are spoken using your device's built-in voice synthesis. No audio data is transmitted."
                    )

                    PrivacyPoint(
                        icon: "trash",
                        title: "No Voice Storage",
                        description: "We don't store voice recordings, voice prints, or any audio data. Your voice remains your private data."
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Voice Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPoint: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
```

### Backend Implementation

No significant backend changes required for MVP since:

- Speech-to-text uses iOS on-device processing (SFSpeechRecognizer)
- Text-to-speech uses iOS on-device synthesis (AVSpeechSynthesizer)
- Chat API receives transcribed text (same as typed messages)

#### Optional: Voice Analytics Edge Function

**File:** `supabase/functions/log-voice-session/index.ts`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const authHeader = req.headers.get("Authorization")!;
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const {
      conversation_id,
      input_duration_seconds,
      output_duration_seconds,
      messages_count,
    } = await req.json();

    // Log voice session for analytics
    const { data, error } = await supabase
      .from("voice_sessions")
      .insert({
        user_id: user.id,
        conversation_id,
        input_duration_seconds,
        output_duration_seconds,
        messages_count,
        ended_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error) throw error;

    return new Response(JSON.stringify({ success: true, session: data }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

### Required Permissions

**Info.plist additions:**

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>MindFriend uses speech recognition to let you talk to your AI companion instead of typing.</string>

<key>NSMicrophoneUsageDescription</key>
<string>MindFriend needs microphone access so you can speak to your AI companion.</string>
```

---

## UI/UX

### Voice Chat Flow

```
┌─────────────────────────────────────────┐
│  < AI Companion              ⚙️         │
├─────────────────────────────────────────┤
│                                         │
│   ┌─────────────────────────────┐       │
│   │ Voice │ Text                │       │ ← Mode toggle
│   └─────────────────────────────┘       │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │ 😊 How are you feeling today?   │   │
│   │                            🔊   │   │ ← Play button
│   └─────────────────────────────────┘   │
│                                         │
│              ┌─────────────────────┐    │
│              │ I'm feeling a bit  │    │
│              │ anxious about work │    │
│              └─────────────────────┘    │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │ I hear you. Work stress can    │   │
│   │ really weigh on us...          │   │
│   │                            🔊   │   │
│   └─────────────────────────────────┘   │
│                                         │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐    │
│  │ "I've been having trouble..."  │    │ ← Live transcription
│  └─────────────────────────────────┘    │
│                                         │
│       ⛔              🎤              ➡️  │ ← Voice controls
│     Cancel         (pulsing)        Send │
│                                         │
│           Listening...                  │
└─────────────────────────────────────────┘
```

### Key Interactions

1. **Push-to-Talk**
   - Tap microphone to start listening
   - Tap again to stop
   - Pulsing animation while active

2. **Live Transcription**
   - Text appears as you speak
   - Can edit before sending
   - Clear X button to restart

3. **AI Response Playback**
   - Auto-plays if setting enabled
   - Tap speaker icon to replay
   - Tap stop to interrupt

4. **Mode Switching**
   - Seamless toggle between voice/text
   - Preserves conversation context
   - Remembers preference

### Accessibility

- VoiceOver fully compatible
- Haptic feedback for record start/stop
- Visual indicators for all audio states
- Adjustable speech rate for TTS

---

## Verification

### Test Scenarios

1. **Speech Recognition**
   - Grant microphone permission
   - Speak a sentence
   - Verify accurate transcription
   - Test background noise handling

2. **Text-to-Speech**
   - Receive AI response
   - Verify auto-play (if enabled)
   - Test play/stop controls
   - Verify speed adjustment works

3. **Mode Switching**
   - Switch from voice to text mid-conversation
   - Verify messages preserved
   - Switch back to voice
   - Verify continuity

4. **Permissions Denied**
   - Deny microphone permission
   - Verify graceful fallback to text
   - Verify helpful error message

5. **Offline Behavior**
   - Test with airplane mode
   - Verify recognition uses on-device model
   - Verify TTS works offline

---

## Dependencies

- **Requires:** iOS 17+ (for enhanced speech APIs)
- **Requires:** Chat system (existing)
- **Optional:** Premium tier (for priority response—spec-08)

---

## Risks & Mitigations

| Risk                             | Impact | Mitigation                                        |
| -------------------------------- | ------ | ------------------------------------------------- |
| Speech recognition accuracy      | High   | Use Apple's latest models, show edit option       |
| Battery drain from audio         | Medium | Auto-stop after silence, efficient processing     |
| User privacy concerns            | High   | On-device processing, clear privacy messaging     |
| TTS sounds robotic               | Medium | Use premium voices (V2), user voice selection     |
| Ambient noise interference       | Medium | Show noise indicator, suggest quieter environment |
| App Store rejection (microphone) | Low    | Clear usage description, legitimate use case      |

---

## Implementation Estimate

| Component                    | Estimate     |
| ---------------------------- | ------------ |
| SpeechService implementation | 8 hours      |
| VoiceChatView                | 6 hours      |
| Voice settings & UI          | 4 hours      |
| Database migration           | 1 hour       |
| Permission handling          | 2 hours      |
| Testing & polish             | 6 hours      |
| **Total**                    | **27 hours** |

---

## Success Metrics

| Metric                    | Target                           |
| ------------------------- | -------------------------------- |
| Voice mode adoption       | 30% of active users try it       |
| Voice session completion  | 70% of started sessions complete |
| Voice vs text preference  | 20% primarily use voice          |
| User satisfaction (voice) | 4.5+ stars in feature feedback   |

---

## Future Enhancements (V2+)

1. **Wake Word Activation**
   - "Hey MindFriend" hands-free start
   - Always-listening mode (battery optimized)

2. **Emotion Detection**
   - Analyze voice stress markers
   - Adjust AI tone accordingly
   - Feed into weekly insights

3. **Voice Journaling**
   - Quick voice memo capture
   - Automatic transcription + analysis
   - Add to journal entries

4. **Guided Voice Exercises**
   - Voice-guided breathing
   - Audio meditation sessions
   - Call-and-response prompts

5. **Multi-Language Support**
   - Detect spoken language
   - Respond in same language
   - Cross-language translation
