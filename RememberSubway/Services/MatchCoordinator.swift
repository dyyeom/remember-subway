import Foundation
import UIKit

@MainActor
final class MatchCoordinator: ObservableObject {
    enum Role { case host, participant }
    enum ScreenState: Equatable {
        case home
        case browsing
        case joining
        case lobby
        case countdown(Int)
        case playing
        case roundResult
        case matchResult
        case cancelled(String)
        case failed(String)
    }

    @Published private(set) var screenState: ScreenState = .home
    @Published private(set) var roomCode = ""
    @Published private(set) var configuration: MultiplayerRoomConfiguration?
    @Published private(set) var lobbyPlayers: [NearbyPlayer] = []
    @Published private(set) var matchPlayers: [PlayerMatchState] = []
    @Published private(set) var questions: [MultiplayerQuestion] = []
    @Published private(set) var roundIndex = 0
    @Published private(set) var timeRemaining = MultiplayerRoomConfiguration.defaultRoundDuration
    @Published private(set) var hintVisible = false
    @Published private(set) var localAnswerLocked = false
    @Published private(set) var feedback = ""
    @Published private(set) var feedbackIsCorrect = false
    @Published private(set) var revealedAnswer = ""
    @Published private(set) var rematchRequested = false

    let localPlayerID: UUID
    let service: NearbyMatchService
    private(set) var role: Role?

    private let catalog: TransitCatalog
    private var nickname = ""
    private var matchID: UUID?
    private var sequence: UInt64 = 0
    private var hostConnectionID: UUID?
    private var connectionByPlayerID: [UUID: UUID] = [:]
    private var playerIDByConnection: [UUID: UUID] = [:]
    private var roundSubmissions: [UUID: MultiplayerRoundSubmission] = [:]
    private var roundWrongAttempts: [UUID: Int] = [:]
    private var roundHints = Set<UUID>()
    private var lastNormalizedAnswer: [UUID: String] = [:]
    private var lastSubmissionElapsed: [UUID: TimeInterval] = [:]
    private var roundStartedAt = Date()
    private var roundTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingRoom: DiscoveredRoom?
    private var lastReceivedSequence: [UUID: UInt64] = [:]
    private var lastMessageAt: [UUID: Date] = [:]
    private var participantReconnectTask: Task<Void, Never>?
    private var wasPlayingBeforeReconnect = false

    init(catalog: TransitCatalog, service: NearbyMatchService = NearbyMatchService(), localPlayerID: UUID = UUID()) {
        self.catalog = catalog
        self.service = service
        self.localPlayerID = localPlayerID
        service.messageHandler = { [weak self] connectionID, envelope in self?.receive(envelope, from: connectionID) }
        service.disconnectHandler = { [weak self] connectionID in self?.connectionLost(connectionID) }
        service.connectionReadyHandler = { [weak self] connectionID in self?.connectionReady(connectionID) }
        service.failureHandler = { [weak self] message in self?.networkFailed(message) }
    }

    var currentQuestion: MultiplayerQuestion? {
        questions.indices.contains(roundIndex) ? questions[roundIndex] : nil
    }

    var localPlayer: PlayerMatchState? { matchPlayers.first { $0.id == localPlayerID } }
    var currentMatchID: UUID? { matchID }
    var isHost: Bool { role == .host }
    var canStart: Bool { isHost && lobbyPlayers.filter { $0.connectionState == .connected }.count >= 2 }

    func host(configuration: MultiplayerRoomConfiguration, nickname: String) {
        resetSession()
        role = .host
        self.nickname = nickname
        self.configuration = configuration
        roomCode = String(format: "%04d", Int.random(in: 0...9_999))
        lobbyPlayers = [NearbyPlayer(id: localPlayerID, nickname: nickname, isHost: true, connectionState: .connected)]
        screenState = .lobby
        service.startHosting(
            roomName: AppLocalization.format("multiplayer.roomName.format", nickname),
            roomCode: roomCode,
            contentVersion: catalog.contentVersion
        )
        startHeartbeat()
    }

    func browse(nickname: String) {
        resetSession()
        role = .participant
        self.nickname = nickname
        screenState = .browsing
        service.startBrowsing()
    }

    func join(room: DiscoveredRoom, code: String) {
        pendingRoom = room
        roomCode = code
        screenState = .joining
        service.join(room: room, roomCode: code, contentVersion: catalog.contentVersion)
        startHeartbeat()
    }

    func startMatch() {
        guard isHost, canStart, let configuration else { return }
        let generated = MultiplayerQuestionFactory.questions(
            catalog: catalog,
            lineID: configuration.lineID,
            count: configuration.numberOfQuestions,
            seed: UInt64.random(in: .min ... .max)
        )
        guard generated.count == configuration.numberOfQuestions else {
            screenState = .failed(AppLocalization.text("multiplayer.error.insufficientStations"))
            return
        }
        questions = generated
        matchID = UUID()
        roundIndex = 0
        matchPlayers = lobbyPlayers.map { PlayerMatchState(id: $0.id, nickname: $0.nickname) }
        let start = MatchStart(
            configuration: configuration,
            questions: generated,
            players: matchPlayers,
            countdownStartedAt: .now
        )
        broadcast(.matchStart(start))
        beginCountdown()
    }

    func useHint() {
        guard screenState == .playing, !hintVisible, !localAnswerLocked else { return }
        hintVisible = true
        if isHost {
            roundHints.insert(localPlayerID)
        } else {
            sendToHost(.hintUsed(localPlayerID))
        }
    }

    func submit(_ answer: String) {
        guard screenState == .playing, !localAnswerLocked else { return }
        let elapsed = Date().timeIntervalSince(roundStartedAt)
        let submission = AnswerSubmission(
            playerID: localPlayerID,
            answer: answer,
            elapsed: elapsed,
            hintUsed: hintVisible
        )
        if isHost {
            handle(submission, from: nil)
        } else {
            sendToHost(.answerSubmission(submission))
        }
    }

    func remove(playerID: UUID) {
        guard isHost, playerID != localPlayerID else { return }
        if let connectionID = connectionByPlayerID.removeValue(forKey: playerID) {
            playerIDByConnection.removeValue(forKey: connectionID)
            send(.playerRemoved(playerID), to: connectionID)
            service.disconnect(connectionID: connectionID)
        }
        lobbyPlayers.removeAll { $0.id == playerID }
        broadcastLobby()
    }

    func requestRematch() {
        if isHost {
            startMatch()
        } else {
            rematchRequested = true
            sendToHost(.rematchRequest(localPlayerID))
        }
    }

    func applicationMovedToBackground() {
        let isActiveMatch: Bool
        switch screenState {
        case .playing, .countdown, .roundResult: isActiveMatch = true
        default: isActiveMatch = false
        }
        guard isActiveMatch else { return }
        if isHost {
            broadcast(.matchCancelled(AppLocalization.text("multiplayer.error.hostLeftApp")))
            cancelMatch(reason: AppLocalization.text("multiplayer.error.matchEndedAfterLeavingApp"))
        } else {
            localAnswerLocked = true
            feedback = AppLocalization.text("multiplayer.feedback.backgroundZero")
            feedbackIsCorrect = false
        }
    }

    func leave() {
        if isHost, screenState != .home {
            broadcast(.matchCancelled(AppLocalization.text("multiplayer.error.hostClosedRoom")))
        }
        resetSession()
        role = nil
        screenState = .home
    }

    private func connectionReady(_ connectionID: UUID) {
        lastMessageAt[connectionID] = .now
        guard role == .participant else { return }
        hostConnectionID = connectionID
        if wasPlayingBeforeReconnect {
            send(.reconnectRequest(playerID: localPlayerID, nickname: nickname), to: connectionID)
        } else {
            send(.joinRequest(JoinRequest(playerID: localPlayerID, nickname: nickname)), to: connectionID)
        }
    }

    private func receive(_ envelope: MultiplayerEnvelope, from connectionID: UUID) {
        if let previous = lastReceivedSequence[connectionID], envelope.sequenceNumber <= previous { return }
        lastReceivedSequence[connectionID] = envelope.sequenceNumber
        lastMessageAt[connectionID] = .now
        if case .matchStart = envelope.message {
            matchID = envelope.matchID
        } else if matchID == nil, let incomingMatchID = envelope.matchID {
            matchID = incomingMatchID
        }
        guard envelope.protocolVersion == MultiplayerEnvelope.currentProtocolVersion,
              envelope.contentVersion == catalog.contentVersion else {
            if isHost {
                send(.joinResponse(JoinResponse(
                    accepted: false,
                    reason: AppLocalization.text("multiplayer.error.versionMismatch"),
                    player: nil
                )), to: connectionID)
            } else {
                screenState = .failed(AppLocalization.text("multiplayer.error.updateRequired"))
            }
            return
        }

        switch envelope.message {
        case .joinRequest(let request): handleJoin(request, connectionID: connectionID)
        case .joinResponse(let response): handleJoinResponse(response)
        case .lobbySnapshot(let snapshot):
            configuration = snapshot.configuration
            lobbyPlayers = snapshot.players
            switch screenState {
            case .browsing, .joining, .lobby: screenState = .lobby
            default: break
            }
        case .playerRemoved(let id):
            if id == localPlayerID { cancelMatch(reason: AppLocalization.text("multiplayer.error.removedByHost")) }
        case .matchStart(let start): receiveMatchStart(start)
        case .roundStart(let round): receiveRoundStart(round)
        case .answerSubmission(let submission):
            guard isHost, playerIDByConnection[connectionID] == submission.playerID else { return }
            handle(submission, from: connectionID)
        case .hintUsed(let playerID):
            guard isHost, playerIDByConnection[connectionID] == playerID else { return }
            roundHints.insert(playerID)
        case .answerResult(let result):
            let targetName = currentQuestion.flatMap { catalog.stationByID[$0.targetStationID]?.name }
                ?? AppLocalization.text("station.nameFallback")
            feedback = result.isCorrect
                ? AppLocalization.format("game.correct.format", targetName)
                : AppLocalization.text("game.incorrectTryAgain")
            feedbackIsCorrect = result.isCorrect
            localAnswerLocked = result.isLocked
        case .roundResult(let result): receiveRoundResult(result)
        case .matchResult(let result): receiveMatchResult(result)
        case .matchCancelled(let reason): cancelMatch(reason: reason)
        case .reconnectRequest(let playerID, let reconnectingNickname):
            handleJoin(JoinRequest(playerID: playerID, nickname: reconnectingNickname), connectionID: connectionID)
        case .rematchRequest:
            rematchRequested = true
        case .heartbeat, .hello: break
        }
    }

    private func handleJoin(_ request: JoinRequest, connectionID: UUID) {
        guard isHost, let configuration else { return }
        guard screenState == .lobby || lobbyPlayers.contains(where: { $0.id == request.playerID }) else {
            send(.joinResponse(JoinResponse(accepted: false, reason: AppLocalization.text("multiplayer.error.alreadyStarted"), player: nil)), to: connectionID)
            return
        }
        guard lobbyPlayers.count < configuration.maximumPlayers || lobbyPlayers.contains(where: { $0.id == request.playerID }) else {
            send(.joinResponse(JoinResponse(accepted: false, reason: AppLocalization.text("multiplayer.error.roomFull"), player: nil)), to: connectionID)
            return
        }

        let nickname = uniqueNickname(request.nickname, excluding: request.playerID)
        let player = NearbyPlayer(id: request.playerID, nickname: nickname, isHost: false, connectionState: .connected)
        if let index = lobbyPlayers.firstIndex(where: { $0.id == request.playerID }) {
            lobbyPlayers[index] = player
            reconnectTasks.removeValue(forKey: request.playerID)?.cancel()
        } else {
            lobbyPlayers.append(player)
        }
        connectionByPlayerID[request.playerID] = connectionID
        playerIDByConnection[connectionID] = request.playerID
        send(.joinResponse(JoinResponse(accepted: true, reason: nil, player: player)), to: connectionID)
        broadcastLobby()
        sendCurrentMatchStateIfNeeded(to: connectionID)
    }

    private func handleJoinResponse(_ response: JoinResponse) {
        guard response.accepted else {
            screenState = .failed(response.reason ?? AppLocalization.text("multiplayer.error.joinFailed"))
            return
        }
        participantReconnectTask?.cancel()
        if !wasPlayingBeforeReconnect { screenState = .lobby }
        wasPlayingBeforeReconnect = false
    }

    private func uniqueNickname(_ requested: String, excluding playerID: UUID) -> String {
        let existing = Set(lobbyPlayers.filter { $0.id != playerID }.map(\.nickname))
        guard existing.contains(requested) else { return requested }
        var suffix = 2
        while existing.contains("\(requested) (\(suffix))") { suffix += 1 }
        return "\(requested) (\(suffix))"
    }

    private func beginCountdown() {
        roundTask?.cancel()
        roundTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for value in stride(from: 3, through: 1, by: -1) {
                self.screenState = .countdown(value)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self.startRound(index: 0)
        }
    }

    private func startRound(index: Int) {
        guard isHost, questions.indices.contains(index), let configuration else { return }
        roundIndex = index
        resetRoundState()
        roundStartedAt = .now
        let round = RoundStart(
            roundIndex: index,
            question: questions[index],
            startsAt: roundStartedAt,
            deadline: roundStartedAt.addingTimeInterval(configuration.roundDuration)
        )
        broadcast(.roundStart(round))
        startRoundClock(deadline: round.deadline)
    }

    private func receiveMatchStart(_ start: MatchStart) {
        configuration = start.configuration
        questions = start.questions
        matchPlayers = start.players
        roundIndex = 0
        rematchRequested = false
        roundTask?.cancel()
        roundTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for value in stride(from: 3, through: 1, by: -1) {
                self.screenState = .countdown(value)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
        }
    }

    private func receiveRoundStart(_ round: RoundStart) {
        roundIndex = round.roundIndex
        resetRoundState()
        roundStartedAt = .now
        let duration = max(0, round.deadline.timeIntervalSince(round.startsAt))
        startRoundClock(deadline: Date().addingTimeInterval(duration))
    }

    private func startRoundClock(deadline: Date) {
        roundTask?.cancel()
        screenState = .playing
        roundTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.timeRemaining = max(0, deadline.timeIntervalSinceNow)
                if self.timeRemaining <= 0 {
                    if self.isHost { self.finishRound() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func handle(_ submission: AnswerSubmission, from connectionID: UUID?) {
        guard isHost, screenState == .playing,
              submission.elapsed >= 0,
              submission.elapsed <= MultiplayerRoomConfiguration.defaultRoundDuration + 0.5,
              roundSubmissions[submission.playerID] == nil,
              let question = currentQuestion,
              let target = catalog.stationByID[question.targetStationID] else { return }

        if let previousElapsed = lastSubmissionElapsed[submission.playerID],
           submission.elapsed - previousElapsed < MultiplayerScoring.minimumSubmissionInterval { return }
        lastSubmissionElapsed[submission.playerID] = submission.elapsed

        let normalized = AnswerMatcher.normalize(submission.answer)
        guard !normalized.isEmpty else { return }
        if lastNormalizedAnswer[submission.playerID] == normalized {
            respond(AnswerResult(isCorrect: false, wrongAttempts: roundWrongAttempts[submission.playerID, default: 0], isLocked: false), playerID: submission.playerID, connectionID: connectionID)
            return
        }
        lastNormalizedAnswer[submission.playerID] = normalized

        if submission.hintUsed { roundHints.insert(submission.playerID) }
        if AnswerMatcher.matches(submission.answer, station: target) {
            let accepted = MultiplayerRoundSubmission(
                playerID: submission.playerID,
                elapsed: min(submission.elapsed, MultiplayerRoomConfiguration.defaultRoundDuration),
                hintUsed: roundHints.contains(submission.playerID),
                wrongAttempts: roundWrongAttempts[submission.playerID, default: 0]
            )
            roundSubmissions[submission.playerID] = accepted
            respond(AnswerResult(isCorrect: true, wrongAttempts: accepted.wrongAttempts, isLocked: true), playerID: submission.playerID, connectionID: connectionID)
            if roundSubmissions.count == matchPlayers.filter({ !$0.isForfeited }).count { finishRound() }
        } else {
            roundWrongAttempts[submission.playerID, default: 0] += 1
            respond(AnswerResult(isCorrect: false, wrongAttempts: roundWrongAttempts[submission.playerID, default: 0], isLocked: false), playerID: submission.playerID, connectionID: connectionID)
        }
    }

    private func respond(_ result: AnswerResult, playerID: UUID, connectionID: UUID?) {
        if playerID == localPlayerID {
            let targetName = currentQuestion.flatMap { catalog.stationByID[$0.targetStationID]?.name }
                ?? AppLocalization.text("station.nameFallback")
            feedback = result.isCorrect
                ? AppLocalization.format("game.correct.format", targetName)
                : AppLocalization.text("game.incorrectTryAgain")
            feedbackIsCorrect = result.isCorrect
            localAnswerLocked = result.isLocked
        } else if let connectionID {
            send(.answerResult(result), to: connectionID)
        }
    }

    private func finishRound() {
        guard isHost, screenState == .playing, let question = currentQuestion else { return }
        roundTask?.cancel()
        let scores = Dictionary(uniqueKeysWithValues: MultiplayerScoring.scores(for: Array(roundSubmissions.values)).map { ($0.playerID, $0) })
        for index in matchPlayers.indices {
            let id = matchPlayers[index].id
            matchPlayers[index].hintsUsed += roundHints.contains(id) ? 1 : 0
            matchPlayers[index].wrongAnswers += roundWrongAttempts[id, default: 0]
            if let score = scores[id] {
                matchPlayers[index].score += score.total
                matchPlayers[index].correctAnswers += 1
            }
        }
        matchPlayers = MultiplayerScoring.ranked(matchPlayers)
        revealedAnswer = catalog.stationByID[question.targetStationID]?.name ?? ""
        screenState = .roundResult
        broadcast(.roundResult(RoundResult(roundIndex: roundIndex, targetStationName: revealedAnswer, players: matchPlayers)))

        roundTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard let self, !Task.isCancelled else { return }
            if self.roundIndex + 1 >= self.questions.count {
                self.finishMatch()
            } else {
                self.startRound(index: self.roundIndex + 1)
            }
        }
    }

    private func receiveRoundResult(_ result: RoundResult) {
        roundTask?.cancel()
        roundIndex = result.roundIndex
        matchPlayers = result.players
        revealedAnswer = result.targetStationName
        localAnswerLocked = true
        screenState = .roundResult
    }

    private func finishMatch() {
        guard isHost else { return }
        matchPlayers = MultiplayerScoring.ranked(matchPlayers)
        screenState = .matchResult
        broadcast(.matchResult(MatchResult(players: matchPlayers)))
    }

    private func receiveMatchResult(_ result: MatchResult) {
        roundTask?.cancel()
        matchPlayers = result.players
        screenState = .matchResult
    }

    private func resetRoundState() {
        roundSubmissions = [:]
        roundWrongAttempts = [:]
        roundHints = []
        lastNormalizedAnswer = [:]
        lastSubmissionElapsed = [:]
        timeRemaining = configuration?.roundDuration ?? MultiplayerRoomConfiguration.defaultRoundDuration
        hintVisible = false
        localAnswerLocked = false
        feedback = ""
        feedbackIsCorrect = false
        revealedAnswer = ""
    }

    private func connectionLost(_ connectionID: UUID) {
        if role == .participant, connectionID == hostConnectionID {
            beginParticipantReconnect()
            return
        }
        guard isHost, let playerID = playerIDByConnection.removeValue(forKey: connectionID) else { return }
        connectionByPlayerID.removeValue(forKey: playerID)
        if let index = lobbyPlayers.firstIndex(where: { $0.id == playerID }) {
            lobbyPlayers[index].connectionState = .reconnecting
        }
        broadcastLobby()
        reconnectTasks[playerID]?.cancel()
        reconnectTasks[playerID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            if let index = self.lobbyPlayers.firstIndex(where: { $0.id == playerID }) {
                self.lobbyPlayers[index].connectionState = .forfeited
            }
            if let index = self.matchPlayers.firstIndex(where: { $0.id == playerID }) {
                self.matchPlayers[index].isForfeited = true
            }
            self.broadcastLobby()
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.broadcast(.heartbeat(.now))
                let expired = self.lastMessageAt.filter { Date().timeIntervalSince($0.value) > 6 }.map(\.key)
                for connectionID in expired { self.service.disconnect(connectionID: connectionID) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func broadcastLobby() {
        guard let configuration else { return }
        broadcast(.lobbySnapshot(LobbySnapshot(roomCode: nil, configuration: configuration, players: lobbyPlayers)))
    }

    private func sendToHost(_ message: MultiplayerMessage) {
        guard let hostConnectionID else { return }
        send(message, to: hostConnectionID)
    }

    private func broadcast(_ message: MultiplayerMessage) { send(message, to: nil) }

    private func send(_ message: MultiplayerMessage, to connectionID: UUID?) {
        sequence &+= 1
        service.send(MultiplayerEnvelope(
            contentVersion: catalog.contentVersion,
            matchID: matchID,
            sequenceNumber: sequence,
            message: message
        ), to: connectionID)
    }

    private func cancelMatch(reason: String) {
        roundTask?.cancel()
        screenState = .cancelled(reason)
    }

    private func networkFailed(_ underlyingMessage: String) {
        let message: String
        if role == .participant, screenState == .joining {
            message = AppLocalization.format("multiplayer.error.joinNetwork.format", underlyingMessage)
        } else {
            message = AppLocalization.format("multiplayer.error.localNetwork.format", underlyingMessage)
        }
        screenState = .failed(message)
    }

    private func resetSession() {
        roundTask?.cancel()
        heartbeatTask?.cancel()
        participantReconnectTask?.cancel()
        for task in reconnectTasks.values { task.cancel() }
        reconnectTasks = [:]
        service.stop()
        roomCode = ""
        configuration = nil
        lobbyPlayers = []
        matchPlayers = []
        questions = []
        roundIndex = 0
        matchID = nil
        sequence = 0
        hostConnectionID = nil
        connectionByPlayerID = [:]
        playerIDByConnection = [:]
        lastReceivedSequence = [:]
        lastMessageAt = [:]
        wasPlayingBeforeReconnect = false
        pendingRoom = nil
        resetRoundState()
    }

    private func beginParticipantReconnect() {
        guard let pendingRoom else {
            screenState = .failed(AppLocalization.text("multiplayer.error.hostDisconnected"))
            return
        }
        switch screenState {
        case .playing, .countdown, .roundResult: wasPlayingBeforeReconnect = true
        default: wasPlayingBeforeReconnect = false
        }
        screenState = .joining
        participantReconnectTask?.cancel()
        participantReconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [1, 3, 5] {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                self.service.join(room: pendingRoom, roomCode: self.roomCode, contentVersion: self.catalog.contentVersion)
                try? await Task.sleep(for: .seconds(2))
                if self.service.state == .connected { return }
            }
            self.screenState = .failed(AppLocalization.text("multiplayer.error.reconnectTimedOut"))
        }
    }

    private func sendCurrentMatchStateIfNeeded(to connectionID: UUID) {
        guard let configuration, let matchID else { return }
        switch screenState {
        case .playing, .roundResult, .countdown:
            self.matchID = matchID
            send(.matchStart(MatchStart(
                configuration: configuration,
                questions: questions,
                players: matchPlayers,
                countdownStartedAt: .now
            )), to: connectionID)
            if let question = currentQuestion {
                let deadline = roundStartedAt.addingTimeInterval(configuration.roundDuration)
                send(.roundStart(RoundStart(
                    roundIndex: roundIndex,
                    question: question,
                    startsAt: roundStartedAt,
                    deadline: max(deadline, Date().addingTimeInterval(0.5))
                )), to: connectionID)
            }
            if screenState == .roundResult {
                send(.roundResult(RoundResult(roundIndex: roundIndex, targetStationName: revealedAnswer, players: matchPlayers)), to: connectionID)
            }
        case .matchResult:
            send(.matchResult(MatchResult(players: matchPlayers)), to: connectionID)
        default: break
        }
    }
}
