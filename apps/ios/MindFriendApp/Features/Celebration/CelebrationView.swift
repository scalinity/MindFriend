import SwiftUI

/// Full-screen celebration for a server milestone (level, badge, quest, exercise, program).
struct CelebrationView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let celebration: CelebrationEvent
    var onDismiss: (() -> Void)?

    @State private var isSharing = false
    @State private var showShareSheet = false
    @State private var hasSharedToCircle = false

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()
            CelebrationParticles().ignoresSafeArea()

            VStack(spacing: SupportTheme.Spacing.l) {
                Spacer()
                CelebrationEmblem(.symbol(celebration.displayIconName), tint: SupportTheme.Celebration.gold, diameter: 112)
                VStack(spacing: SupportTheme.Spacing.s) {
                    Text(celebration.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(SupportTheme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(celebration.subtitle)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)
                .celebrationReveal(delay: 0.2)

                Spacer()

                VStack(spacing: SupportTheme.Spacing.s) {
                    Button("Continue") { dismissCelebration() }
                        .buttonStyle(.supportPrimary)
                    Button {
                        Task { await shareToCircle() }
                    } label: {
                        Label(hasSharedToCircle ? "Shared with your circle" : "Share with your circle",
                              systemImage: hasSharedToCircle ? "checkmark" : "person.2")
                    }
                    .buttonStyle(.supportSecondary)
                    .disabled(hasSharedToCircle || isSharing || celebration.sharedToCircle)
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share elsewhere", systemImage: "square.and.arrow.up")
                    }
                    .font(.subheadline)
                    .frame(minHeight: SupportTheme.minimumTarget)
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .padding(.bottom, SupportTheme.Spacing.l)
                .celebrationReveal(delay: 0.35)
            }
            .frame(maxWidth: SupportTheme.readableWidth)
        }
        .tint(SupportTheme.accent)
        .onAppear {
            triggerHaptic()
            hasSharedToCircle = celebration.sharedToCircle
            markAsShown()
            AccessibilityNotification.Announcement("\(celebration.title). \(celebration.subtitle)").post()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareCardSheet(celebration: celebration) {
                markAsSharedExternally()
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func triggerHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func markAsShown() {
        Task {
            try? await container.supabaseDataService.markCelebrationShown(celebrationId: celebration.id)
            Analytics.shared.track(.celebrationShown, properties: [
                "type": celebration.celebrationType.rawValue,
                "value": celebration.value
            ])
        }
    }

    private func shareToCircle() async {
        isSharing = true
        defer { isSharing = false }

        do {
            _ = try await container.supabaseDataService.shareCelebrationToCircles(celebrationId: celebration.id)
            withAnimation {
                hasSharedToCircle = true
            }
        } catch {
            Log.data.error("[Celebration] Share to circle failed: \(error)")
        }
    }

    private func markAsSharedExternally() {
        Task {
            try? await container.supabaseDataService.markCelebrationSharedExternally(celebrationId: celebration.id)
        }
    }

    private func dismissCelebration() {
        Analytics.shared.track(.celebrationDismissed, properties: [
            "type": celebration.celebrationType.rawValue,
            "shared_to_circle": hasSharedToCircle
        ])
        onDismiss?()
        dismiss()
    }
}

// MARK: - Celebration kit

/// One vocabulary for every reward moment: a soft glow, an emblem that settles into place and
/// slow particles in theme hues. Under Reduce Motion each piece cross-fades instead.
enum CelebrationMark {
    case symbol(String)
    case text(String)
}

struct CelebrationEmblem: View {
    let mark: CelebrationMark
    var tint: Color = SupportTheme.Celebration.accent
    var diameter: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    init(_ mark: CelebrationMark, tint: Color = SupportTheme.Celebration.accent, diameter: CGFloat = 96) {
        self.mark = mark
        self.tint = tint
        self.diameter = diameter
    }

    private struct Phase {
        var scale = 0.6
        var opacity = 0.0
    }

    var body: some View {
        ZStack {
            Circle().fill(SupportTheme.elevated)
            Circle().strokeBorder(tint.opacity(0.7), lineWidth: 2)
            switch mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : shown)
            case .text(let value):
                Text(value)
                    .font(.system(size: diameter * 0.4, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(tint)
        .frame(width: diameter, height: diameter)
        .background {
            Circle()
                .fill(RadialGradient(colors: [SupportTheme.Celebration.glow, SupportTheme.Celebration.glow.opacity(0)],
                                     center: .center, startRadius: diameter * 0.35, endRadius: diameter * 1.15))
                .frame(width: diameter * 2.3, height: diameter * 2.3)
        }
        .keyframeAnimator(initialValue: Phase(), trigger: shown) { content, phase in
            content
                .scaleEffect(reduceMotion ? 1 : phase.scale)
                .opacity(phase.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.08, duration: 0.35, spring: .bouncy)
                SpringKeyframe(1.0, duration: 0.3, spring: .smooth)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: 0.3)
            }
        }
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}

/// Slow particles drifting out from the upper centre, drawn in one Canvas in theme hues.
/// Nothing is drawn under Reduce Motion.
struct CelebrationParticles: View {
    var count = 36
    var duration = 2.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    @State private var seeds: [Seed] = []
    @State private var finished = false

    private struct Seed {
        let angle: Double
        let distance: Double
        let size: Double
        let hue: Int
        let delay: Double
        let rounded: Bool
    }

    var body: some View {
        if !reduceMotion && !finished {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(startedAt)
                    let centre = CGPoint(x: size.width / 2, y: size.height * 0.38)
                    let palette = [SupportTheme.Celebration.accent, SupportTheme.Celebration.gold, SupportTheme.Celebration.glow]
                    for seed in seeds {
                        let t = (elapsed - seed.delay) / duration
                        guard t > 0, t < 1 else { continue }
                        let eased = 1 - pow(1 - t, 3)
                        let x = centre.x + cos(seed.angle) * seed.distance * eased
                        let y = centre.y + sin(seed.angle) * seed.distance * eased + 60 * t * t
                        let rect = CGRect(x: x - seed.size / 2, y: y - seed.size / 2, width: seed.size, height: seed.size)
                        var layer = context
                        layer.opacity = 1 - t
                        let shape = seed.rounded ? Path(roundedRect: rect, cornerRadius: seed.size / 3) : Path(ellipseIn: rect)
                        layer.fill(shape, with: .color(palette[seed.hue]))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                startedAt = Date()
                seeds = (0..<count).map { _ in
                    Seed(angle: .random(in: 0...(2 * .pi)), distance: .random(in: 90...260),
                         size: .random(in: 4...9), hue: .random(in: 0...2), delay: .random(in: 0...0.5),
                         rounded: .random())
                }
                try? await Task.sleep(for: .seconds(duration + 0.6))
                finished = true
            }
        }
    }
}

/// Earlier callers pass their own colours; particles now always use the theme hues.
struct ConfettiView: View {
    var colors: [Color] = []
    var body: some View { CelebrationParticles() }
}

/// Content that rises gently into place after the emblem; under Reduce Motion it only fades in.
private struct CelebrationReveal: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.6, bounce: 0.2).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func celebrationReveal(delay: Double = 0) -> some View {
        modifier(CelebrationReveal(delay: delay))
    }
}

// MARK: - Completion moments (session saves)

/// A brief check and accent bloom after a durable save: an activity finished, a reflection
/// or check-in saved, a step done, a session closed. It never blocks touches.
struct CompletionMomentView: View {
    let moment: CompletionMoment
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            CelebrationEmblem(.symbol("checkmark"), diameter: moment.soft ? 52 : 72)
            Text(moment.title)
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, SupportTheme.Spacing.xl)
        .padding(.vertical, SupportTheme.Spacing.l)
        .background(SupportTheme.elevated, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(moment.soft ? 1.2 : 1.7))
            onFinish()
        }
    }
}

private struct CompletionMomentModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let moment = appState.completionMoment {
                    CompletionMomentView(moment: moment) {
                        if appState.completionMoment?.id == moment.id { appState.completionMoment = nil }
                    }
                    .id(moment.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(.easeInOut(duration: 0.24), value: appState.completionMoment)
    }
}

/// Simple celebrations requested through `AppState.showCelebration(title:subtitle:icon:)`.
private struct SimpleCelebrationModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if appState.showSimpleCelebration {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        CelebrationEmblem(.symbol(appState.celebrationIcon.isEmpty ? "sparkles" : appState.celebrationIcon),
                                          tint: SupportTheme.Celebration.gold, diameter: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.celebrationTitle).font(.headline).foregroundStyle(SupportTheme.textPrimary)
                            if !appState.celebrationSubtitle.isEmpty {
                                Text(appState.celebrationSubtitle).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.elevated, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    .shadow(color: .black.opacity(0.15), radius: 18, y: 6)
                    .padding(.horizontal, SupportTheme.Spacing.m)
                    .frame(maxWidth: SupportTheme.readableWidth)
                    .accessibilityElement(children: .combine)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task {
                        AccessibilityNotification.Announcement("\(appState.celebrationTitle). \(appState.celebrationSubtitle)").post()
                        try? await Task.sleep(for: .seconds(2.4))
                        appState.showSimpleCelebration = false
                    }
                }
            }
            .animation(.easeInOut(duration: 0.24), value: appState.showSimpleCelebration)
    }
}

extension View {
    /// Shows completion moments; mounted at the shell and inside full-screen activity covers.
    func completionMoments() -> some View { modifier(CompletionMomentModifier()) }
    /// Shows `AppState.showCelebration` requests as a calm card at the top of the screen.
    func simpleCelebrations() -> some View { modifier(SimpleCelebrationModifier()) }
}

// MARK: - Celebration View Modifier

/// View modifier to show pending celebrations
struct CelebrationModifier: ViewModifier {
    @EnvironmentObject var container: DependencyContainer
    @Binding var pendingCelebrations: [CelebrationEvent]

    @State private var currentCelebration: CelebrationEvent?

    func body(content: Content) -> some View {
        content
            .onChange(of: pendingCelebrations) { _, newValue in
                if currentCelebration == nil, let first = newValue.first {
                    currentCelebration = first
                }
            }
            .fullScreenCover(item: $currentCelebration) { celebration in
                CelebrationView(celebration: celebration) {
                    // Remove shown celebration and show next
                    pendingCelebrations.removeAll { $0.id == celebration.id }
                    if let next = pendingCelebrations.first {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            currentCelebration = next
                        }
                    }
                }
                .environmentObject(container)
            }
    }
}

extension View {
    /// Shows celebration modals for pending celebrations
    func celebrationOverlay(pending: Binding<[CelebrationEvent]>) -> some View {
        modifier(CelebrationModifier(pendingCelebrations: pending))
    }
}

// MARK: - Preview

#Preview("Quest Milestone") {
    CelebrationView(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .questMilestone,
            value: 30,
            badgeId: nil,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date()
        )
    )
    .environmentObject(DependencyContainer.preview)
}

#Preview("Level Up") {
    CelebrationView(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .levelUp,
            value: 10,
            badgeId: nil,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date()
        )
    )
    .environmentObject(DependencyContainer.preview)
}

#Preview("Badge Unlock") {
    CelebrationView(
        celebration: CelebrationEvent(
            id: UUID(),
            userId: UUID(),
            celebrationType: .badgeUnlock,
            value: 1,
            badgeId: UUID(),
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date(),
            badgeTitle: "Week Warrior",
            badgeDescription: "Complete 7 days in a row",
            badgeIconName: "flame.fill"
        )
    )
    .environmentObject(DependencyContainer.preview)
}
