import SwiftUI

/// Explore: search plus inline named sections with direct destination rows (SUPPORT_SESSION_SPEC §4.1–4.2).
/// Every row opens an existing destination view. Circles is a direct root row (two deliberate taps from any tab).
struct SupportExploreView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var navigator: SupportShellNavigator
    @EnvironmentObject private var pins: SupportPinStore

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
                    activeProgramSection
                    ForEach(Self.exploreSections, id: \.self) { section in
                        destinationSection(section)
                    }
                }
            }
            .supportCanvas()
            .navigationTitle(SupportShellTab.explore.title)
            .searchable(text: $query, prompt: Text("Search practices, programs, and people"))
            .navigationDestination(for: SupportDestination.self) { destination in
                SupportDestinationView(destination: destination)
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
                                icon: "book.fill"
                            )
                        }
                    } else {
                        NavigationLink(value: SupportDestination.programs) {
                            SupportRowLabel(
                                title: String(localized: "Continue your program"),
                                subtitle: String(localized: "Day \(enrollment.currentDay)"),
                                icon: "book.fill"
                            )
                        }
                    }
                    pinMenu(for: activePin, name: enrollment.program?.title ?? String(localized: "your program"))
                }
            }
        }
    }

    private func destinationSection(_ section: SupportSection) -> some View {
        Section(section.title) {
            if section == .peopleAndCircles {
                activeCircleRows
            }
            ForEach(SupportDestination.exploreRows(in: section)) { destination in
                destinationRow(destination)
            }
            if section == .peopleAndCircles {
                Button {
                    showInviteBuddy = true
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Invite a buddy"),
                        subtitle: String(localized: "Send an invitation to someone you trust"),
                        icon: "person.badge.plus"
                    )
                }
                .buttonStyle(.plain)
            }
        }
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
                    icon: "person.3.fill"
                )
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let matches = Self.exploreSections.flatMap { SupportDestination.exploreRows(in: $0) }
            .filter { $0.matches(query) }
        if matches.isEmpty {
            Section {
                SupportUnavailableState(
                    title: String(localized: "Nothing found"),
                    message: String(localized: "Try another word, or clear the search to browse everything.")
                )
            }
        } else {
            Section(String(localized: "Results")) {
                ForEach(matches) { destination in
                    destinationRow(destination, showsSection: true)
                }
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func destinationRow(_ destination: SupportDestination, showsSection: Bool = false) -> some View {
        let label = SupportRowLabel(
            title: destination.title,
            subtitle: showsSection ? destination.section.title : destination.subtitle,
            icon: destination.icon
        )
        if destination.isPinnable {
            let pin = SupportPin(destination)
            HStack(spacing: SupportTheme.Spacing.xs) {
                NavigationLink(value: destination) { label }
                pinMenu(for: pin, name: destination.title)
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

    private func pinMenu(for pin: SupportPin, name: String) -> some View {
        Menu {
            if pins.isPinned(pin) {
                Button(String(localized: "Unpin from Today"), systemImage: "pin.slash") {
                    pins.unpin(pin)
                }
            } else if pins.isFull {
                Button(String(localized: "Replace a pin…"), systemImage: "pin") {
                    replaceCandidate = pin
                }
            } else {
                Button(String(localized: "Pin to Today"), systemImage: "pin") {
                    pins.pin(pin)
                }
            }
        } label: {
            Image(systemName: pins.isPinned(pin) ? "pin.fill" : "ellipsis.circle")
                .foregroundStyle(SupportTheme.accent)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Pin options for \(name)"))
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
                Section(String(localized: "Current pins")) {
                    ForEach(pins.pins) { pinned in
                        Button {
                            pins.replace(pinned, with: candidate)
                            dismiss()
                        } label: {
                            SupportRowLabel(
                                title: String(localized: "Replace \(pinned.record?.title ?? pinned.destination.title)"),
                                icon: pinned.destination.icon
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .supportCanvas()
            .navigationTitle(String(localized: "Replace a pin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
