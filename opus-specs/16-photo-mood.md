# Photo Mood Logging

> Capture moments and moods visually with photo-based mood tracking.

**Priority:** P3 - Nice to Have
**Effort:** Low (1-2 weeks)
**Impact:** Visual journaling; engagement variety

---

## 1. Overview

### 1.1 What It Does

A photo-centric mood logging feature:

- Snap or select a photo with your mood
- Optional caption and mood tags
- Photo mood gallery with timeline view
- AI-powered mood detection from photos (optional)
- Visual mood patterns over time

### 1.2 Why It Exists

- **Lower Friction:** Sometimes a photo says it all
- **Visual Memory:** Photos trigger stronger emotional recall
- **Engagement Variety:** Alternative to text-based logging
- **Gen Z Appeal:** Visual-first communication preference

### 1.3 Success Metrics

| Metric                 | Target       | Measurement          |
| ---------------------- | ------------ | -------------------- |
| Photo mood adoption    | 20% of users | Users with 1+ photo  |
| Photos per active user | 2+ monthly   | Photo moods / MAU    |
| Time to log mood       | -30%         | Photo vs text timing |

---

## 2. Functional Requirements

### 2.1 Core Features

| ID    | Requirement                            | Priority |
| ----- | -------------------------------------- | -------- |
| PM-01 | Capture photo with camera              | Must     |
| PM-02 | Select photo from library              | Must     |
| PM-03 | Add mood score (1-5) to photo          | Must     |
| PM-04 | Add optional caption                   | Should   |
| PM-05 | Add mood tags (emotions)               | Should   |
| PM-06 | View photo mood gallery                | Must     |
| PM-07 | Filter gallery by mood/date            | Should   |
| PM-08 | Delete photo mood                      | Must     |
| PM-09 | AI mood suggestion from photo (opt-in) | Could    |
| PM-10 | Share photo mood to circles (private)  | Could    |

### 2.2 Privacy Features

| ID    | Requirement                         | Priority |
| ----- | ----------------------------------- | -------- |
| PV-01 | Photos stored encrypted             | Must     |
| PV-02 | Photos never shared without consent | Must     |
| PV-03 | Delete all photos option            | Must     |
| PV-04 | Local-only option (no cloud)        | Could    |

---

## 3. Technical Requirements

### 3.1 Data Models

```sql
-- Photo moods
CREATE TABLE photo_moods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Mood data
    mood_score INTEGER NOT NULL CHECK (mood_score BETWEEN 1 AND 5),
    caption TEXT,
    emotion_tags TEXT[], -- ['happy', 'peaceful', 'excited']

    -- Photo reference
    photo_storage_path TEXT NOT NULL, -- Supabase Storage path
    photo_thumbnail_path TEXT, -- Compressed thumbnail

    -- AI analysis (optional)
    ai_mood_suggestion INTEGER,
    ai_emotions_detected TEXT[],
    ai_analyzed_at TIMESTAMPTZ,

    -- Metadata
    location_name TEXT, -- Optional, user-entered
    logged_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- Sharing
    shared_to_circle_id UUID REFERENCES circles(id)
);

-- RLS
ALTER TABLE photo_moods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own photo moods"
    ON photo_moods FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Circle members can view shared"
    ON photo_moods FOR SELECT
    USING (
        shared_to_circle_id IS NOT NULL AND
        shared_to_circle_id IN (
            SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
        )
    );

-- Index
CREATE INDEX idx_photo_moods_user_date ON photo_moods(user_id, logged_at DESC);
```

### 3.2 Supabase Storage Bucket

```sql
-- Create bucket for mood photos
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'mood-photos',
    'mood-photos',
    false, -- Private bucket
    5242880, -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/heic']
);

-- Storage policies
CREATE POLICY "Users can upload own photos"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'mood-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can view own photos"
ON storage.objects FOR SELECT
USING (
    bucket_id = 'mood-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can delete own photos"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'mood-photos' AND
    auth.uid()::text = (storage.foldername(name))[1]
);
```

### 3.3 Swift Models

```swift
struct PhotoMood: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let moodScore: Int
    let caption: String?
    let emotionTags: [String]?
    let photoStoragePath: String
    let photoThumbnailPath: String?
    let aiMoodSuggestion: Int?
    let aiEmotionsDetected: [String]?
    let locationName: String?
    let loggedAt: Date
    let sharedToCircleId: UUID?

    // Computed
    var photoUrl: URL? {
        // Construct signed URL from storage path
        nil // Populated via service
    }
}

enum MoodEmotion: String, CaseIterable, Codable {
    case happy
    case peaceful
    case excited
    case grateful
    case loved
    case content
    case anxious
    case sad
    case stressed
    case tired
    case frustrated
    case lonely

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .peaceful: return "😌"
        case .excited: return "🤩"
        case .grateful: return "🙏"
        case .loved: return "🥰"
        case .content: return "😊"
        case .anxious: return "😰"
        case .sad: return "😢"
        case .stressed: return "😫"
        case .tired: return "😴"
        case .frustrated: return "😤"
        case .lonely: return "🥺"
        }
    }
}
```

### 3.4 Photo Mood Service

```swift
import PhotosUI
import SwiftUI

@MainActor
class PhotoMoodService: ObservableObject {
    private let supabase: SupabaseClient

    @Published var photoMoods: [PhotoMood] = []
    @Published var isUploading = false

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Create Photo Mood

    func createPhotoMood(
        image: UIImage,
        moodScore: Int,
        caption: String?,
        emotions: [MoodEmotion],
        locationName: String?
    ) async throws -> PhotoMood {
        isUploading = true
        defer { isUploading = false }

        let userId = try await supabase.auth.session.user.id

        // Compress image
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoMoodError.compressionFailed
        }

        // Create thumbnail
        let thumbnail = image.preparingThumbnail(of: CGSize(width: 200, height: 200))
        let thumbnailData = thumbnail?.jpegData(compressionQuality: 0.6)

        // Generate file paths
        let timestamp = Int(Date().timeIntervalSince1970)
        let photoPath = "\(userId)/\(timestamp).jpg"
        let thumbPath = "\(userId)/thumb_\(timestamp).jpg"

        // Upload to Supabase Storage
        try await supabase.storage
            .from("mood-photos")
            .upload(path: photoPath, file: imageData, options: .init(contentType: "image/jpeg"))

        if let thumbData = thumbnailData {
            try await supabase.storage
                .from("mood-photos")
                .upload(path: thumbPath, file: thumbData, options: .init(contentType: "image/jpeg"))
        }

        // Create database record
        let photoMood: PhotoMood = try await supabase
            .from("photo_moods")
            .insert([
                "user_id": userId.uuidString,
                "mood_score": moodScore,
                "caption": caption as Any,
                "emotion_tags": emotions.map { $0.rawValue },
                "photo_storage_path": photoPath,
                "photo_thumbnail_path": thumbPath,
                "location_name": locationName as Any
            ])
            .select()
            .single()
            .execute()
            .value

        photoMoods.insert(photoMood, at: 0)
        return photoMood
    }

    // MARK: - Fetch Photo Moods

    func fetchPhotoMoods(limit: Int = 50, offset: Int = 0) async throws {
        let userId = try await supabase.auth.session.user.id

        let moods: [PhotoMood] = try await supabase
            .from("photo_moods")
            .select()
            .eq("user_id", value: userId)
            .order("logged_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value

        if offset == 0 {
            photoMoods = moods
        } else {
            photoMoods.append(contentsOf: moods)
        }
    }

    // MARK: - Get Signed URL

    func getPhotoUrl(for photoMood: PhotoMood) async throws -> URL {
        let signedUrl = try await supabase.storage
            .from("mood-photos")
            .createSignedURL(path: photoMood.photoStoragePath, expiresIn: 3600)

        return signedUrl
    }

    func getThumbnailUrl(for photoMood: PhotoMood) async throws -> URL? {
        guard let thumbPath = photoMood.photoThumbnailPath else { return nil }

        let signedUrl = try await supabase.storage
            .from("mood-photos")
            .createSignedURL(path: thumbPath, expiresIn: 3600)

        return signedUrl
    }

    // MARK: - Delete

    func deletePhotoMood(_ photoMood: PhotoMood) async throws {
        // Delete from storage
        try await supabase.storage
            .from("mood-photos")
            .remove(paths: [photoMood.photoStoragePath])

        if let thumbPath = photoMood.photoThumbnailPath {
            try await supabase.storage
                .from("mood-photos")
                .remove(paths: [thumbPath])
        }

        // Delete database record
        try await supabase
            .from("photo_moods")
            .delete()
            .eq("id", value: photoMood.id)
            .execute()

        photoMoods.removeAll { $0.id == photoMood.id }
    }

    // MARK: - Delete All (Privacy)

    func deleteAllPhotoMoods() async throws {
        let userId = try await supabase.auth.session.user.id

        // Get all paths
        let moods: [PhotoMood] = try await supabase
            .from("photo_moods")
            .select("photo_storage_path, photo_thumbnail_path")
            .eq("user_id", value: userId)
            .execute()
            .value

        // Delete from storage
        var paths = moods.map { $0.photoStoragePath }
        paths.append(contentsOf: moods.compactMap { $0.photoThumbnailPath })

        try await supabase.storage
            .from("mood-photos")
            .remove(paths: paths)

        // Delete all records
        try await supabase
            .from("photo_moods")
            .delete()
            .eq("user_id", value: userId)
            .execute()

        photoMoods = []
    }
}

enum PhotoMoodError: Error {
    case compressionFailed
    case uploadFailed
}
```

---

## 4. UI/UX Specifications

### 4.1 Photo Mood Capture

```
┌─────────────────────────────────┐
│ ← Photo Mood                    │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │                             │ │
│ │      [Photo Preview]        │ │
│ │                             │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ How are you feeling?            │
│ ┌─────────────────────────────┐ │
│ │ 😢  😕  😐  🙂  😊          │ │
│ │           ↑                 │ │
│ │        Selected             │ │
│ └─────────────────────────────┘ │
│                                 │
│ Add emotions (optional)         │
│ [😊 Happy] [😌 Peaceful]        │
│ [🤩 Excited] [🙏 Grateful]      │
│ [+ More]                        │
│                                 │
│ Caption (optional)              │
│ ┌─────────────────────────────┐ │
│ │ Sunday morning vibes...     │ │
│ └─────────────────────────────┘ │
│                                 │
│        [Save Photo Mood]        │
│                                 │
└─────────────────────────────────┘
```

### 4.2 Photo Mood Gallery

```
┌─────────────────────────────────┐
│ Photo Moods                 📷  │
├─────────────────────────────────┤
│                                 │
│ [All] [😊 Happy] [😢 Sad] [...]│
│                                 │
│ This Week                       │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐    │
│ │    │ │    │ │    │ │    │    │
│ │ 😊 │ │ 🙂 │ │ 😌 │ │ 😊 │    │
│ └────┘ └────┘ └────┘ └────┘    │
│                                 │
│ Last Week                       │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐    │
│ │    │ │    │ │    │ │    │    │
│ │ 😕 │ │ 😊 │ │ 😊 │ │ 🙂 │    │
│ └────┘ └────┘ └────┘ └────┘    │
│                                 │
│ [Load More]                     │
│                                 │
└─────────────────────────────────┘
```

### 4.3 Photo Mood Detail

```
┌─────────────────────────────────┐
│ ← Jan 15, 2024                  │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ │      [Full Photo]           │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ 😊 Feeling Great                │
│                                 │
│ [😊 Happy] [🙏 Grateful]        │
│                                 │
│ "Sunday morning vibes with      │
│  coffee and sunshine"           │
│                                 │
│ 9:15 AM • Home                  │
│                                 │
│        [🗑️ Delete]              │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can capture new photo with camera
- [ ] Users can select existing photo from library
- [ ] Mood score (1-5) is required
- [ ] Photos upload and display correctly
- [ ] Thumbnails load in gallery view
- [ ] Users can delete individual photo moods
- [ ] "Delete all photos" option works
- [ ] Photos are private by default

---

## 6. Privacy Considerations

| Concern               | Mitigation                       |
| --------------------- | -------------------------------- |
| Photo access to faces | No face analysis without consent |
| Location data in EXIF | Strip EXIF before upload         |
| Accidental sharing    | Explicit share action required   |
| Data retention        | Clear delete-all option          |
| Third-party access    | Photos encrypted at rest         |

---

## 7. Rollout Plan

### Phase 1 (Week 1)

- Photo capture and upload
- Basic mood logging
- Gallery view

### Phase 2 (Week 2)

- Emotion tags
- Filtering
- Delete functionality
- Privacy settings
