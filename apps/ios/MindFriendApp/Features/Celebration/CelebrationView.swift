import SwiftUI

/// Full-screen celebration for a server milestone (level, badge, quest, exercise, program).
struct CelebrationView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let celebration: CelebrationEvent
    var onDismiss: (() -> Void)?

    @State private var isSharing = false
    @State private var showShareSheet = false
    @State private var hasSharedToCircle = false

    var body: some View {
        let style = celebration.celebrationType.heroStyle
        ZStack {
            CelebrationBackdrop(palette: style.palette)
            CelebrationParticles(palette: style.particles).ignoresSafeArea()

            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    CelebrationEmblem(.symbol(celebration.supportIcon), tint: style.palette.ink, diameter: 112,
                                      fill: style.gradient)
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text(celebration.supportTitle)
                            .font(.largeTitle.bold())
                            .foregroundStyle(SupportTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(celebration.supportSubtitle)
                            .font(.body)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
                    .celebrationReveal(delay: 0.2)

                    VStack(spacing: SupportTheme.Spacing.s) {
                        Button("Continue") { dismissCelebration() }
                            .buttonStyle(CelebrationButtonStyle(gradient: style.gradient))
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
                .padding(.top, SupportTheme.Spacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(SupportTheme.accent)
        .onAppear {
            triggerHaptic()
            hasSharedToCircle = celebration.sharedToCircle
            markAsShown()
            AccessibilityNotification.Announcement("\(celebration.supportTitle). \(celebration.supportSubtitle)").post()
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
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) {
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

/// Presentation copy stays separate from server event values and sharing calls.
extension CelebrationEvent {
    var supportTitle: String {
        switch celebrationType {
        case .streakMilestone: return "Your progress"
        case .levelUp: return "Level \(value)"
        case .badgeUnlock: return badgeTitle ?? "New badge"
        case .questMilestone: return "\(value) quests completed"
        case .exerciseMilestone: return "\(value) exercises completed"
        case .programComplete: return "Program complete"
        }
    }

    var supportSubtitle: String {
        switch celebrationType {
        case .streakMilestone: return "Every small step is part of your journey."
        case .levelUp: return "Every small step counted toward this."
        case .badgeUnlock: return badgeDescription ?? "A moment to notice what you've done."
        case .questMilestone: return "Time you've made for yourself, one quest at a time."
        case .exerciseMilestone: return "A growing collection of practices to return to."
        case .programComplete: return "You made space for a \(value)-day program."
        }
    }

    var supportIcon: String { celebrationType == .streakMilestone ? "leaf" : displayIconName }

    var supportShareMessage: String {
        switch celebrationType {
        case .streakMilestone: return "Making time for my wellbeing with MindFriend."
        case .levelUp: return "Reached level \(value) on my wellness journey with MindFriend."
        case .badgeUnlock: return "Earned the \(badgeTitle ?? "new") badge with MindFriend."
        case .questMilestone: return "Completed \(value) wellness quests with MindFriend."
        case .exerciseMilestone: return "Completed \(value) exercises with MindFriend."
        case .programComplete: return "Completed a \(value)-day wellness program with MindFriend."
        }
    }
}

/// The color 1.0.5 gave each kind of milestone, taken through the area and hero tokens.
struct CelebrationHeroStyle {
    /// Vivid background of the emblem and the Continue button; carries `SupportTheme.onHero`.
    let gradient: LinearGradient
    /// Calm backdrop and symbol color on the canvas.
    let palette: AreaPalette
    /// Colors of the drifting particles, readable on the canvas in both appearances.
    let particles: [Color]
}

extension CelebrationType {
    var heroStyle: CelebrationHeroStyle {
        typealias Area = SupportTheme.Area
        let gold = SupportTheme.Celebration.gold
        switch self {
        case .streakMilestone:
            return CelebrationHeroStyle(gradient: SupportTheme.Hero.streak, palette: Area.quests.palette,
                                        particles: [Area.quests.palette.ink, gold, Area.quests.palette.deep])
        case .levelUp:
            return CelebrationHeroStyle(gradient: SupportTheme.Hero.levelUp, palette: Area.journal.palette,
                                        particles: [Area.journal.palette.ink, Area.voice.palette.ink, Area.people.palette.ink])
        case .badgeUnlock:
            return CelebrationHeroStyle(gradient: SupportTheme.Hero.badge, palette: Area.insights.palette,
                                        particles: [Area.insights.palette.ink, gold, Area.voice.palette.ink])
        case .questMilestone:
            return CelebrationHeroStyle(gradient: SupportTheme.Hero.gradient(Area.voice.palette.deep, Area.exercises.palette.deep),
                                        palette: Area.voice.palette,
                                        particles: [Area.voice.palette.ink, Area.exercises.palette.ink, SupportTheme.Celebration.glow])
        case .exerciseMilestone:
            return CelebrationHeroStyle(gradient: SupportTheme.Hero.gradient(Area.insights.palette.deep, Area.exercises.palette.deep),
                                        palette: Area.exercises.palette,
                                        particles: [Area.insights.palette.ink, Area.sensory.palette.ink, Area.exercises.palette.ink])
        case .programComplete:
            return CelebrationHeroStyle(gradient: SupportTheme.Hero.gradient(Area.journal.palette.deep, Area.people.palette.deep),
                                        palette: Area.journal.palette,
                                        particles: [Area.journal.palette.ink, Area.people.palette.ink, gold])
        }
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
    /// A hero gradient fills the emblem and the symbol turns `onHero`; `tint` then colors only the glow.
    var fill: LinearGradient?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var shown = false

    init(_ mark: CelebrationMark, tint: Color = SupportTheme.Celebration.accent, diameter: CGFloat = 96, animated: Bool = true,
         fill: LinearGradient? = nil) {
        self.mark = mark
        self.tint = tint
        self.diameter = diameter
        self.animated = animated
        self.fill = fill
    }

    var animated = true

    var body: some View {
        ZStack {
            if let fill {
                Circle().fill(fill)
                Circle().strokeBorder(SupportTheme.onHero, lineWidth: 2)
                    .padding(SupportTheme.Spacing.xxs)
            } else {
                Circle().fill(SupportTheme.elevated)
                Circle().strokeBorder(tint, lineWidth: 2)
                    .padding(SupportTheme.Spacing.xxs)
            }
            switch mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: diameter * 0.42, weight: .semibold))
            case .text(let value):
                Text(value)
                    .font(.system(size: diameter * 0.4, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(fill == nil ? tint : SupportTheme.onHero)
        .frame(width: diameter, height: diameter)
        .background {
            if !reduceTransparency {
                Circle().fill((fill == nil ? SupportTheme.Celebration.glow : tint).opacity(0.18))
                    .padding(-SupportTheme.Spacing.s)
                Circle().strokeBorder((fill == nil ? SupportTheme.Celebration.glow : tint).opacity(0.3), lineWidth: 1)
                    .padding(-SupportTheme.Spacing.l)
            }
        }
        .padding(SupportTheme.Spacing.l)
        .scaleEffect(reduceMotion || !animated || shown ? 1 : 0.85)
        .opacity(!animated || shown ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.6, bounce: 0.15), value: shown)
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}

/// Slow particles drifting out from the upper centre, drawn in one Canvas in theme hues.
/// Nothing is drawn under Reduce Motion.
struct CelebrationParticles: View {
    var count = 36
    var duration = 2.4
    /// Up to three colors; empty keeps the theme hues.
    var palette: [Color] = []
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
                    let palette = self.palette.isEmpty
                        ? [SupportTheme.Celebration.accent, SupportTheme.Celebration.gold, SupportTheme.Celebration.glow]
                        : self.palette
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
                        layer.fill(shape, with: .color(palette[seed.hue % palette.count]))
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

/// Calm backdrop of a celebration: the canvas with a soft wash of the milestone's color at the top.
/// It sits behind primary and secondary text. Opaque stops, so Reduce Transparency needs no change.
struct CelebrationBackdrop: View {
    let palette: AreaPalette

    var body: some View {
        LinearGradient(colors: [palette.tint, SupportTheme.canvas], startPoint: .top, endPoint: .center)
            .background(SupportTheme.canvas)
            .ignoresSafeArea()
    }
}

/// The primary action of a reward moment shown on a full hero gradient: a white button with
/// text in a deep area color, at least 48pt tall, growing with the text.
struct CelebrationLightButtonStyle: ButtonStyle {
    let label: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(label)
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: SupportTheme.primaryButtonHeight)
            .background(SupportTheme.onHero, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }
}

/// The primary action of a reward moment: a hero gradient behind `onHero` text, at least 48pt
/// tall, growing with the text. Reward screens use it in place of the accent primary button.
struct CelebrationButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(SupportTheme.onHero)
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.vertical, SupportTheme.Spacing.s)
            .frame(maxWidth: .infinity, minHeight: SupportTheme.primaryButtonHeight)
            .background(gradient, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }
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
            if moment.soft {
                Image(systemName: "checkmark.circle")
                    .font(.title2).foregroundStyle(SupportTheme.accent)
            } else {
                CelebrationEmblem(.symbol("checkmark"), diameter: 72)
            }
            Text(moment.title)
                .font(.headline)
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, SupportTheme.Spacing.xl)
        .padding(.vertical, SupportTheme.Spacing.l)
        .background(SupportTheme.elevated, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: SupportTheme.cardRadius).strokeBorder(SupportTheme.border, lineWidth: 1))
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
                    .transition(reduceMotion || moment.soft ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
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
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(appState.celebrationTitle).font(.headline).foregroundStyle(SupportTheme.textPrimary)
                            if !appState.celebrationSubtitle.isEmpty {
                                Text(appState.celebrationSubtitle).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.elevated, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: SupportTheme.cardRadius).strokeBorder(SupportTheme.border, lineWidth: 1))
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
            badgeIconName: "star.fill"
        )
    )
    .environmentObject(DependencyContainer.preview)
}
