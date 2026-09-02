import SwiftData
import SwiftUI
import UIKit

struct MultiplayerContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settings: [AppSettingsRecord]
    @StateObject private var coordinator: MatchCoordinator
    @Binding var showSettings: Bool
    @Binding var showStats: Bool
    @Binding var showTutorial: Bool
    @State private var nickname = ""
    @State private var selectedRegionID: String?
    @State private var selectedLineID: String?
    @State private var selectedRoom: DiscoveredRoom?
    @State private var roomCodeEntry = ""
    @State private var recordedMatchIDs = Set<UUID>()
    @FocusState private var nicknameFocused: Bool
    let catalog: TransitCatalog

    init(
        catalog: TransitCatalog,
        showSettings: Binding<Bool>,
        showStats: Binding<Bool>,
        showTutorial: Binding<Bool>
    ) {
        self.catalog = catalog
        _coordinator = StateObject(wrappedValue: MatchCoordinator(catalog: catalog))
        _showSettings = showSettings
        _showStats = showStats
        _showTutorial = showTutorial
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    AppToolbar(
                        showStats: $showStats,
                        showSettings: $showSettings,
                        showTutorial: $showTutorial
                    )
                }
        }
        .task { initialize() }
        .onChange(of: selectedRegionID) { _, _ in selectedLineID = selectedRegion.flatMap { catalog.lines(in: $0).first?.id } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { coordinator.applicationMovedToBackground() }
        }
        .onChange(of: coordinator.screenState) { _, state in
            guard state == .matchResult else { return }
            recordResultIfNeeded()
        }
        .sheet(item: $selectedRoom) { room in
            JoinCodeView(room: room, code: $roomCodeEntry) {
                selectedRoom = nil
                coordinator.join(room: room, code: roomCodeEntry)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch coordinator.screenState {
        case .home:
            home
        case .browsing:
            RoomBrowserView(
                service: coordinator.service,
                select: { selectedRoom = $0 },
                exit: { coordinator.leave() }
            )
        case .joining:
            progress(
                title: AppLocalization.text("multiplayer.joining.title"),
                message: AppLocalization.text("multiplayer.joining.message")
            )
        case .lobby:
            lobby
        case .countdown(let value):
            matchPlay(countdown: value)
        case .playing:
            matchPlay(countdown: nil)
        case .roundResult:
            matchPlay(countdown: nil)
        case .matchResult:
            result
        case .cancelled(let message), .failed(let message):
            failure(message)
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.text("multiplayer.home.title"))
                        .font(.largeTitle.bold())
                    Text(AppLocalization.text("multiplayer.home.description"))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    selectionRow(AppLocalization.text("multiplayer.nickname.label"), systemImage: "person.fill") {
                        TextField(AppLocalization.text("multiplayer.nickname.placeholder"), text: $nickname)
                            .multilineTextAlignment(.trailing)
                            .focused($nicknameFocused)
                            .submitLabel(.done)
                            .onSubmit { nicknameFocused = false }
                            .onChange(of: nickname) { _, value in saveNickname(value) }
                    }
                    Divider().padding(.leading, 52)
                    selectionRow(AppLocalization.text("common.region"), systemImage: "map") {
                        Picker(AppLocalization.text("common.region"), selection: $selectedRegionID) {
                            Text(AppLocalization.text("common.selectRegion")).tag(Optional<String>.none)
                            ForEach(regions) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                    Divider().padding(.leading, 52)
                    selectionRow(AppLocalization.text("common.line"), systemImage: "tram.fill") {
                        Picker(AppLocalization.text("common.line"), selection: $selectedLineID) {
                            Text(AppLocalization.text("common.selectLine")).tag(Optional<String>.none)
                            ForEach(lines) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                }
                .padding(.horizontal, 16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                GroupBox {
                    LabeledContent(AppLocalization.text("multiplayer.questions"), value: AppLocalization.text("multiplayer.tenQuestions"))
                    LabeledContent(AppLocalization.text("multiplayer.timeLimit"), value: AppLocalization.text("multiplayer.tenSecondsEach"))
                    LabeledContent(AppLocalization.text("multiplayer.players"), value: AppLocalization.text("multiplayer.twoToEightPlayers"))
                } label: {
                    Label(AppLocalization.text("multiplayer.simultaneousMatch"), systemImage: "timer")
                }

                VStack(spacing: 12) {
                    Button {
                        guard let regionID = selectedRegionID, let lineID = selectedLineID else { return }
                        coordinator.host(
                            configuration: MultiplayerRoomConfiguration(regionID: regionID, lineID: lineID),
                            nickname: validNickname
                        )
                    } label: {
                        Label(AppLocalization.text("multiplayer.createRoom"), systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(selectedLine?.color ?? .accentColor)
                    .disabled(!canEnterMultiplayer || selectedLine == nil)

                    Button {
                        coordinator.browse(nickname: validNickname)
                    } label: {
                        Label(AppLocalization.text("multiplayer.findNearbyRoom"), systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canEnterMultiplayer)
                }
                .controlSize(.large)
            }
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.vertical, AppLayout.pageVertical)
        }
        .scrollDismissesKeyboard(.immediately)
        .onScrollPhaseChange { _, phase in
            if phase.isScrolling { nicknameFocused = false }
        }
    }

    private var lobby: some View {
        ScrollView {
            VStack(spacing: 24) {
                if coordinator.isHost {
                    VStack(spacing: 6) {
                        Text(AppLocalization.text("multiplayer.joinCode")).font(.headline).foregroundStyle(.secondary)
                        Text(coordinator.roomCode)
                            .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                            .textSelection(.enabled)
                        Text(AppLocalization.text("multiplayer.shareCodeMessage"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                }

                if let configuration = coordinator.configuration,
                   let line = catalog.lineByID[configuration.lineID] {
                    HStack {
                        LineIdentityLabel(line: line)
                        Spacer()
                        Text(AppLocalization.text("multiplayer.matchSummary")).foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(coordinator.lobbyPlayers) { player in
                        HStack(spacing: 12) {
                            Image(systemName: player.isHost ? "crown.fill" : "person.fill")
                                .foregroundStyle(player.isHost ? .yellow : .secondary)
                                .frame(width: 28)
                            Text(player.nickname).font(.headline)
                            Spacer()
                            Text(connectionLabel(player.connectionState)).font(.caption).foregroundStyle(.secondary)
                            if coordinator.isHost && !player.isHost {
                                Button(AppLocalization.text("multiplayer.removePlayer"), systemImage: "xmark.circle") { coordinator.remove(playerID: player.id) }
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(minHeight: 56)
                        if player.id != coordinator.lobbyPlayers.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22))

                if coordinator.isHost {
                    Button {
                        coordinator.startMatch()
                    } label: {
                        Label(AppLocalization.text("common.startGame"), systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!coordinator.canStart)
                } else {
                    Label(AppLocalization.text("multiplayer.waitingForHost"), systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }

                Button(AppLocalization.text("multiplayer.leaveRoom"), role: .destructive) { coordinator.leave() }
            }
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.vertical, AppLayout.pageVertical)
        }
    }

    private func matchPlay(countdown: Int?) -> some View {
        MultiplayerPlayView(coordinator: coordinator, catalog: catalog, countdown: countdown)
    }

    private var result: some View {
        MultiplayerResultView(coordinator: coordinator, catalog: catalog)
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label(AppLocalization.text("multiplayer.failure.title"), systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 12) {
                Button(AppLocalization.text("common.openSettings")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                Button(AppLocalization.text("multiplayer.backHome")) { coordinator.leave() }
            }
        }
    }

    private func progress(title: String, message: String) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(title).font(.title2.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(AppLocalization.text("common.cancel"), role: .cancel) { coordinator.leave() }
        }
        .padding()
    }

    private func selectionRow<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 24)
            Text(title).font(.body.weight(.medium))
            Spacer()
            content()
        }
        .frame(minHeight: 58)
    }

    private var regions: [Region] { catalog.regions.sorted { $0.sortOrder < $1.sortOrder } }
    private var selectedRegion: Region? { regions.first { $0.id == selectedRegionID } }
    private var lines: [Line] { selectedRegion.map { catalog.lines(in: $0) } ?? [] }
    private var selectedLine: Line? { catalog.lineByID[selectedLineID ?? ""] }
    private var validNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canEnterMultiplayer: Bool { (1...10).contains(validNickname.count) }

    private var navigationTitle: String {
        switch coordinator.screenState {
        case .home: AppLocalization.text("tab.multiplayer")
        case .browsing: AppLocalization.text("multiplayer.nearbyRooms")
        case .lobby: AppLocalization.text("multiplayer.lobby")
        case .matchResult: AppLocalization.text("multiplayer.result.title")
        default: AppLocalization.text("multiplayer.nearbyMatch")
        }
    }

    private func initialize() {
        nickname = settings.first?.multiplayerNickname ?? ""
        selectedRegionID = selectedRegionID ?? regions.first?.id
        selectedLineID = selectedLineID ?? lines.first?.id
    }

    private func saveNickname(_ value: String) {
        let trimmed = String(value.prefix(10))
        if nickname != trimmed { nickname = trimmed }
        let record = settings.first ?? AppSettingsRecord()
        if record.modelContext == nil { modelContext.insert(record) }
        record.multiplayerNickname = trimmed
        try? modelContext.save()
    }

    private func recordResultIfNeeded() {
        guard let matchID = coordinator.currentMatchID,
              !recordedMatchIDs.contains(matchID),
              let configuration = coordinator.configuration,
              let player = coordinator.localPlayer else { return }
        recordedMatchIDs.insert(matchID)
        try? ProgressStore.recordMultiplayerMatch(
            regionID: configuration.regionID,
            lineID: configuration.lineID,
            player: player,
            playerCount: coordinator.matchPlayers.count,
            context: modelContext
        )
    }

    private func connectionLabel(_ state: NearbyPlayer.ConnectionState) -> String {
        switch state {
        case .connected: AppLocalization.text("connection.connected")
        case .reconnecting: AppLocalization.text("connection.reconnecting")
        case .forfeited: AppLocalization.text("connection.forfeited")
        }
    }
}

private struct RoomBrowserView: View {
    @ObservedObject var service: NearbyMatchService
    let select: (DiscoveredRoom) -> Void
    let exit: () -> Void

    var body: some View {
        Group {
            if service.discoveredRooms.isEmpty {
                ContentUnavailableView {
                    Label(AppLocalization.text("multiplayer.searching.title"), systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text(AppLocalization.text("multiplayer.searching.message"))
                }
            } else {
                List(service.discoveredRooms) { room in
                    Button { select(room) } label: {
                        HStack {
                            Image(systemName: "person.3.fill").foregroundStyle(.tint)
                            Text(room.name).font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(AppLocalization.text("multiplayer.backHome"), systemImage: "chevron.backward", action: exit)
                .buttonStyle(.glass)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.vertical, 12)
        }
    }
}

private struct JoinCodeView: View {
    @Environment(\.dismiss) private var dismiss
    let room: DiscoveredRoom
    @Binding var code: String
    let join: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "lock.fill").font(.system(size: 46)).foregroundStyle(.tint)
                Text(room.name).font(.title2.bold())
                TextField(AppLocalization.text("multiplayer.joinCode.placeholder"), text: $code)
                    .font(.largeTitle.bold().monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
                    .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(4)) }
                Button(AppLocalization.text("multiplayer.join"), action: join)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(code.count != 4)
            }
            .padding(24)
            .navigationTitle(AppLocalization.text("multiplayer.joinCode"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.text("common.cancel")) { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

private struct MultiplayerPlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var coordinator: MatchCoordinator
    let catalog: TransitCatalog
    let countdown: Int?
    @State private var answer = ""
    @State private var showRanking = false
    @State private var keyboardPresented = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            if let question = coordinator.currentQuestion,
               let previous = catalog.stationByID[question.previousStationID],
               let next = catalog.stationByID[question.nextStationID],
               let line = catalog.lineByID[question.lineID] {
                VStack(spacing: 0) {
                    HStack {
                        LineIdentityLabel(line: line)
                        Spacer()
                        Text("\(coordinator.roundIndex + 1)/\(coordinator.questions.count)").font(.headline.monospacedDigit())
                        Spacer()
                        Button(AppLocalization.text("common.ranking"), systemImage: "list.number") { showRanking = true }
                            .labelStyle(.iconOnly)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, keyboardPresented ? 4 : 12)

                    HStack {
                        Label(AppLocalization.format("time.seconds.format", Int(ceil(coordinator.timeRemaining))), systemImage: "timer")
                        Spacer()
                        Text(AppLocalization.format(
                            "score.pointsAndRank.format",
                            coordinator.localPlayer?.score ?? 0,
                            coordinator.localPlayer?.rank ?? 1
                        ))
                            .font(.headline.monospacedDigit())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, keyboardPresented ? 6 : 18)

                    ProgressView(value: coordinator.timeRemaining, total: 10)
                        .tint(line.color)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    NeighborStationSignView(previous: previous, next: next, line: line, compact: keyboardPresented)
                        .padding(.horizontal, 20)
                        .padding(.top, keyboardPresented ? 8 : 28)

                    VStack(spacing: keyboardPresented ? 10 : 18) {
                        Text(AppLocalization.text("game.stationQuestion")).font(.largeTitle.bold())
                        if coordinator.hintVisible {
                            Text(AnswerMatcher.initialConsonants(of: catalog.stationByID[question.targetStationID]?.name ?? ""))
                                .font(.title2.monospaced().bold())
                                .foregroundStyle(line.color)
                        }
                        TextField(AppLocalization.text("game.answer.placeholder"), text: $answer)
                            .font(.title3)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 60)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22))
                            .focused($focused)
                            .disabled(coordinator.localAnswerLocked || coordinator.screenState != .playing)
                            .submitLabel(.done)
                            .onSubmit(submit)
                        Text(feedbackText)
                            .font(coordinator.feedbackIsCorrect ? .largeTitle.bold() : .callout)
                            .foregroundStyle(feedbackColor(line))
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 38)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, keyboardPresented ? 10 : 30)
                    .padding(.bottom, keyboardPresented ? 8 : 24)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .scrollDismissesKeyboard(.interactively)
        .overlay { countdownOverlay }
        .sheet(isPresented: $showRanking) { RankingSheet(players: coordinator.matchPlayers) }
        .task { focused = coordinator.screenState == .playing }
        .onChange(of: coordinator.roundIndex) { _, _ in answer = ""; restoreFocus() }
        .onChange(of: coordinator.screenState) { _, state in if state == .playing { restoreFocus() } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardPresented = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardPresented = false }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: keyboardPresented)
    }

    private var feedbackText: String {
        coordinator.screenState == .roundResult
            ? AppLocalization.format("game.incorrectReveal.format", coordinator.revealedAnswer)
            : coordinator.feedback
    }

    private func feedbackColor(_ line: Line) -> Color {
        coordinator.feedbackIsCorrect || coordinator.screenState == .roundResult ? line.color : .secondary
    }

    @ViewBuilder private var actionBar: some View {
        if let line = coordinator.currentQuestion.flatMap({ catalog.lineByID[$0.lineID] }) {
            GameGlassActionBar(
                color: line.color,
                hintTitle: AppLocalization.text("game.initialHint"),
                hintDisabled: coordinator.hintVisible || coordinator.localAnswerLocked || coordinator.screenState != .playing,
                confirmDisabled: AnswerMatcher.normalize(answer).isEmpty || coordinator.localAnswerLocked || coordinator.screenState != .playing,
                onHint: { coordinator.useHint(); restoreFocus() },
                onConfirm: submit
            )
        }
    }

    @ViewBuilder private var countdownOverlay: some View {
        if let countdown {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                Text("\(countdown)")
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .padding(44)
                    .background(.regularMaterial, in: Circle())
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func submit() {
        coordinator.submit(answer)
        answer = ""
        restoreFocus()
    }

    private func restoreFocus() {
        guard !coordinator.localAnswerLocked else { return }
        Task { @MainActor in await Task.yield(); focused = true }
    }
}

private struct RankingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let players: [PlayerMatchState]

    var body: some View {
        NavigationStack {
            List(MultiplayerScoring.ranked(players)) { player in
                HStack {
                    Text("\(player.rank)").font(.title2.bold().monospacedDigit()).frame(width: 36)
                    Text(player.nickname).font(.headline)
                    Spacer()
                    Text(AppLocalization.format("score.points.format", player.score)).monospacedDigit()
                }
            }
            .navigationTitle(AppLocalization.text("multiplayer.currentRanking"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.text("common.done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MultiplayerResultView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var coordinator: MatchCoordinator
    let catalog: TransitCatalog

    var body: some View {
        ZStack {
            if coordinator.localPlayer?.rank == 1 {
                CelebrationFireworksView(color: resultLine?.color ?? .accentColor, reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: coordinator.localPlayer?.rank == 1 ? "trophy.fill" : "flag.checkered")
                        .font(.system(size: 64))
                        .foregroundStyle(coordinator.localPlayer?.rank == 1 ? Color.yellow : Color.accentColor)
                    Text(coordinator.localPlayer?.rank == 1
                        ? AppLocalization.text("multiplayer.result.winner")
                        : AppLocalization.text("multiplayer.result.finished"))
                        .font(.largeTitle.bold())
                    if let player = coordinator.localPlayer {
                        Text(AppLocalization.format("stats.rankAndScore.format", player.rank, player.score)).font(.title2.bold().monospacedDigit())
                        GroupBox {
                            LabeledContent(AppLocalization.text("game.correctAnswers"), value: AppLocalization.format("count.items.format", player.correctAnswers))
                            LabeledContent(AppLocalization.text("game.hints"), value: AppLocalization.format("count.times.format", player.hintsUsed))
                            LabeledContent(AppLocalization.text("game.wrongAnswers"), value: AppLocalization.format("count.times.format", player.wrongAnswers))
                        }
                    }
                    VStack(spacing: 12) {
                        ForEach(MultiplayerScoring.ranked(coordinator.matchPlayers)) { player in
                            HStack {
                                Text(AppLocalization.format("rank.position.format", player.rank)).font(.headline).frame(width: 48, alignment: .leading)
                                Text(player.nickname)
                                Spacer()
                                Text(AppLocalization.format("score.points.format", player.score)).monospacedDigit()
                            }
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))

                    Button {
                        coordinator.requestRematch()
                    } label: {
                        Label(coordinator.isHost
                            ? AppLocalization.text("multiplayer.rematch.sameRoom")
                            : AppLocalization.text("multiplayer.rematch.request"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(coordinator.rematchRequested && !coordinator.isHost)

                    Button(AppLocalization.text("common.leave")) { coordinator.leave() }.buttonStyle(.glass)
                }
                .padding(24)
            }
        }
    }

    private var resultLine: Line? { coordinator.configuration.flatMap { catalog.lineByID[$0.lineID] } }
}
