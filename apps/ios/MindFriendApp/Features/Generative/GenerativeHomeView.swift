import SwiftUI

/// Main hub for AI-generated wellness content
/// Provides quick generate buttons, recent history, and favorites access
struct GenerativeHomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject var appState: AppState
    @StateObject private var service: GeneratedContentService
    @State private var recentContent: [GeneratedContent] = []
    @State private var favorites: [GeneratedContent] = []
    @State private var isGenerating = false
    @State private var generatingType: GeneratedContentType?
    @State private var error: String?
    @State private var showVoicePreferences = false
    @State private var selectedContent: GeneratedContent?
    @State private var quotaStatus: ContentQuotaStatus?
    @State private var selectedSoundscape: BackgroundSoundType?

    init(service: GeneratedContentService? = nil) {
        _service = StateObject(wrappedValue: service ?? GeneratedContentService(supabase: supabase))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                if let error {
                    SupportUnavailableState(title: "Content unavailable", message: error, actionTitle: "Try again") {
                        self.error = nil
                        Task { await loadData() }
                    }
                }
                // Quick Generate Section
                quickGenerateSection

                // Soundscapes Section
                soundscapesSection

                // Recent Section
                recentSection

                // Favorites Section
                favoritesSection

                // Quota Status - only show for free tier users
                if let quota = quotaStatus, !quota.isPremium {
                    quotaStatusView(quota)
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Made for you")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showVoicePreferences = true
                } label: {
                    Image(systemName: "gearshape")
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .accessibilityLabel("Voice preferences")
            }
        }
        .sheet(isPresented: $showVoicePreferences) {
            NavigationStack {
                VoicePreferencesView(service: service)
            }
        }
        .sheet(item: $selectedContent, onDismiss: {
            // Refresh content lists to pick up favorite changes
            Task {
                await refreshContent()
            }
        }) { content in
            NavigationStack {
                if content.contentType == .sleepStory {
                    GeneratedStoryView(content: content)
                } else {
                    GeneratedMeditationView(content: content)
                }
            }
        }
        .sheet(item: $selectedSoundscape) { soundscape in
            NavigationStack {
                SoundscapePlayerView(soundscape: soundscape)
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Quick Generate Section

    private var quickGenerateSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Quick Generate")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: SupportTheme.Spacing.s) {
                ForEach(GeneratedContentType.allCases) { type in
                    quickGenerateButton(for: type)
                }
            }
        }
    }

    private func quickGenerateButton(for type: GeneratedContentType) -> some View {
        Button {
            Task {
                await generateContent(type: type)
            }
        } label: {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.accent.opacity(0.15))
                        .frame(width: 56, height: 56)

                    if generatingType == type {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: type.icon)
                            .font(.title2)
                            .foregroundStyle(SupportTheme.accent)
                    }
                }

                Text(type.shortDisplayName)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(SupportTheme.textPrimary)
            }
        }
        .disabled(isGenerating || (quotaStatus?.isExhausted ?? false))
        .opacity((quotaStatus?.isExhausted ?? false) ? 0.5 : 1)
    }

    // MARK: - Soundscapes Section

    private var soundscapesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Ambient Soundscapes")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.s) {
                    // Free sounds
                    ForEach(BackgroundSoundType.freeSounds, id: \.self) { sound in
                        soundscapeCard(for: sound, isPremium: false)
                    }

                    // Premium sounds with badge
                    ForEach(BackgroundSoundType.premiumSounds, id: \.self) { sound in
                        soundscapeCard(for: sound, isPremium: true)
                    }
                }
            }
        }
    }

    private func soundscapeCard(for sound: BackgroundSoundType, isPremium: Bool) -> some View {
        Button {
            if isPremium && appState.entitlements.tier != .premium {
                appState.showPaywall = true
            } else {
                selectedSoundscape = sound
            }
        } label: {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .fill(SupportTheme.accent.opacity(0.2))

                        Image(systemName: sound.icon)
                            .font(.title)
                            .foregroundStyle(SupportTheme.accent)
                    }
                    .frame(width: 80, height: 60)

                    if isPremium {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                            .padding(SupportTheme.Spacing.xxs)
                            .background(SupportTheme.canvas.opacity(0.6))
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }

                Text(sound.displayName)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 80)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Section

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text("Recent")
                    .font(.headline)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("See All") {
                    ContentHistoryListView(service: service)
                }
                .font(.subheadline)
            }

            if recentContent.isEmpty {
                emptyStateView(
                    icon: "sparkles",
                    title: "Generate your first content",
                    subtitle: "Tap a category above to create personalized wellness content"
                )
            } else {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(recentContent.prefix(5)) { content in
                        ContentRowView(content: content) {
                            selectedContent = content
                        }
                    }
                }
            }
        }
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text("Favorites (\(favorites.count))")
                    .font(.headline)
                Spacer()
                if !favorites.isEmpty {
                    NavigationLink("View All") {
                        FavoritesListView(service: service)
                    }
                    .font(.subheadline)
                }
            }

            if favorites.isEmpty {
                emptyStateView(
                    icon: "heart",
                    title: "No favorites yet",
                    subtitle: "Save your favorite content for quick access"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(favorites.prefix(5)) { content in
                            FavoriteCardView(content: content) {
                                selectedContent = content
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quota Status

    private func quotaStatusView(_ quota: ContentQuotaStatus) -> some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: quota.isPremium ? "infinity" : "chart.bar")
                .foregroundStyle(SupportTheme.textSecondary)

            if quota.isPremium {
                Text("Unlimited generations")
                    .font(.footnote)
                    .foregroundStyle(SupportTheme.textSecondary)
            } else {
                Text("\(quota.used)/\(quota.limit) generations used this month")
                    .font(.footnote)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            if quota.isExhausted {
                Button("Upgrade") {
                    appState.showPaywall = true
                }
                .font(.footnote.bold())
                .foregroundStyle(SupportTheme.accent)
            }
        }
        .supportCard()
    }

    // MARK: - Empty State

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(SupportTheme.textSecondary)

            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(SupportTheme.textSecondary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.l)
    }

    // MARK: - Data Loading

    private func loadData() async {
        // Load content library and favorites (these use RLS, won't fail if authenticated)
        do {
            async let recentTask = service.fetchContentLibrary(limit: 5)
            async let favoritesTask = service.fetchFavorites()

            let (recent, favs) = try await (recentTask, favoritesTask)
            recentContent = recent
            favorites = favs
        } catch {
            print("Failed to load content: \(error)")
        }

        // Load quota status separately - don't block UI if this fails
        do {
            quotaStatus = try await service.fetchQuotaStatus()
        } catch {
            // Default to free tier status if quota fetch fails
            quotaStatus = ContentQuotaStatus(
                used: 0,
                limit: 3,
                isPremium: false,
                resetsAt: nil
            )
            print("Failed to load quota status: \(error)")
        }
    }

    /// Refresh content lists (called when sheet is dismissed to pick up changes)
    private func refreshContent() async {
        do {
            async let recentTask = service.fetchContentLibrary(limit: 5)
            async let favoritesTask = service.fetchFavorites()

            let (recent, favs) = try await (recentTask, favoritesTask)
            recentContent = recent
            favorites = favs
        } catch {
            print("Failed to refresh content: \(error)")
        }
    }

    private func generateContent(type: GeneratedContentType) async {
        isGenerating = true
        generatingType = type
        error = nil

        do {
            let params = GenerateContentParams(
                duration: type.defaultDuration * 60, // Convert minutes to seconds
                voiceId: nil, // Use user's preferred voice
                theme: nil
            )
            let response = try await service.generateContent(type: type, params: params)

            // Update quota status from response
            // Premium users have quotaLimit of 999 (or -1 from legacy), free tier has 3
            let isPremiumQuota = response.quotaLimit > 3 || response.quotaLimit == -1
            quotaStatus = ContentQuotaStatus(
                used: response.quotaUsed,
                limit: isPremiumQuota ? 999 : response.quotaLimit,
                isPremium: isPremiumQuota,
                resetsAt: nil
            )

            // Fetch the full content and show it (safe UUID parsing)
            guard let contentUUID = UUID(uuidString: response.contentId) else {
                self.error = "Invalid content ID returned from server"
                isGenerating = false
                generatingType = nil
                return
            }
            var content = try await service.fetchContent(id: contentUUID)

            // If DB fetch doesn't have audio URL but response does, use response's URL
            // This handles potential timing issues where the fetch happens before DB update is visible
            if content.audioUrl == nil, let responseAudioUrl = response.audioUrl {
                print("[GenerativeHomeView] DB fetch missing audioUrl, using response audioUrl: \(responseAudioUrl)")
                content = GeneratedContent(
                    id: content.id,
                    userId: content.userId,
                    contentType: content.contentType,
                    title: content.title,
                    textContent: content.textContent,
                    audioUrl: responseAudioUrl,
                    voiceId: content.voiceId,
                    duration: content.duration ?? response.duration,
                    qualityScore: content.qualityScore ?? response.qualityScore,
                    status: content.status,
                    generationPrompt: content.generationPrompt,
                    aiModel: content.aiModel,
                    processingTimeMs: content.processingTimeMs,
                    triggerWarnings: content.triggerWarnings,
                    averageRating: content.averageRating,
                    ratingCount: content.ratingCount,
                    seriesId: content.seriesId,
                    seriesOrder: content.seriesOrder,
                    isFavorite: content.isFavorite,
                    playCount: content.playCount,
                    lastPlayedAt: content.lastPlayedAt,
                    generationContext: content.generationContext,
                    userRating: content.userRating,
                    createdAt: content.createdAt,
                    updatedAt: content.updatedAt
                )
            }
            selectedContent = content

            // Refresh recent list
            recentContent = try await service.fetchContentLibrary(limit: 5)

        } catch let contentError as GeneratedContentError {
            error = contentError.errorDescription
        } catch {
            self.error = error.localizedDescription
        }

        isGenerating = false
        generatingType = nil
    }
}

// MARK: - Content Row View

private struct ContentRowView: View {
    let content: GeneratedContent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SupportTheme.Spacing.s) {
                Image(systemName: content.contentType.icon)
                    .font(.title3)
                    .foregroundStyle(SupportTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(content.title)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(content.createdAt.timeAgoDisplay())
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                if content.hasAudio {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(SupportTheme.accent)
                }
            }
            .padding(.vertical, SupportTheme.Spacing.xs)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Favorite Card View

private struct FavoriteCardView: View {
    let content: GeneratedContent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.accent.opacity(0.2))

                    Image(systemName: content.contentType.icon)
                        .font(.title)
                        .foregroundStyle(SupportTheme.accent)
                }
                .frame(width: 100, height: 80)

                Text(content.title)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 100, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content History List View

private struct ContentHistoryListView: View {
    @ObservedObject var service: GeneratedContentService
    @State private var content: [GeneratedContent] = []
    @State private var selectedContent: GeneratedContent?

    var body: some View {
        List(content) { item in
            Button {
                selectedContent = item
            } label: {
                ContentRowView(content: item, onTap: {})
            }
            .buttonStyle(.plain)
        }
        .supportScreen()
        .navigationTitle("History")
        .sheet(item: $selectedContent, onDismiss: {
            Task { await refreshContent() }
        }) { content in
            NavigationStack {
                if content.contentType == .sleepStory {
                    GeneratedStoryView(content: content)
                } else {
                    GeneratedMeditationView(content: content)
                }
            }
        }
        .task {
            await refreshContent()
        }
    }

    private func refreshContent() async {
        do {
            content = try await service.fetchContentLibrary(limit: 50)
        } catch {
            print("Failed to load history: \(error)")
        }
    }
}

// MARK: - Favorites List View

private struct FavoritesListView: View {
    @ObservedObject var service: GeneratedContentService
    @State private var favorites: [GeneratedContent] = []
    @State private var selectedContent: GeneratedContent?

    var body: some View {
        List(favorites) { item in
            Button {
                selectedContent = item
            } label: {
                ContentRowView(content: item, onTap: {})
            }
            .buttonStyle(.plain)
        }
        .supportScreen()
        .navigationTitle("Favorites")
        .sheet(item: $selectedContent, onDismiss: {
            Task { await refreshFavorites() }
        }) { content in
            NavigationStack {
                if content.contentType == .sleepStory {
                    GeneratedStoryView(content: content)
                } else {
                    GeneratedMeditationView(content: content)
                }
            }
        }
        .task {
            await refreshFavorites()
        }
    }

    private func refreshFavorites() async {
        do {
            favorites = try await service.fetchFavorites()
        } catch {
            print("Failed to load favorites: \(error)")
        }
    }
}

// MARK: - Extensions

extension GeneratedContentType {
    var backgroundColor: Color {
        switch self {
        case .meditation, .mindfulness: return SupportTheme.accent
        case .sleepStory: return SupportTheme.accent
        case .breathing: return SupportTheme.accent
        case .affirmation: return SupportTheme.accent
        case .grounding: return SupportTheme.accent
        case .cbt: return SupportTheme.accent
        case .journaling: return SupportTheme.accent
        }
    }

    var shortDisplayName: String {
        switch self {
        case .sleepStory: return "Sleep"
        case .meditation: return "Meditate"
        case .breathing: return "Breathe"
        case .affirmation: return "Affirm"
        case .grounding: return "Ground"
        case .mindfulness: return "Mindful"
        case .cbt: return "CBT"
        case .journaling: return "Journal"
        }
    }
}

extension Date {
    func timeAgoDisplay() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day], from: self, to: now)

        if let day = components.day, day > 0 {
            return day == 1 ? "Yesterday" : "\(day)d ago"
        }
        if let hour = components.hour, hour > 0 {
            return "\(hour)h ago"
        }
        if let minute = components.minute, minute > 0 {
            return "\(minute)m ago"
        }
        return "Just now"
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        GenerativeHomeView()
    }
}
#endif
