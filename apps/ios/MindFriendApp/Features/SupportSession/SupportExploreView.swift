import SwiftUI

/// Explore offers short practices, familiar suggestions, and focused category pages.
struct SupportExploreView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var navigator: SupportShellNavigator
    @EnvironmentObject private var pins: SupportPinStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var query = ""
    @State private var activeEnrollment: ProgramEnrollment?
    @State private var circles: [FriendCircle] = []
    @State private var replaceCandidate: SupportPin?
    @State private var showInviteBuddy = false

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let exploreSections: [SupportSection] = [
        .practices, .programsAndPathways, .toolsAndExperiments, .peopleAndCircles
    ]

    var body: some View {
        NavigationStack(path: $navigator.explorePath) {
            List {
                if isSearching {
                    searchResults
                } else {
                    Section("Try one small thing") {
                        ForEach(SupportActivityTemplateKey.allCases, id: \.self) { template in
                            SupportActivityChoiceButton(template: template, origin: .explore)
                        }
                    }
                    .listRowBackground(SupportTheme.surface)
                    suggestedSection
                    categorySection
                    activeProgramSection
                }
            }
            .supportScreen()

            .navigationTitle(SupportShellTab.explore.title)
            .searchable(text: $query, prompt: Text("Search practices, programs, and people"))
            .navigationDestination(for: SupportDestination.self) { destination in
                SupportDestinationView(destination: destination)
            }
            .navigationDestination(for: SupportSection.self) { section in
                categoryPage(section)
            }
            .sheet(item: $replaceCandidate) { candidate in
                ReplacePinSheet(candidate: candidate)
                    .environmentObject(pins)
            }
            .sheet(isPresented: $showInviteBuddy) {
                InviteBuddySheet()
                    .environmentObject(container)
            }
            .task(id: appState.currentUser?.id) { await loadActiveWork() }
        }
    }

    // MARK: Sections

    private var suggestedDestinations: [SupportDestination] {
        let available = Set(Self.exploreSections.flatMap { SupportDestination.exploreRows(in: $0) }
            .filter { $0 != .quote })
        let candidates = pins.pins.map(\.destination) + [SupportDestination.quickBreathing, .journal, .sleep, .sensoryToolkit]
        var seen = Set<SupportDestination>()
        return Array(candidates.filter { available.contains($0) && seen.insert($0).inserted }.prefix(5))
    }

    private var suggestedSection: some View {
        Section("Suggested for you") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    ForEach(suggestedDestinations) { destination in
                        NavigationLink(value: destination) {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                cardIcon(destination.icon, area: destination.area)
                                Text(destination.title)
                                    .font(.headline)
                                    .foregroundStyle(SupportTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let subtitle = destination.subtitle {
                                    Text(subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(SupportTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(width: SupportTheme.readableWidth / (dynamicTypeSize.isAccessibilitySize ? 2 : 3), alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .supportCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityAction(named: pins.isPinned(destination) ? Text("Unpin from Today") : Text("Pin to Today")) {
                            togglePin(SupportPin(destination))
                        }
                        .contextMenu { pinSwipeAction(SupportPin(destination)) }
                    }
                }
                // Every card takes the tallest card's height, so the row has no ragged band.
                .fixedSize(horizontal: false, vertical: true)
            }
            .listRowInsets(EdgeInsets(top: SupportTheme.Spacing.xs, leading: 0, bottom: SupportTheme.Spacing.xs, trailing: 0))
            .listRowBackground(SupportTheme.canvas)
        }
    }

    private var categorySection: some View {
        Section("Browse by category") {
            // A two-by-two grid: tiles in a row share its height, and titles wrap instead of clipping.
            // At accessibility sizes the same tiles stack; AnyLayout keeps their identity across the change.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: SupportTheme.Spacing.s))
                : AnyLayout(GridLayout(horizontalSpacing: SupportTheme.Spacing.s, verticalSpacing: SupportTheme.Spacing.s))
            layout {
                ForEach(0..<(Self.exploreSections.count + 1) / 2, id: \.self) { row in
                    // Outside a grid layout a GridRow acts as a group, so the stack lists the tiles one by one.
                    GridRow {
                        ForEach(Self.exploreSections[(row * 2)..<min(row * 2 + 2, Self.exploreSections.count)], id: \.self) {
                            categoryTile($0)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: SupportTheme.Spacing.xs, leading: 0, bottom: SupportTheme.Spacing.xs, trailing: 0))
            .listRowBackground(SupportTheme.canvas)
        }
    }

    /// A button rather than a NavigationLink: inside a List, links gain a disclosure chevron outside the card.
    private func categoryTile(_ section: SupportSection) -> some View {
        let area = categoryArea(section)
        return Button { navigator.explorePath.append(section) } label: {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                // The card is the area's soft gradient, so the tile is ringed rather than tinted.
                SupportAreaIconTile(icon: categoryIcon(section), area: area, ringed: true)
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .supportAreaCard(area)
        }
        .buttonStyle(.plain)
    }

    private func categoryPage(_ section: SupportSection) -> some View {
        List { destinationSection(section) }
            .supportScreen()
            .safeAreaInset(edge: .top, spacing: 0) { SupportAreaStrip(area: categoryArea(section)) }

            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
    }

    /// Each category takes the area that fits most of what it holds.
    private func categoryArea(_ section: SupportSection) -> SupportTheme.Area {
        switch section {
        case .practices: return .exercises
        case .programsAndPathways: return .quests
        case .toolsAndExperiments: return .insights
        case .peopleAndCircles: return .people
        default: return .exercises
        }
    }

    /// An area tile above a card's title; a destination with no area keeps the neutral accent symbol.
    @ViewBuilder
    private func cardIcon(_ icon: String, area: SupportTheme.Area?) -> some View {
        if let area {
            SupportAreaIconTile(icon: icon, area: area)
        } else {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SupportTheme.accent)
                .accessibilityHidden(true)
        }
    }

    private func categoryIcon(_ section: SupportSection) -> String {
        switch section {
        case .practices: return "leaf"
        case .programsAndPathways: return "map"
        case .toolsAndExperiments: return "slider.horizontal.3"
        case .peopleAndCircles: return "person.3"
        default: return "square.grid.2x2"
        }
    }

    @ViewBuilder
    private var activeProgramSection: some View {
        if let enrollment = activeEnrollment {
            Section(String(localized: "Active program")) {
                // Pinning this row pins this specific enrollment, not the Programs library.
                let activePin = SupportPin(.programs, record: .init(
                    kind: .enrollment, id: enrollment.id,
                    relatedProgramID: enrollment.programId,
                    title: enrollment.program?.title
                ))
                HStack(spacing: SupportTheme.Spacing.xs) {
                    if let program = enrollment.program {
                        NavigationLink {
                            ProgramDetailView(program: program)
                        } label: {
                            SupportRowLabel(
                                title: program.title,
                                subtitle: String(localized: "Day \(enrollment.currentDay) of \(program.durationDays)"),
                                icon: "book.fill",
                                area: .quests
                            )
                        }
                    } else {
                        NavigationLink(value: SupportDestination.programs) {
                            SupportRowLabel(
                                title: String(localized: "Continue your program"),
                                subtitle: String(localized: "Day \(enrollment.currentDay)"),
                                icon: "book.fill",
                                area: .quests
                            )
                        }
                    }
                    if pins.isPinned(activePin) {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(SupportTheme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .swipeActions(edge: .trailing) { pinSwipeAction(activePin) }
                .accessibilityAction(named: pins.isPinned(activePin)
                                     ? Text("Unpin from Today") : Text("Pin to Today")) {
                    togglePin(activePin)
                }
            }
            .listRowBackground(SupportTheme.surface)
        }
    }

    private func destinationSection(_ section: SupportSection) -> some View {
        Section(section.title) {
            if section == .peopleAndCircles {
                activeCircleRows
            }
            ForEach(SupportDestination.exploreRows(in: section).filter { $0 != .quote }) { destination in
                destinationRow(destination)
            }
            if section == .peopleAndCircles {
                Button {
                    showInviteBuddy = true
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Invite a buddy"),
                        subtitle: String(localized: "Send an invitation to someone you trust"),
                        icon: "person.badge.plus",
                        area: .people
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(SupportTheme.surface)
    }

    @ViewBuilder
    private var activeCircleRows: some View {
        ForEach(circles.prefix(3)) { circle in
            NavigationLink {
                CircleDetailView(circle: circle)
            } label: {
                SupportRowLabel(
                    title: circle.name,
                    subtitle: String(localized: "Your circle · \(circle.memberCount) members"),
                    icon: "person.3.fill",
                    area: .people
                )
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = Self.exploreSections.flatMap { SupportDestination.exploreRows(in: $0) }
            .filter { $0 != .quote && $0.matches(query) }
        if matches.isEmpty {
            Section {
                SupportUnavailableState(
                    title: String(localized: "Nothing found"),
                    message: String(localized: "Try another word, or clear the search to browse everything.")
                )
            }
            .listRowBackground(SupportTheme.surface)
        } else {
            Section(String(localized: "Results")) {
                ForEach(matches) { destination in
                    destinationRow(destination, showsSection: true)
                }
            }
            .listRowBackground(SupportTheme.surface)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func destinationRow(_ destination: SupportDestination, showsSection: Bool = false) -> some View {
        let label = SupportRowLabel(
            title: destination.title,
            subtitle: showsSection ? destination.section.title : destination.subtitle,
            icon: destination.icon,
            area: destination.area
        )
        if destination.isPinnable {
            let pin = SupportPin(destination)
            HStack(spacing: SupportTheme.Spacing.xs) {
                NavigationLink(value: destination) { label }
                if pins.isPinned(pin) {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(SupportTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .swipeActions(edge: .trailing) { pinSwipeAction(pin) }
            .accessibilityAction(named: pins.isPinned(pin)
                                 ? Text("Unpin from Today") : Text("Pin to Today")) {
                togglePin(pin)
            }
        } else {
            NavigationLink(value: destination) { label }
        }
    }

    @ViewBuilder
    private func pinSwipeAction(_ pin: SupportPin) -> some View {
        Button {
            togglePin(pin)
        } label: {
            Label(pins.isPinned(pin) ? String(localized: "Unpin") : String(localized: "Pin"),
                  systemImage: pins.isPinned(pin) ? "pin.slash" : "pin")
        }
        .tint(SupportTheme.accent)
    }

    private func togglePin(_ pin: SupportPin) {
        if pins.isPinned(pin) {
            pins.unpin(pin)
        } else if pins.isFull {
            replaceCandidate = pin
        } else {
            pins.pin(pin)
        }
    }

    // MARK: Data (real services; failures leave the static destinations fully usable)

    private func loadActiveWork() async {
        guard let userID = appState.currentUser?.id, appState.authState == .authenticated else {
            activeEnrollment = nil
            circles = []
            return
        }
        async let enrollment = try? container.supabaseDataService.getActiveEnrollment()
        async let joined = try? container.supabaseDataService.getCircles()
        let (loadedEnrollment, loadedCircles) = await (enrollment, joined)
        // A late result must not appear under a different account.
        guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
        activeEnrollment = loadedEnrollment
        circles = loadedCircles ?? []
    }
}

/// Explicit replacement chooser shown when three pins already exist. Nothing is evicted silently.
struct ReplacePinSheet: View {
    let candidate: SupportPin
    @EnvironmentObject private var pins: SupportPinStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Today shows up to \(SupportPinStore.maxPins) pins. Choose one to replace with \(candidate.record?.title ?? candidate.destination.title).")
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .listRowBackground(SupportTheme.surface)
                Section(String(localized: "Current pins")) {
                    ForEach(pins.pins) { pinned in
                        Button {
                            pins.replace(pinned, with: candidate)
                            dismiss()
                        } label: {
                            SupportRowLabel(
                                title: String(localized: "Replace \(pinned.record?.title ?? pinned.destination.title)"),
                                icon: pinned.destination.icon,
                                area: pinned.destination.area
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(SupportTheme.surface)
            }
            .supportScreen()

            .navigationTitle(String(localized: "Replace a pin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .supportSheet()
        .presentationDetents([.medium, .large])
    }
}

// Hubs that give retained capabilities a named home in Explore (SR-03…SR-07); You's hubs stay in
// SupportRetainedHubs.swift.

// MARK: - Journal chooser (Explore → Practices)

/// Text and voice journals are separate existing tools; this chooser names both instead of hiding one.
struct SupportJournalHub: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    JournalListView()
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Text journal"),
                        subtitle: String(localized: "Write and revisit entries"),
                        icon: "book.closed",
                        area: .journal
                    )
                }
                NavigationLink {
                    VoiceJournalRecorderView()
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Voice journal"),
                        subtitle: String(localized: "Record an entry. The microphone starts only when you ask."),
                        icon: "mic.fill",
                        area: .voice
                    )
                }
                NavigationLink {
                    CreativeGalleryView()
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Voice journal history"),
                        subtitle: String(localized: "Saved recordings and other creative work"),
                        icon: "waveform",
                        area: .voice
                    )
                }
            } footer: {
                Text("Text and voice entries are kept separately, and each list is searched on its own. Art and drawing tools are in Create.")
            }
            .listRowBackground(SupportTheme.surface)
        }
        .supportScreen()

        .navigationTitle(SupportDestination.journal.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pathways (Explore → Programs and Pathways)

/// Your active pathways open their exact dashboards first; the catalog only starts a new one.
struct SupportPathwaysHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var pathways: [UserPathway] = []
    @State private var state = HubLoad.loading
    @State private var selected: UserPathway?
    @State private var retry = UUID()

    var body: some View {
        List {
            Section(String(localized: "Your pathways")) {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HubFailedView(message: String(localized: "Your active pathways couldn't be loaded.")) { retry = UUID() }
                case .loaded:
                    if pathways.isEmpty {
                        Text("You don't have an active pathway.")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    ForEach(pathways) { pathway in
                        ActivePathwayCard(userPathway: pathway) { selected = pathway }
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
            .listRowBackground(SupportTheme.surface)
            Section {
                NavigationLink {
                    PathwaySelectionView().environmentObject(container)
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Start a new pathway"),
                        subtitle: String(localized: "Browse life transitions"),
                        icon: "signpost.right.fill",
                        area: .quests
                    )
                }
            }
            .listRowBackground(SupportTheme.surface)
        }
        .supportScreen()

        .navigationTitle(SupportDestination.pathways.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            if let selected {
                PathwayDashboardView(userPathway: selected).environmentObject(container)
            }
        }
        .task(id: retry) { await load() }
    }

    private func load() async {
        guard let userID = appState.currentUser?.id else { return }
        state = .loading
        do {
            let result = try await container.transitionService.fetchActivePathways()
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            pathways = result
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            state = .failed
        }
    }
}

// MARK: - Seasonal events (Explore → People and Circles)

struct SupportSeasonalHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var event: SeasonalEvent?
    @State private var participation: EventParticipation?
    @State private var state = HubLoad.loading
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HubFailedView(message: String(localized: "Events couldn't be loaded.")) { retry = UUID() }
                case .loaded:
                    if let event {
                        SeasonalEventCard(event: event, participation: participation) { join(event) }
                    } else {
                        Text("There's no event running right now.")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .supportScreen()
        .navigationTitle(SupportDestination.seasonalEvents.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retry) { await load() }
    }

    private func load() async {
        guard let userID = appState.currentUser?.id else { return }
        state = .loading
        do {
            let events = try await container.supabaseDataService.getActiveEvents()
            let all = try await container.supabaseDataService.getEventParticipation()
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            event = events.first
            participation = event.flatMap { current in all.first { $0.eventId == current.id } }
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            state = .failed
        }
    }

    /// Joining is an explicit tap on the card's own Join button.
    private func join(_ event: SeasonalEvent) {
        guard let userID = appState.currentUser?.id else { return }
        Task {
            do {
                try await container.supabaseDataService.joinEvent(id: event.id)
                let all = try await container.supabaseDataService.getEventParticipation()
                guard appState.currentUser?.id == userID else { return }
                participation = all.first { $0.eventId == event.id }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

// MARK: - Buddy (Explore → People and Circles)

struct SupportBuddyHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var buddy: BuddyWidgetData?
    @State private var state = HubLoad.loading
    @State private var showInvite = false
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HubFailedView(message: String(localized: "Your buddy status couldn't be loaded.")) { retry = UUID() }
                case .loaded:
                    if let buddy {
                        // Encouragement is only sent when the person taps the widget's own button.
                        BuddyWidget(buddyData: buddy, onSendEncouragement: { sendEncouragement(buddy) })
                    } else {
                        InviteBuddyPrompt(onTap: { showInvite = true })
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .supportScreen()
        .navigationTitle(SupportDestination.buddy.title)
        .navigationBarTitleDisplayMode(.inline)
        // Joining a friend's code in the sheet creates the buddy; reload so the hub shows it.
        .sheet(isPresented: $showInvite, onDismiss: { retry = UUID() }) {
            InviteBuddySheet().environmentObject(container)
        }
        .task(id: retry) { await load() }
    }

    private func load() async {
        guard let userID = appState.currentUser?.id else { return }
        state = .loading
        do {
            let data = try await container.supabaseDataService.getBuddyWidgetData()
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            buddy = data
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            state = .failed
        }
    }

    private func sendEncouragement(_ data: BuddyWidgetData) {
        guard let userID = appState.currentUser?.id else { return }
        Task {
            do {
                try await container.supabaseDataService.sendEncouragement(
                    to: data.buddyId, relationshipId: data.relationshipId, type: .encouragement
                )
                let refreshed = try await container.supabaseDataService.getBuddyWidgetData()
                guard appState.currentUser?.id == userID else { return }
                buddy = refreshed
            } catch {
                appState.showError(.apiError("Could not send encouragement"))
            }
        }
    }
}
