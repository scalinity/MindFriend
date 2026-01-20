# Music & Soundscapes

> Ambient audio for focus, relaxation, and mood enhancement throughout the day.

**Priority:** P1 - High Value
**Effort:** Medium (3-4 weeks)
**Impact:** Ambient experience; increased session time

---

## 1. Overview

### 1.1 What It Does

A dedicated music and soundscape library featuring:

- Focus music for concentration
- Relaxation soundscapes
- Binaural beats for various mental states
- Apple Music integration
- Custom mixing capabilities

### 1.2 Why It Exists

- **Daily Use Case:** Background audio during work/study
- **Mood Enhancement:** Music directly affects emotional state
- **Session Extension:** Audio increases time in app
- **Competitor Feature:** Calm/Endel have soundscapes; Spotify entering wellness

### 1.3 Success Metrics

| Metric                 | Target       | Measurement |
| ---------------------- | ------------ | ----------- |
| Daily audio sessions   | 2+ per user  | Analytics   |
| Average session length | 25+ minutes  | Analytics   |
| Playlist saves         | 30% of users | User action |

---

## 2. Functional Requirements

### 2.1 Content Library

| ID    | Requirement                                         | Priority |
| ----- | --------------------------------------------------- | -------- |
| CL-01 | Focus music category (instrumental, lo-fi, ambient) | Must     |
| CL-02 | Relaxation category (nature, ambient, piano)        | Must     |
| CL-03 | Sleep category (linked from sleep feature)          | Must     |
| CL-04 | Binaural beats (alpha, theta, delta waves)          | Should   |
| CL-05 | Soundscapes (rain, ocean, forest, fire, cafe)       | Must     |
| CL-06 | Guided sessions with music background               | Should   |

### 2.2 Playback Features

| ID    | Requirement                        | Priority |
| ----- | ---------------------------------- | -------- |
| PF-01 | Background playback (screen off)   | Must     |
| PF-02 | Timer (15/30/60 min or continuous) | Must     |
| PF-03 | Volume control                     | Must     |
| PF-04 | Crossfade between tracks           | Should   |
| PF-05 | Shuffle and repeat modes           | Should   |
| PF-06 | Lock screen controls               | Must     |

### 2.3 Mixing & Customization

| ID    | Requirement                 | Priority |
| ----- | --------------------------- | -------- |
| MC-01 | Layer up to 3 soundscapes   | Should   |
| MC-02 | Individual volume per layer | Should   |
| MC-03 | Save custom mixes           | Should   |
| MC-04 | Share mixes with friends    | Could    |

### 2.4 Apple Music Integration

| ID    | Requirement                            | Priority |
| ----- | -------------------------------------- | -------- |
| AM-01 | Browse user's Apple Music library      | Could    |
| AM-02 | Play Apple Music alongside soundscapes | Could    |
| AM-03 | Curated playlists for wellness         | Could    |

---

## 3. Technical Requirements

### 3.1 Data Models

```sql
-- Audio tracks
CREATE TABLE audio_tracks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    artist TEXT,
    category TEXT NOT NULL, -- 'focus', 'relax', 'sleep', 'soundscape', 'binaural'
    subcategory TEXT, -- 'lofi', 'nature', 'piano', 'alpha', etc.
    duration_seconds INTEGER NOT NULL,
    audio_url TEXT NOT NULL,
    thumbnail_url TEXT,
    is_premium BOOLEAN DEFAULT false,
    is_loopable BOOLEAN DEFAULT false,
    bpm INTEGER, -- For music tracks
    binaural_frequency DECIMAL(5,2), -- For binaural beats (Hz)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User playlists
CREATE TABLE audio_playlists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    track_ids UUID[] NOT NULL,
    is_mix BOOLEAN DEFAULT false, -- Custom soundscape mix
    mix_config JSONB, -- For mixes: [{track_id, volume}]
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Playback sessions (analytics)
CREATE TABLE audio_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    track_id UUID REFERENCES audio_tracks(id),
    playlist_id UUID REFERENCES audio_playlists(id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_played_seconds INTEGER
);

-- RLS
ALTER TABLE audio_tracks ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tracks readable by authenticated"
    ON audio_tracks FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Users manage own playlists"
    ON audio_playlists FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own sessions"
    ON audio_sessions FOR ALL
    USING (auth.uid() = user_id);
```

### 3.2 Audio Player Service

```swift
import AVFoundation
import MediaPlayer

@MainActor
class MusicPlayerService: NSObject, ObservableObject {
    static let shared = MusicPlayerService()

    @Published var isPlaying = false
    @Published var currentTrack: AudioTrack?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0

    private var players: [UUID: AVAudioPlayer] = [:] // For mixing
    private var timer: Timer?

    // MARK: - Single Track Playback

    func play(_ track: AudioTrack) async {
        stop()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let data = try await downloadTrack(track.audioUrl)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.numberOfLoops = track.isLoopable ? -1 : 0
            player.volume = volume
            player.prepareToPlay()
            player.play()

            players[track.id] = player
            currentTrack = track
            duration = player.duration
            isPlaying = true

            setupNowPlaying(track)
            startTimeUpdates()
        } catch {
            print("Playback error: \(error)")
        }
    }

    // MARK: - Mix Playback (Multiple Layers)

    func playMix(_ tracks: [(track: AudioTrack, volume: Float)]) async {
        stop()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            for (track, trackVolume) in tracks {
                let data = try await downloadTrack(track.audioUrl)
                let player = try AVAudioPlayer(data: data)
                player.numberOfLoops = -1 // Always loop soundscapes
                player.volume = trackVolume * volume
                player.prepareToPlay()
                player.play()

                players[track.id] = player
            }

            currentTrack = tracks.first?.track
            isPlaying = true
        } catch {
            print("Mix playback error: \(error)")
        }
    }

    func setLayerVolume(_ trackId: UUID, volume: Float) {
        players[trackId]?.volume = volume * self.volume
    }

    // MARK: - Controls

    func pause() {
        players.values.forEach { $0.pause() }
        isPlaying = false
    }

    func resume() {
        players.values.forEach { $0.play() }
        isPlaying = true
    }

    func stop() {
        players.values.forEach { $0.stop() }
        players.removeAll()
        currentTrack = nil
        isPlaying = false
        stopTimeUpdates()
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        players.values.forEach { $0.volume = newVolume }
    }

    // MARK: - Timer

    func setTimer(minutes: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .minutes(minutes)) { [weak self] in
            self?.fadeOutAndStop()
        }
    }

    private func fadeOutAndStop() {
        // Fade out over 10 seconds
        let fadeSteps = 20
        let stepDuration = 10.0 / Double(fadeSteps)

        for i in 0..<fadeSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(i)) { [weak self] in
                let newVolume = self?.volume ?? 1.0 * Float(fadeSteps - i) / Float(fadeSteps)
                self?.players.values.forEach { $0.volume = newVolume }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stop()
        }
    }

    // MARK: - Now Playing

    private func setupNowPlaying(_ track: AudioTrack) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist ?? "MindFriend"
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Remote controls
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
    }
}
```

---

## 4. UI/UX Specifications

### 4.1 Music Home

```
┌─────────────────────────────────┐
│ Sounds                     🔍   │
├─────────────────────────────────┤
│                                 │
│ Now Playing                     │
│ ┌─────────────────────────────┐ │
│ │ 🎵 Calm Focus               │ │
│ │ Lo-Fi • 32:45 remaining     │ │
│ │ ▶️ ━━━━━━━●━━━━━━ 🔊        │ │
│ └─────────────────────────────┘ │
│                                 │
│ Quick Start                     │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐    │
│ │🎯  │ │😌  │ │😴  │ │🌧️  │    │
│ │Focus│ │Relax│ │Sleep│ │Rain │    │
│ └────┘ └────┘ └────┘ └────┘    │
│                                 │
│ Focus Music                  ▶  │
│ ┌────────────────────────────┐  │
│ │ Lo-Fi  │ Ambient │ Classical│  │
│ └────────────────────────────┘  │
│                                 │
│ Soundscapes                  ▶  │
│ ┌────────────────────────────┐  │
│ │ 🌧️ Rain │ 🌊 Ocean │ 🔥 Fire │  │
│ └────────────────────────────┘  │
│                                 │
│ Binaural Beats               ▶  │
│ ┌────────────────────────────┐  │
│ │ Alpha (Focus) │ Theta (Calm)│  │
│ └────────────────────────────┘  │
│                                 │
│ My Mixes                     ▶  │
│ ┌────────────────────────────┐  │
│ │ + Create Mix               │  │
│ └────────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

### 4.2 Mix Creator

```
┌─────────────────────────────────┐
│ ← Create Mix            [Save]  │
├─────────────────────────────────┤
│                                 │
│ Mix Name                        │
│ ┌─────────────────────────────┐ │
│ │ Cozy Study Session          │ │
│ └─────────────────────────────┘ │
│                                 │
│ Layers (3 max)                  │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🌧️ Rain on Window           │ │
│ │ ━━━━━━━━━●━━━━━━ 70%       │ │
│ │                    [Remove] │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🔥 Fireplace Crackle        │ │
│ │ ━━━━━●━━━━━━━━━━ 40%       │ │
│ │                    [Remove] │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ + Add Layer                 │ │
│ │   (1 remaining)             │ │
│ └─────────────────────────────┘ │
│                                 │
│                                 │
│          [▶️ Preview]           │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] User can browse and play focus music
- [ ] User can browse and play soundscapes
- [ ] Playback continues in background
- [ ] Timer fades out and stops playback
- [ ] User can mix up to 3 soundscapes
- [ ] Lock screen controls work
- [ ] Volume control is functional
- [ ] User can save custom mixes

---

## 6. Content Plan

| Category       | Count     | Source                   |
| -------------- | --------- | ------------------------ |
| Focus Music    | 30 tracks | Licensing + AI-generated |
| Relaxation     | 20 tracks | Original + licensing     |
| Soundscapes    | 20        | Original recordings      |
| Binaural Beats | 10        | AI-generated             |

---

## 7. Rollout Plan

### Phase 1: Core Playback (Week 1-2)

- Audio player service
- Basic library UI
- Background playback

### Phase 2: Mixing (Week 3)

- Multi-track mixing
- Volume per layer
- Save mixes

### Phase 3: Polish (Week 4)

- Timer functionality
- Now playing UI
- Apple Music integration (optional)
