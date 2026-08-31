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
    @State private var nickname = ""
    @State private var selectedRegionID: String?
    @State private var selectedLineID: String?
    @State private var selectedRoom: DiscoveredRoom?
    @State private var roomCodeEntry = ""
    @State private var recordedMatchIDs = Set<UUID>()
    let catalog: TransitCatalog

    init(catalog: TransitCatalog, showSettings: Binding<Bool>, showStats: Binding<Bool>) {
        self.catalog = catalog
        _coordinator = StateObject(wrappedValue: MatchCoordinator(catalog: catalog))
        _showSettings = showSettings
        _showStats = showStats
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { AppToolbar(showStats: $showStats, showSettings: $showSettings) }
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
            RoomBrowserView(service: coordinator.service) { selectedRoom = $0 }
        case .joining:
            progress(title: "방에 연결하는 중이에요", message: "참가 코드와 보안 연결을 확인하고 있어요.")
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
                    Text("친구들과\n같이 맞혀 보세요")
                        .font(.largeTitle.bold())
                    Text("근처의 iPhone 2~8대가 같은 역 문제를 동시에 풉니다.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    selectionRow("내 이름", systemImage: "person.fill") {
                        TextField("닉네임", text: $nickname)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: nickname) { _, value in saveNickname(value) }
                    }
                    Divider().padding(.leading, 52)
                    selectionRow("지역", systemImage: "map") {
                        Picker("지역", selection: $selectedRegionID) {
                            Text("지역 선택").tag(Optional<String>.none)
                            ForEach(regions) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                    Divider().padding(.leading, 52)
                    selectionRow("노선", systemImage: "tram.fill") {
                        Picker("노선", selection: $selectedLineID) {
                            Text("노선 선택").tag(Optional<String>.none)
                            ForEach(lines) { Text($0.name).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                }
                .padding(.horizontal, 16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                GroupBox {
                    LabeledContent("문제", value: "10개")
                    LabeledContent("제한 시간", value: "문제당 10초")
                    LabeledContent("참가 인원", value: "2~8명")
                } label: {
                    Label("동시 점수전", systemImage: "timer")
                }

                VStack(spacing: 12) {
                    Button {
                        guard let regionID = selectedRegionID, let lineID = selectedLineID else { return }
                        coordinator.host(
                            configuration: MultiplayerRoomConfiguration(regionID: regionID, lineID: lineID),
                            nickname: validNickname
                        )
                    } label: {
                        Label("방 만들기", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(selectedLine?.color ?? .accentColor)
                    .disabled(!canEnterMultiplayer || selectedLine == nil)

                    Button {
                        coordinator.browse(nickname: validNickname)
                    } label: {
                        Label("근처 방 찾기", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canEnterMultiplayer)
                }
                .controlSize(.large)
            }
            .padding(20)
        }
    }

    private var lobby: some View {
        ScrollView {
            VStack(spacing: 24) {
                if coordinator.isHost {
                    VStack(spacing: 6) {
                        Text("참가 코드").font(.headline).foregroundStyle(.secondary)
                        Text(coordinator.roomCode)
                            .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                            .textSelection(.enabled)
                        Text("이 코드를 함께 플레이할 사람에게 알려주세요.")
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
                        Text("10문제 · 10초").foregroundStyle(.secondary)
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
                                Button("내보내기", systemImage: "xmark.circle") { coordinator.remove(playerID: player.id) }
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
                        Label("게임 시작", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!coordinator.canStart)
                } else {
                    Label("방장이 시작하기를 기다리고 있어요", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }

                Button("방 나가기", role: .destructive) { coordinator.leave() }
            }
            .padding(20)
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
            Label("대전을 계속할 수 없어요", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 12) {
                Button("설정 열기") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                Button("멀티플레이 홈으로") { coordinator.leave() }
            }
        }
    }

    private func progress(title: String, message: String) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(title).font(.title2.bold())
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("취소", role: .cancel) { coordinator.leave() }
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
        case .home: "멀티플레이"
        case .browsing: "근처 방"
        case .lobby: "대기실"
        case .matchResult: "경기 결과"
        default: "근처 대전"
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
        case .connected: "연결됨"
        case .reconnecting: "재연결 중"
        case .forfeited: "기권"
        }
    }
}

private struct RoomBrowserView: View {
    @ObservedObject var service: NearbyMatchService
    let select: (DiscoveredRoom) -> Void

    var body: some View {
        Group {
            if service.discoveredRooms.isEmpty {
                ContentUnavailableView {
                    Label("근처 방을 찾고 있어요", systemImage: "dot.radiowaves.left.and.right")
                } description: {
                    Text("방을 만든 사람과 가까이 있는지 확인해 주세요.")
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
                TextField("4자리 참가 코드", text: $code)
                    .font(.largeTitle.bold().monospacedDigit())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
                    .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(4)) }
                Button("참가하기", action: join)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(code.count != 4)
            }
            .padding(24)
            .navigationTitle("참가 코드")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
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
                        Button("순위", systemImage: "list.number") { showRanking = true }
                            .labelStyle(.iconOnly)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, keyboardPresented ? 4 : 12)

                    HStack {
                        Label("\(Int(ceil(coordinator.timeRemaining)))초", systemImage: "timer")
                        Spacer()
                        Text("\(coordinator.localPlayer?.score ?? 0)점 · \(coordinator.localPlayer?.rank ?? 1)위")
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
                        Text("이 역의 이름은?").font(.largeTitle.bold())
                        if coordinator.hintVisible {
                            Text(AnswerMatcher.initialConsonants(of: catalog.stationByID[question.targetStationID]?.name ?? ""))
                                .font(.title2.monospaced().bold())
                                .foregroundStyle(line.color)
                        }
                        TextField("역 이름 입력", text: $answer)
                            .font(.title3)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 60)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22))
                            .focused($focused)
                            .disabled(coordinator.localAnswerLocked || coordinator.screenState != .playing)
                            .submitLabel(.done)
                            .onSubmit(submit)
                        Text(feedbackText)
                            .font(coordinator.feedback.contains("정답이에요") ? .largeTitle.bold() : .callout)
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
        coordinator.screenState == .roundResult ? "정답은 \(coordinator.revealedAnswer)이에요." : coordinator.feedback
    }

    private func feedbackColor(_ line: Line) -> Color {
        coordinator.feedback.contains("정답이에요") || coordinator.screenState == .roundResult ? line.color : .secondary
    }

    @ViewBuilder private var actionBar: some View {
        if let line = coordinator.currentQuestion.flatMap({ catalog.lineByID[$0.lineID] }) {
            GameGlassActionBar(
                color: line.color,
                hintTitle: "초성 힌트",
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
                    Text("\(player.score)점").monospacedDigit()
                }
            }
            .navigationTitle("현재 순위")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
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
                    Text(coordinator.localPlayer?.rank == 1 ? "우승했어요!" : "경기가 끝났어요")
                        .font(.largeTitle.bold())
                    if let player = coordinator.localPlayer {
                        Text("\(player.rank)위 · \(player.score)점").font(.title2.bold().monospacedDigit())
                        GroupBox {
                            LabeledContent("정답", value: "\(player.correctAnswers)개")
                            LabeledContent("힌트", value: "\(player.hintsUsed)회")
                            LabeledContent("오답", value: "\(player.wrongAnswers)회")
                        }
                    }
                    VStack(spacing: 12) {
                        ForEach(MultiplayerScoring.ranked(coordinator.matchPlayers)) { player in
                            HStack {
                                Text("\(player.rank)위").font(.headline).frame(width: 48, alignment: .leading)
                                Text(player.nickname)
                                Spacer()
                                Text("\(player.score)점").monospacedDigit()
                            }
                        }
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))

                    Button {
                        coordinator.requestRematch()
                    } label: {
                        Label(coordinator.isHost ? "같은 방에서 다시 하기" : "다시 하기 요청", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(coordinator.rematchRequested && !coordinator.isHost)

                    Button("나가기") { coordinator.leave() }.buttonStyle(.glass)
                }
                .padding(24)
            }
        }
    }

    private var resultLine: Line? { coordinator.configuration.flatMap { catalog.lineByID[$0.lineID] } }
}
