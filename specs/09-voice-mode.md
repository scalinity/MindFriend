# 09 - Voice Mode (Big Bet)

## Overview

Talk to your AI companion instead of typing. Voice mode transforms MindFriend from a text-based app into a real-time conversational experience—like having a supportive friend on call. Powered by **Grok Voice Agent API** for natural, low-latency voice conversations with premium AI voices.

This is particularly valuable during moments when typing feels difficult: while walking, lying in bed anxious at night, or during emotional overwhelm.

**Priority:** Future (Big Bet)
**Impact:** Differentiation ↑↑↑, Engagement ↑↑, Accessibility ↑↑
**Complexity:** High

**Technical Reference:** See `docs/grok-voice-agent-api.md` for full API documentation.

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

### Premium Features

- As a **free user**, I want 3 voice minutes/month so that I can try voice mode
- As a **premium user**, I want unlimited voice conversations so that I can always talk instead of type
- As a **premium user**, I want to choose from multiple AI voices so that I can pick one that feels right

---

## Product Requirements

### Must Have (MVP)

1. **Real-Time Voice Conversations (Grok Voice Agent API)**
   - Bidirectional WebSocket connection via backend relay
   - Server-side VAD (Voice Activity Detection) for natural turn-taking
   - Real-time transcription display during speech
   - Natural AI voice responses with minimal latency

2. **Voice Selection**
   - 5 Grok voices: Ara (warm), Rex (professional), Sal (calm), Eve (energetic), Leo (authoritative)
   - Default: Ara (warm, conversational)
   - Voice preview in settings

3. **Voice Mode Toggle**
   - Easy switch between voice and text modes
   - Remember user's preference
   - Per-conversation setting option

4. **Usage Limits & Paywall**
   - **Free tier:** 3 minutes/month voice conversation
   - **Premium tier:** Unlimited voice minutes
   - Clear usage indicator and upgrade prompt
   - Graceful fallback to text when limit reached

5. **Basic Voice Settings**
   - Enable/disable voice mode
   - Voice selection (Premium only: all 5 voices)
   - Auto-play responses toggle

### Nice to Have (V2)

1. **Hands-Free Mode**
   - Continuous conversation without tapping
   - Background audio support

2. **Voice Emotion Detection**
   - Detect stress/anxiety in user's voice
   - Adjust AI response tone accordingly
   - Log emotional markers for insights

3. **Audio Sessions**
   - Voice-only guided exercises
   - Breathing exercise with audio cues
   - Meditation with voice guidance

4. **Transcript Export**
   - Save voice conversations as text
   - Share conversation summaries
   - Journal entry creation from voice

5. **Multi-Language Voice**
   - 100+ languages with automatic detection
   - TTS in user's preferred language

### Out of Scope

- Video calling
- Human therapist voice calls
- Voice cloning/custom voice synthesis
- Real-time voice modification
- Group voice conversations
- Voice messages to circles (use existing text)

---

## Paywall & Limits

### Voice Minutes Quota

| Tier        | Voice Minutes | Voice Selection | Features                  |
| ----------- | ------------- | --------------- | ------------------------- |
| **Free**    | 3 min/month   | Ara only        | Basic voice mode          |
| **Premium** | Unlimited     | All 5 voices    | Full voice mode + history |

### Quota Enforcement

1. Track `voice_minutes_used` in `voice_usage` table
2. Check quota before establishing WebSocket connection
3. Monitor session duration in real-time
4. Graceful degradation when limit approached:
   - At 80%: Show warning banner
   - At 95%: Show upgrade prompt
   - At 100%: End voice session, offer text fallback

### Usage Reset

- Monthly reset on billing cycle date
- No rollover of unused minutes
- Real-time usage display in settings

---

## Technical Design

### Architecture Overview

```
┌─────────────────┐     ┌────────────────────┐     ┌─────────────────┐
│                 │     │                    │     │                 │
│  iOS App        │────▶│  Supabase Edge     │────▶│  xAI Grok       │
│  (WebSocket)    │◀────│  Function Relay    │◀────│  Voice API      │
│                 │     │                    │     │                 │
└─────────────────┘     └────────────────────┘     └─────────────────┘
       │                         │
       │ Audio PCM               │ Ephemeral tokens
       │ (24kHz)                 │ Usage tracking
       ▼                         ▼
  [Microphone]              [Supabase DB]
  [Speaker]                 [voice_usage]
```

**Why Backend Relay:**

- Never expose xAI API key to client
- Enforce usage quotas server-side
- Log conversations for safety (crisis detection)
- Apply MindFriend system prompt to voice sessions

### Data Model Changes

#### Migration: `20260200000000_voice_mode.sql`

```sql
-- Voice settings per user
CREATE TABLE voice_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE UNIQUE,
  voice_enabled BOOLEAN DEFAULT TRUE,
  preferred_voice TEXT DEFAULT 'ara', -- 'ara', 'rex', 'sal', 'eve', 'leo'
  auto_play_responses BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Voice usage tracking for quota enforcement
CREATE TABLE voice_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  period_start DATE NOT NULL, -- First day of billing period
  minutes_used FLOAT DEFAULT 0, -- Total minutes used this period
  last_session_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, period_start)
);

-- Voice sessions for analytics
CREATE TABLE voice_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  duration_seconds INT DEFAULT 0,
  voice_used TEXT DEFAULT 'ara',
  messages_count INT DEFAULT 0,
  was_quota_limited BOOLEAN DEFAULT FALSE
);

-- Indexes
CREATE INDEX idx_voice_settings_user_id ON voice_settings(user_id);
CREATE INDEX idx_voice_usage_user_period ON voice_usage(user_id, period_start);
CREATE INDEX idx_voice_sessions_user_id ON voice_sessions(user_id);
CREATE INDEX idx_voice_sessions_conversation_id ON voice_sessions(conversation_id);

-- RLS
ALTER TABLE voice_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own voice settings" ON voice_settings
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users view own voice usage" ON voice_usage
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users view own voice sessions" ON voice_sessions
  FOR SELECT USING (auth.uid() = user_id);

-- Function to get current period usage
CREATE OR REPLACE FUNCTION get_voice_minutes_remaining(p_user_id UUID)
RETURNS FLOAT AS $$
DECLARE
  v_is_premium BOOLEAN;
  v_minutes_used FLOAT;
  v_limit FLOAT;
BEGIN
  -- Check premium status
  SELECT EXISTS(
    SELECT 1 FROM subscriptions
    WHERE user_id = p_user_id
    AND status = 'active'
    AND current_period_end > NOW()
  ) INTO v_is_premium;

  -- Premium users have unlimited
  IF v_is_premium THEN
    RETURN 999999;
  END IF;

  -- Get current period usage
  SELECT COALESCE(minutes_used, 0) INTO v_minutes_used
  FROM voice_usage
  WHERE user_id = p_user_id
  AND period_start = DATE_TRUNC('month', NOW())::DATE;

  -- Free tier limit: 3 minutes
  v_limit := 3.0;

  RETURN GREATEST(0, v_limit - COALESCE(v_minutes_used, 0));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Backend Implementation

#### Edge Function: Voice Session Relay

**File:** `supabase/functions/voice-session/index.ts`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const XAI_API_KEY = Deno.env.get("XAI_API_KEY")!;
const XAI_REALTIME_URL = "wss://api.x.ai/v1/realtime";

const VOICE_INSTRUCTIONS = `You are a warm, supportive AI companion for MindFriend, a mental wellness app.

Guidelines:
- Be empathetic, understanding, and non-judgmental
- Use a conversational, friendly tone
- Ask follow-up questions to understand feelings better
- Offer gentle suggestions without being prescriptive
- If user expresses self-harm or crisis, immediately provide crisis resources
- Keep responses concise for voice (2-3 sentences typically)
- Acknowledge emotions before offering perspectives`;

serve(async (req) => {
  // Handle WebSocket upgrade
  const { socket, response } = Deno.upgradeWebSocket(req);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get user from auth header
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response("Unauthorized", { status: 401 });
  }

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response("Unauthorized", { status: 401 });
  }

  // Check voice quota
  const { data: remaining } = await supabase.rpc(
    "get_voice_minutes_remaining",
    {
      p_user_id: user.id,
    },
  );

  if (remaining <= 0) {
    socket.close(4003, "Voice quota exceeded");
    return response;
  }

  // Get user's voice preference
  const { data: settings } = await supabase
    .from("voice_settings")
    .select("preferred_voice")
    .eq("user_id", user.id)
    .single();

  const preferredVoice = settings?.preferred_voice || "ara";

  // Check if user is premium (for voice selection)
  const { data: subscription } = await supabase
    .from("subscriptions")
    .select("status")
    .eq("user_id", user.id)
    .eq("status", "active")
    .single();

  const isPremium = !!subscription;

  // Non-premium users can only use 'ara'
  const voice = isPremium ? preferredVoice : "ara";

  // Track session
  let sessionId: string;
  let sessionStart = Date.now();
  let messageCount = 0;

  // Create session record
  const { data: session } = await supabase
    .from("voice_sessions")
    .insert({
      user_id: user.id,
      voice_used: voice,
      started_at: new Date().toISOString(),
    })
    .select()
    .single();

  sessionId = session?.id;

  // Connect to xAI Voice API
  let xaiSocket: WebSocket | null = null;

  socket.onopen = () => {
    xaiSocket = new WebSocket(XAI_REALTIME_URL, {
      headers: {
        Authorization: `Bearer ${XAI_API_KEY}`,
      },
    });

    xaiSocket.onopen = () => {
      // Configure session with MindFriend personality
      xaiSocket!.send(
        JSON.stringify({
          type: "session.update",
          session: {
            instructions: VOICE_INSTRUCTIONS,
            voice: voice,
            turn_detection: {
              type: "server_vad",
            },
            audio: {
              input: { format: { type: "audio/pcm", rate: 24000 } },
              output: { format: { type: "audio/pcm", rate: 24000 } },
            },
          },
        }),
      );

      // Notify client of connection
      socket.send(
        JSON.stringify({
          type: "session.ready",
          voice: voice,
          minutes_remaining: remaining,
        }),
      );
    };

    xaiSocket.onmessage = (event) => {
      const data = JSON.parse(event.data);

      // Track messages
      if (data.type === "response.done") {
        messageCount++;
      }

      // Check for crisis keywords in transcripts
      if (data.type === "response.output_audio_transcript.delta") {
        // Crisis detection handled by chat safety system
      }

      // Forward to client
      socket.send(event.data);
    };

    xaiSocket.onerror = (error) => {
      console.error("xAI WebSocket error:", error);
      socket.send(
        JSON.stringify({
          type: "error",
          error: { message: "Voice service unavailable" },
        }),
      );
    };

    xaiSocket.onclose = () => {
      socket.close();
    };
  };

  socket.onmessage = (event) => {
    // Forward client messages to xAI
    if (xaiSocket?.readyState === WebSocket.OPEN) {
      xaiSocket.send(event.data);
    }
  };

  socket.onclose = async () => {
    // Close xAI connection
    if (xaiSocket) {
      xaiSocket.close();
    }

    // Calculate session duration
    const durationSeconds = Math.ceil((Date.now() - sessionStart) / 1000);
    const durationMinutes = durationSeconds / 60;

    // Update session record
    await supabase
      .from("voice_sessions")
      .update({
        ended_at: new Date().toISOString(),
        duration_seconds: durationSeconds,
        messages_count: messageCount,
      })
      .eq("id", sessionId);

    // Update usage
    const periodStart = new Date();
    periodStart.setDate(1);
    periodStart.setHours(0, 0, 0, 0);

    await supabase.rpc("increment_voice_usage", {
      p_user_id: user.id,
      p_minutes: durationMinutes,
      p_period_start: periodStart.toISOString().split("T")[0],
    });
  };

  socket.onerror = (error) => {
    console.error("Client WebSocket error:", error);
  };

  return response;
});
```

#### Edge Function: Get Ephemeral Token (Alternative Approach)

**File:** `supabase/functions/voice-token/index.ts`

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

    // Check quota
    const { data: remaining } = await supabase.rpc(
      "get_voice_minutes_remaining",
      {
        p_user_id: user.id,
      },
    );

    if (remaining <= 0) {
      return new Response(
        JSON.stringify({
          error: "Voice quota exceeded",
          minutes_remaining: 0,
          upgrade_required: true,
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Generate ephemeral token from xAI
    const tokenResponse = await fetch(
      "https://api.x.ai/v1/realtime/client_secrets",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${Deno.env.get("XAI_API_KEY")}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          expires_in: 300, // 5 minutes
        }),
      },
    );

    if (!tokenResponse.ok) {
      throw new Error("Failed to generate voice token");
    }

    const { client_secret, expires_at } = await tokenResponse.json();

    // Get user settings
    const { data: settings } = await supabase
      .from("voice_settings")
      .select("preferred_voice")
      .eq("user_id", user.id)
      .single();

    // Check premium status
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("status")
      .eq("user_id", user.id)
      .eq("status", "active")
      .single();

    const isPremium = !!subscription;

    return new Response(
      JSON.stringify({
        token: client_secret,
        expires_at,
        minutes_remaining: remaining,
        voice: isPremium ? settings?.preferred_voice || "ara" : "ara",
        is_premium: isPremium,
        available_voices: isPremium
          ? ["ara", "rex", "sal", "eve", "leo"]
          : ["ara"],
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

### iOS Implementation

#### Grok Voice Service

**File:** `apps/ios/MindFriendApp/Core/Services/GrokVoiceService.swift`

```swift
import Foundation
import AVFoundation
import Combine

/// Voice service using Grok Voice Agent API
@MainActor
class GrokVoiceService: ObservableObject {
    // MARK: - Published Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var transcribedText = ""
    @Published var minutesRemaining: Double = 0
    @Published var currentVoice: GrokVoice = .ara
    @Published var availableVoices: [GrokVoice] = [.ara]
    @Published var isPremium = false

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Private Properties
    private var webSocket: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var playbackBuffer: [Data] = []
    private var isPlaying = false

    private let supabaseClient: SupabaseClient
    private var sessionStartTime: Date?

    // MARK: - Audio Configuration
    private let sampleRate: Double = 24000
    private let channelCount: AVAudioChannelCount = 1

    init(supabaseClient: SupabaseClient) {
        self.supabaseClient = supabaseClient
        setupAudio()
    }

    // MARK: - Setup

    private func setupAudio() {
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        )

        audioPlayer = AVAudioPlayerNode()
        if let player = audioPlayer {
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: audioFormat)
        }
    }

    // MARK: - Connection

    func connect() async throws {
        connectionState = .connecting

        // Get voice token from backend
        let response = try await supabaseClient.functions.invoke(
            "voice-token",
            options: .init()
        )

        guard let data = response.data else {
            throw VoiceError.tokenGenerationFailed
        }

        let tokenResponse = try JSONDecoder().decode(VoiceTokenResponse.self, from: data)

        // Check quota
        guard tokenResponse.minutesRemaining > 0 else {
            throw VoiceError.quotaExceeded
        }

        minutesRemaining = tokenResponse.minutesRemaining
        isPremium = tokenResponse.isPremium
        availableVoices = tokenResponse.availableVoices.compactMap { GrokVoice(rawValue: $0) }
        currentVoice = GrokVoice(rawValue: tokenResponse.voice) ?? .ara

        // Connect to xAI via WebSocket
        let url = URL(string: "wss://api.x.ai/v1/realtime?token=\(tokenResponse.token)")!
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        // Configure session
        try await configureSession()

        // Start receiving messages
        receiveMessages()

        connectionState = .connected
        sessionStartTime = Date()
    }

    private func configureSession() async throws {
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "voice": currentVoice.rawValue,
                "turn_detection": ["type": "server_vad"],
                "audio": [
                    "input": ["format": ["type": "audio/pcm", "rate": 24000]],
                    "output": ["format": ["type": "audio/pcm", "rate": 24000]]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: config)
        try await webSocket?.send(.data(data))
    }

    // MARK: - Message Handling

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                Task { @MainActor in
                    await self.handleMessage(message)
                }
                self.receiveMessages() // Continue receiving

            case .failure(let error):
                Task { @MainActor in
                    self.connectionState = .error(error.localizedDescription)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "session.updated":
            connectionState = .connected

        case "input_audio_buffer.speech_started":
            isListening = true
            stopPlayback() // Interrupt AI when user starts speaking

        case "input_audio_buffer.speech_stopped":
            isListening = false

        case "response.output_audio.delta":
            if let delta = json["delta"] as? String,
               let audioData = Data(base64Encoded: delta) {
                queueAudioPlayback(audioData)
            }

        case "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                transcribedText += delta
            }

        case "response.done":
            // Response complete
            transcribedText = ""

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                connectionState = .error(message)
            }

        default:
            break
        }
    }

    // MARK: - Audio Input

    func startListening() throws {
        guard connectionState == .connected else {
            throw VoiceError.notConnected
        }

        // Configure audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)

        // Setup audio input tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.sendAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
    }

    func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isListening = false

        // Commit the audio buffer
        let commit: [String: Any] = ["type": "input_audio_buffer.commit"]
        if let data = try? JSONSerialization.data(withJSONObject: commit) {
            webSocket?.send(.data(data)) { _ in }
        }
    }

    private func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameCount * 2)
        let base64 = data.base64EncodedString()

        let message: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: message) {
            webSocket?.send(.data(jsonData)) { _ in }
        }
    }

    // MARK: - Audio Output

    private func queueAudioPlayback(_ data: Data) {
        playbackBuffer.append(data)

        if !isPlaying {
            playNextAudioChunk()
        }
    }

    private func playNextAudioChunk() {
        guard !playbackBuffer.isEmpty,
              let player = audioPlayer,
              let format = audioFormat else {
            isPlaying = false
            isSpeaking = false
            return
        }

        isPlaying = true
        isSpeaking = true

        let audioData = playbackBuffer.removeFirst()

        // Convert PCM data to AVAudioPCMBuffer
        let frameCount = AVAudioFrameCount(audioData.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            playNextAudioChunk()
            return
        }

        buffer.frameLength = frameCount
        audioData.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, audioData.count)
            }
        }

        // Schedule playback
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.playNextAudioChunk()
            }
        }

        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
        player.play()
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        playbackBuffer.removeAll()
        isPlaying = false
        isSpeaking = false
    }

    // MARK: - Voice Selection

    func setVoice(_ voice: GrokVoice) async throws {
        guard isPremium || voice == .ara else {
            throw VoiceError.premiumRequired
        }

        currentVoice = voice

        // Update session if connected
        if connectionState == .connected {
            try await configureSession()
        }

        // Save preference
        try await supabaseClient
            .from("voice_settings")
            .upsert([
                "user_id": supabaseClient.auth.currentUser?.id.uuidString ?? "",
                "preferred_voice": voice.rawValue
            ])
            .execute()
    }

    // MARK: - Disconnect

    func disconnect() async {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        connectionState = .disconnected

        audioEngine.stop()
        audioPlayer?.stop()

        // Log session duration
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            // Duration tracking handled by backend
        }

        sessionStartTime = nil
    }
}

// MARK: - Supporting Types

enum GrokVoice: String, CaseIterable, Identifiable {
    case ara = "ara"
    case rex = "rex"
    case sal = "sal"
    case eve = "eve"
    case leo = "leo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ara: return "Ara"
        case .rex: return "Rex"
        case .sal: return "Sal"
        case .eve: return "Eve"
        case .leo: return "Leo"
        }
    }

    var description: String {
        switch self {
        case .ara: return "Warm & conversational"
        case .rex: return "Professional & clear"
        case .sal: return "Calm & balanced"
        case .eve: return "Energetic & upbeat"
        case .leo: return "Authoritative & strong"
        }
    }

    var gender: String {
        switch self {
        case .ara, .eve: return "Female"
        case .rex, .leo: return "Male"
        case .sal: return "Neutral"
        }
    }
}

struct VoiceTokenResponse: Codable {
    let token: String
    let expiresAt: String
    let minutesRemaining: Double
    let voice: String
    let isPremium: Bool
    let availableVoices: [String]

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case minutesRemaining = "minutes_remaining"
        case voice
        case isPremium = "is_premium"
        case availableVoices = "available_voices"
    }
}

enum VoiceError: LocalizedError {
    case notConnected
    case quotaExceeded
    case premiumRequired
    case tokenGenerationFailed
    case audioSessionFailed

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Voice service not connected"
        case .quotaExceeded:
            return "You've used all your voice minutes this month. Upgrade to Premium for unlimited voice conversations."
        case .premiumRequired:
            return "Premium subscription required to use additional voices."
        case .tokenGenerationFailed:
            return "Failed to start voice session. Please try again."
        case .audioSessionFailed:
            return "Failed to access microphone."
        }
    }
}
```

#### Voice Chat View

**File:** `apps/ios/MindFriendApp/Features/Chat/VoiceChatView.swift`

```swift
import SwiftUI

struct VoiceChatView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var voiceService: GrokVoiceService
    @ObservedObject var viewModel: ChatViewModel

    @State private var showSettings = false
    @State private var showUpgradeSheet = false
    @State private var errorMessage: String?

    init(viewModel: ChatViewModel, supabaseClient: SupabaseClient) {
        self.viewModel = viewModel
        _voiceService = StateObject(wrappedValue: GrokVoiceService(supabaseClient: supabaseClient))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Usage indicator
            if !voiceService.isPremium {
                usageBar
            }

            // Connection status
            connectionStatus

            // Voice visualization
            voiceVisualization

            Spacer()

            // Voice controls
            voiceControls
        }
        .navigationTitle("Voice Mode")
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
            VoiceSettingsView(voiceService: voiceService)
        }
        .sheet(isPresented: $showUpgradeSheet) {
            SubscriptionView()
        }
        .alert("Voice Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
            if case .quotaExceeded = VoiceError.quotaExceeded {
                Button("Upgrade") { showUpgradeSheet = true }
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await connectVoice()
        }
        .onDisappear {
            Task {
                await voiceService.disconnect()
            }
        }
    }

    // MARK: - Usage Bar

    private var usageBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Voice Minutes")
                    .font(.caption)
                Spacer()
                Text("\(String(format: "%.1f", voiceService.minutesRemaining)) min remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    Rectangle()
                        .fill(usageColor)
                        .frame(width: geometry.size.width * usagePercentage, height: 4)
                }
                .cornerRadius(2)
            }
            .frame(height: 4)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var usagePercentage: Double {
        let total = 3.0 // Free tier limit
        let used = total - voiceService.minutesRemaining
        return min(1.0, max(0, used / total))
    }

    private var usageColor: Color {
        if usagePercentage >= 0.95 { return .red }
        if usagePercentage >= 0.8 { return .orange }
        return .accentColor
    }

    // MARK: - Connection Status

    private var connectionStatus: some View {
        Group {
            switch voiceService.connectionState {
            case .disconnected:
                Label("Disconnected", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            case .connecting:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                }
                .foregroundStyle(.secondary)
            case .connected:
                Label("Connected • \(voiceService.currentVoice.displayName)", systemImage: "waveform")
                    .foregroundStyle(.green)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .padding(.vertical, 8)
    }

    // MARK: - Voice Visualization

    private var voiceVisualization: some View {
        VStack(spacing: 24) {
            // Live transcription
            if !voiceService.transcribedText.isEmpty {
                Text(voiceService.transcribedText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
            }

            // Voice orb
            ZStack {
                // Outer glow when speaking/listening
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                voiceService.isListening ? Color.red.opacity(0.3) :
                                voiceService.isSpeaking ? Color.accentColor.opacity(0.3) :
                                Color.clear,
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(voiceService.isListening || voiceService.isSpeaking ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: voiceService.isListening || voiceService.isSpeaking)

                // Main orb
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                voiceService.isListening ? Color.red :
                                voiceService.isSpeaking ? Color.accentColor :
                                Color(.systemGray4),
                                voiceService.isListening ? Color.red.opacity(0.7) :
                                voiceService.isSpeaking ? Color.accentColor.opacity(0.7) :
                                Color(.systemGray5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                // Icon
                Image(systemName: voiceService.isListening ? "waveform" :
                      voiceService.isSpeaking ? "speaker.wave.2.fill" : "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }

            // Status text
            Text(statusText)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var statusText: String {
        switch voiceService.connectionState {
        case .connected:
            if voiceService.isListening {
                return "Listening..."
            } else if voiceService.isSpeaking {
                return "Speaking..."
            } else {
                return "Tap to speak"
            }
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Tap to connect"
        case .error:
            return "Connection error"
        }
    }

    // MARK: - Voice Controls

    private var voiceControls: some View {
        HStack(spacing: 40) {
            // End call
            Button {
                Task {
                    await voiceService.disconnect()
                }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.red)
                    .clipShape(Circle())
            }

            // Main microphone button
            Button {
                toggleVoice()
            } label: {
                Image(systemName: voiceService.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(voiceService.isListening ? Color.red : Color.accentColor)
                    .clipShape(Circle())
            }
            .disabled(voiceService.connectionState != .connected)

            // Switch to text
            NavigationLink {
                ChatView(viewModel: viewModel)
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 24))
                    .foregroundStyle(.accentColor)
                    .frame(width: 56, height: 56)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Actions

    private func connectVoice() async {
        do {
            try await voiceService.connect()
        } catch let error as VoiceError {
            errorMessage = error.localizedDescription
            if case .quotaExceeded = error {
                showUpgradeSheet = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleVoice() {
        if voiceService.isListening {
            voiceService.stopListening()
        } else {
            do {
                try voiceService.startListening()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

#### Voice Settings View

**File:** `apps/ios/MindFriendApp/Features/Profile/VoiceSettingsView.swift`

```swift
import SwiftUI

struct VoiceSettingsView: View {
    @ObservedObject var voiceService: GrokVoiceService
    @Environment(\.dismiss) private var dismiss

    @State private var showUpgradeSheet = false

    var body: some View {
        NavigationStack {
            Form {
                // Voice selection
                Section {
                    ForEach(GrokVoice.allCases) { voice in
                        voiceRow(voice)
                    }
                } header: {
                    Text("AI Voice")
                } footer: {
                    if !voiceService.isPremium {
                        Text("Upgrade to Premium to unlock all voices.")
                    }
                }

                // Usage
                Section("Usage This Month") {
                    HStack {
                        Text("Minutes Used")
                        Spacer()
                        if voiceService.isPremium {
                            Text("Unlimited")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(String(format: "%.1f", 3 - voiceService.minutesRemaining)) / 3 min")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !voiceService.isPremium {
                        Button {
                            showUpgradeSheet = true
                        } label: {
                            Label("Upgrade for Unlimited Voice", systemImage: "star.fill")
                        }
                    }
                }

                // Privacy
                Section("Privacy") {
                    NavigationLink {
                        VoicePrivacyInfoView()
                    } label: {
                        Label("How Voice Data is Used", systemImage: "lock.shield")
                    }
                }
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showUpgradeSheet) {
                SubscriptionView()
            }
        }
    }

    private func voiceRow(_ voice: GrokVoice) -> some View {
        Button {
            selectVoice(voice)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(voice.displayName)
                            .font(.headline)

                        Text("(\(voice.gender))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(voice.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if voiceService.currentVoice == voice {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accentColor)
                } else if !voiceService.availableVoices.contains(voice) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(!voiceService.availableVoices.contains(voice) && voice != .ara)
    }

    private func selectVoice(_ voice: GrokVoice) {
        guard voiceService.availableVoices.contains(voice) else {
            showUpgradeSheet = true
            return
        }

        Task {
            try? await voiceService.setVoice(voice)
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
                        icon: "server.rack",
                        title: "Secure Processing",
                        description: "Voice is processed through encrypted connections to our AI partner. Audio is never stored after the conversation ends."
                    )

                    PrivacyPoint(
                        icon: "text.bubble",
                        title: "Transcription Privacy",
                        description: "Transcripts are used only for your conversation history and are protected by the same privacy policies as text messages."
                    )

                    PrivacyPoint(
                        icon: "trash",
                        title: "No Voice Storage",
                        description: "We don't store voice recordings, voice prints, or any raw audio data. Your voice remains your private data."
                    )

                    PrivacyPoint(
                        icon: "shield.checkered",
                        title: "Safety First",
                        description: "Voice conversations are monitored for crisis keywords to ensure your safety, just like text conversations."
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

### Required Permissions

**Info.plist additions:**

```xml
<key>NSMicrophoneUsageDescription</key>
<string>MindFriend needs microphone access so you can have voice conversations with your AI companion.</string>
```

### Environment Variables

**Supabase Dashboard → Edge Functions → Secrets:**

| Variable      | Purpose                  |
| ------------- | ------------------------ |
| `XAI_API_KEY` | Grok Voice Agent API key |

---

## UI/UX

### Voice Chat Flow

```
┌─────────────────────────────────────────┐
│  < Voice Mode                    ⚙️      │
├─────────────────────────────────────────┤
│  Voice Minutes  ████████░░  12.5 min    │ ← Usage bar (free tier)
├─────────────────────────────────────────┤
│                                         │
│       🟢 Connected • Ara                │ ← Status
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ "I've been feeling stressed..." │    │ ← Live transcription
│  └─────────────────────────────────┘    │
│                                         │
│              ╭─────────╮                │
│             ╱           ╲               │
│            │   🎤        │              │ ← Animated orb
│             ╲           ╱               │
│              ╰─────────╯                │
│           ~ ~ ~ ~ ~ ~ ~ ~               │ ← Pulse when active
│                                         │
│           "Listening..."                │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│      📞          🎤          ⌨️          │
│     End        Speak       Text         │
│                                         │
└─────────────────────────────────────────┘
```

### Key Interactions

1. **Tap to Speak**
   - Tap microphone orb to start/stop
   - Server VAD auto-detects speech boundaries
   - Visual pulse animation while active

2. **Real-Time Feedback**
   - Live transcription as you speak
   - AI voice response plays automatically
   - Orb color changes: blue (AI speaking), red (user speaking)

3. **Quota Awareness**
   - Progress bar shows remaining minutes
   - Warning at 80% and 95% usage
   - Upgrade prompt when limit reached

4. **Voice Selection (Premium)**
   - Settings → Voice selection
   - Preview voices before selecting
   - Locked icons for non-premium voices

### Accessibility

- VoiceOver fully compatible
- Haptic feedback for state changes
- High contrast mode support
- Reduced motion option

---

## Verification

### Test Scenarios

1. **Connection Flow**
   - Launch voice mode
   - Verify connection establishes
   - Verify correct voice is set

2. **Voice Conversation**
   - Speak to AI companion
   - Verify transcription accuracy
   - Verify AI responds with voice
   - Verify natural turn-taking

3. **Quota Enforcement**
   - Use voice until near limit
   - Verify warning appears at 80%
   - Verify upgrade prompt at 100%
   - Verify graceful fallback

4. **Premium Features**
   - Verify free users can only use Ara
   - Verify premium users can select all voices
   - Verify voice preference persists

5. **Error Handling**
   - Test network disconnection
   - Test microphone permission denied
   - Test API errors

---

## Dependencies

- **Requires:** iOS 17+
- **Requires:** Chat system (existing)
- **Requires:** Premium subscription system (spec-08)
- **Requires:** xAI API key with Voice Agent access

---

## Risks & Mitigations

| Risk                  | Impact | Mitigation                                |
| --------------------- | ------ | ----------------------------------------- |
| API costs per minute  | High   | Enforce quotas, monitor usage             |
| Latency issues        | Medium | Use server VAD, optimize audio buffering  |
| User privacy concerns | High   | Clear privacy messaging, no audio storage |
| Network reliability   | Medium | Graceful reconnection, offline fallback   |
| Quota gaming          | Low    | Server-side enforcement only              |
| xAI API availability  | Medium | Fallback to text mode, retry logic        |

---

## Implementation Estimate

| Component                    | Estimate     |
| ---------------------------- | ------------ |
| Database migration           | 1 hour       |
| Edge Function (voice-token)  | 4 hours      |
| GrokVoiceService (iOS)       | 12 hours     |
| VoiceChatView                | 6 hours      |
| Voice settings UI            | 4 hours      |
| Quota tracking & enforcement | 4 hours      |
| Testing & polish             | 8 hours      |
| **Total**                    | **39 hours** |

---

## Success Metrics

| Metric                     | Target                           |
| -------------------------- | -------------------------------- |
| Voice mode adoption        | 30% of active users try it       |
| Voice session completion   | 70% of started sessions complete |
| Premium conversion (voice) | 15% of voice users upgrade       |
| Voice vs text preference   | 20% primarily use voice          |
| User satisfaction (voice)  | 4.5+ stars in feature feedback   |

---

## Future Enhancements (V2+)

1. **Hands-Free Mode**
   - Continuous conversation without tapping
   - Background audio support

2. **Emotion Detection**
   - Analyze voice stress markers
   - Adjust AI tone accordingly
   - Feed into weekly insights

3. **Voice Journaling**
   - Quick voice memo capture
   - Automatic transcription + analysis

4. **Guided Voice Exercises**
   - Voice-guided breathing
   - Audio meditation sessions

5. **Multi-Language Support**
   - 100+ languages automatic detection
   - Response in user's language
