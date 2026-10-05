import Foundation
import Testing
@testable import RememberSubway

struct MultiplayerGameTests {
    @Test func scoreIncludesHintPenaltyWrongPenaltyAndTopThreeBonus() {
        let ids = (0..<4).map { _ in UUID() }
        let submissions = [
            MultiplayerRoundSubmission(playerID: ids[0], elapsed: 1, hintUsed: false, wrongAttempts: 0),
            MultiplayerRoundSubmission(playerID: ids[1], elapsed: 2, hintUsed: true, wrongAttempts: 1),
            MultiplayerRoundSubmission(playerID: ids[2], elapsed: 3, hintUsed: false, wrongAttempts: 2),
            MultiplayerRoundSubmission(playerID: ids[3], elapsed: 4, hintUsed: false, wrongAttempts: 0)
        ]

        let scores = MultiplayerScoring.scores(for: submissions)
        #expect(scores.map(\.total) == [130, 50, 70, 100])
    }

    @Test func zeroBaseScoreDoesNotReceiveSpeedBonus() {
        let score = MultiplayerScoring.scores(for: [
            MultiplayerRoundSubmission(playerID: UUID(), elapsed: 1, hintUsed: true, wrongAttempts: 3)
        ])
        #expect(score.first?.total == 0)
    }

    @Test func zeroBaseScoreDoesNotConsumeSpeedBonusPosition() {
        let zero = UUID()
        let eligible = UUID()
        let scores = MultiplayerScoring.scores(for: [
            MultiplayerRoundSubmission(playerID: zero, elapsed: 1, hintUsed: true, wrongAttempts: 3),
            MultiplayerRoundSubmission(playerID: eligible, elapsed: 2, hintUsed: false, wrongAttempts: 0)
        ])

        #expect(scores.first { $0.playerID == zero }?.total == 0)
        #expect(scores.first { $0.playerID == eligible }?.total == 130)
    }

    @Test func tenPerfectFirstPlaceAnswersReachMaximumScore() {
        let playerID = UUID()
        let total = (0..<10).reduce(into: 0) { score, _ in
            score += MultiplayerScoring.scores(for: [
                MultiplayerRoundSubmission(playerID: playerID, elapsed: 1, hintUsed: false, wrongAttempts: 0)
            ]).first?.total ?? 0
        }
        #expect(total == 1_300)
    }

    @Test func protocolEnvelopeRoundTripsRoundStart() throws {
        let matchID = UUID()
        let question = MultiplayerQuestion(
            id: "route:2", lineID: "line", routePatternID: "route",
            previousStationID: "a", targetStationID: "b", nextStationID: "c"
        )
        let envelope = MultiplayerEnvelope(
            contentVersion: "2026.09", matchID: matchID, sequenceNumber: 42,
            message: .roundStart(RoundStart(roundIndex: 2, question: question, startsAt: .now, deadline: .now.addingTimeInterval(10)))
        )

        let decoded = try JSONDecoder().decode(MultiplayerEnvelope.self, from: JSONEncoder().encode(envelope))
        #expect(decoded.protocolVersion == MultiplayerEnvelope.currentProtocolVersion)
        #expect(decoded.contentVersion == "2026.09")
        #expect(decoded.matchID == matchID)
        #expect(decoded.sequenceNumber == 42)
        guard case .roundStart(let round) = decoded.message else {
            Issue.record("roundStart 메시지가 복원되지 않았습니다.")
            return
        }
        #expect(round.roundIndex == 2)
        #expect(round.question == question)
    }

    @Test func rankingUsesDeclaredTieBreakersAndAllowsSharedRank() {
        let tiedStats = PlayerMatchState(id: UUID(), nickname: "가", score: 500, correctAnswers: 5, hintsUsed: 1, wrongAnswers: 1)
        let players = [
            PlayerMatchState(id: UUID(), nickname: "라", score: 400, correctAnswers: 6),
            PlayerMatchState(id: UUID(), nickname: "다", score: 500, correctAnswers: 4),
            tiedStats,
            PlayerMatchState(id: UUID(), nickname: "나", score: 500, correctAnswers: 5, hintsUsed: 1, wrongAnswers: 1)
        ]

        let ranked = MultiplayerScoring.ranked(players)
        #expect(ranked.map(\.nickname) == ["가", "나", "다", "라"])
        #expect(ranked.map(\.rank) == [1, 1, 3, 4])
    }

    @Test func loopIncludesTerminalStationsAndShortPoolAvoidsImmediateRepeat() {
        let stations = ["a", "b", "c"].map { Station(id: $0, name: $0, fullName: nil, aliases: []) }
        let pattern = RoutePattern(id: "loop", lineID: "line", name: "순환", kind: .loop, stationIDs: stations.map(\.id), stationCodes: nil)
        let catalog = TransitCatalog(
            schemaVersion: 1, contentVersion: "1", challengePoolVersion: "1", dataAsOf: "",
            sources: [], regions: [], operators: [], stations: stations,
            lines: [Line(id: "line", regionID: "r", operatorID: "o", name: "노선", shortName: "L", colorHex: "000000", sortOrder: 0)],
            routePatterns: [pattern]
        )

        let pool = MultiplayerQuestionFactory.pool(catalog: catalog, lineID: "line")
        let questions = MultiplayerQuestionFactory.questions(catalog: catalog, lineID: "line", count: 10, seed: 7)
        #expect(pool.count == 3)
        #expect(questions.count == 10)
        #expect(zip(questions, questions.dropFirst()).allSatisfy { $0.id != $1.id })
    }

    @Test func duplicatedTriplesAcrossPatternsAppearOnce() {
        let stations = ["a", "b", "c"].map { Station(id: $0, name: $0, fullName: nil, aliases: []) }
        let patterns = ["one", "two"].map {
            RoutePattern(id: $0, lineID: "line", name: $0, kind: .main, stationIDs: stations.map(\.id), stationCodes: nil)
        }
        let catalog = TransitCatalog(
            schemaVersion: 1, contentVersion: "1", challengePoolVersion: "1", dataAsOf: "",
            sources: [], regions: [], operators: [], stations: stations,
            lines: [Line(id: "line", regionID: "r", operatorID: "o", name: "노선", shortName: "L", colorHex: "000000", sortOrder: 0)],
            routePatterns: patterns
        )
        // 양 끝 역 문제를 포함하므로 a·b·c 한 계통은 3문제이고, 같은 계통이 하나 더 있어도 늘지 않는다.
        #expect(MultiplayerQuestionFactory.pool(catalog: catalog, lineID: "line").count == 3)
    }
}

/// 네트워크 없이 `MatchCoordinator`의 메시지 처리를 검증하기 위한 `NearbyMatchServing` 대역.
@MainActor
private final class FakeNearbyMatchService: NearbyMatchServing {
    var state: NearbyMatchService.State = .idle
    var discoveredRooms: [DiscoveredRoom] = []
    var messageHandler: ((UUID, MultiplayerEnvelope) -> Void)?
    var disconnectHandler: ((UUID) -> Void)?
    var connectionReadyHandler: ((UUID) -> Void)?
    var failureHandler: ((String) -> Void)?

    private(set) var sent: [(envelope: MultiplayerEnvelope, connectionID: UUID?)] = []
    private(set) var disconnected: [UUID] = []
    private var nextSequence: UInt64 = 0

    func startHosting(roomName: String, roomCode: String, contentVersion: String) { state = .hosting(code: roomCode) }
    func startBrowsing() { state = .browsing }
    func join(room: DiscoveredRoom, roomCode: String, contentVersion: String) { state = .joining }
    func send(_ envelope: MultiplayerEnvelope, to connectionID: UUID?) { sent.append((envelope, connectionID)) }
    func disconnect(connectionID: UUID) { disconnected.append(connectionID) }
    func stop() { state = .idle }

    /// 상대 기기에서 메시지가 도착한 것처럼 코디네이터에 전달한다.
    func deliver(
        _ message: MultiplayerMessage,
        from connectionID: UUID,
        contentVersion: String,
        protocolVersion: Int = MultiplayerEnvelope.currentProtocolVersion
    ) throws {
        nextSequence += 1
        var envelope = MultiplayerEnvelope(contentVersion: contentVersion, sequenceNumber: nextSequence, message: message)
        if protocolVersion != envelope.protocolVersion {
            // 프로토콜 버전은 생성자에서 고정되므로 인코딩한 JSON을 고쳐 다른 버전의 기기를 흉내 낸다.
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])
            object["protocolVersion"] = protocolVersion
            envelope = try JSONDecoder().decode(MultiplayerEnvelope.self, from: JSONSerialization.data(withJSONObject: object))
        }
        messageHandler?(connectionID, envelope)
    }

    func joinResponses(to connectionID: UUID) -> [JoinResponse] {
        sent.compactMap { item in
            guard item.connectionID == connectionID, case .joinResponse(let response) = item.envelope.message else { return nil }
            return response
        }
    }
}

@MainActor
struct MatchCoordinatorVersionTests {
    private static let contentVersion = "test-1"

    private func makeCatalog() -> TransitCatalog {
        let stations = ["a", "b", "c"].map { Station(id: $0, name: $0, fullName: nil, aliases: []) }
        return TransitCatalog(
            schemaVersion: 1, contentVersion: Self.contentVersion, challengePoolVersion: "1", dataAsOf: "",
            sources: [], regions: [], operators: [], stations: stations,
            lines: [Line(id: "line", regionID: "r", operatorID: "o", name: "노선", shortName: "L", colorHex: "000000", sortOrder: 0)],
            routePatterns: [RoutePattern(id: "main", lineID: "line", name: "본선", kind: .main, stationIDs: stations.map(\.id), stationCodes: nil)]
        )
    }

    private func makeHost() -> (MatchCoordinator, FakeNearbyMatchService) {
        let service = FakeNearbyMatchService()
        let coordinator = MatchCoordinator(catalog: makeCatalog(), service: service)
        coordinator.host(configuration: MultiplayerRoomConfiguration(regionID: "r", lineID: "line"), nickname: "방장")
        return (coordinator, service)
    }

    private func makeJoiningParticipant(hostConnection: UUID) -> (MatchCoordinator, FakeNearbyMatchService) {
        let service = FakeNearbyMatchService()
        let coordinator = MatchCoordinator(catalog: makeCatalog(), service: service)
        coordinator.browse(nickname: "참가자")
        coordinator.join(room: DiscoveredRoom(id: "room", name: "방", endpoint: AnyHashable("room")), code: "1234")
        service.connectionReadyHandler?(hostConnection)
        return (coordinator, service)
    }

    @Test func hostRejectsJoinRequestWithDifferentContentVersion() throws {
        let (coordinator, service) = makeHost()
        defer { coordinator.leave() }
        let connection = UUID()

        try service.deliver(.joinRequest(JoinRequest(playerID: UUID(), nickname: "구버전")), from: connection, contentVersion: "test-0")

        let responses = service.joinResponses(to: connection)
        #expect(responses.count == 1)
        #expect(responses.first?.accepted == false)
        #expect(coordinator.lobbyPlayers.count == 1)
        #expect(service.disconnected == [connection])
    }

    @Test func hostRejectsJoinRequestWithDifferentProtocolVersion() throws {
        let (coordinator, service) = makeHost()
        defer { coordinator.leave() }
        let connection = UUID()

        try service.deliver(
            .joinRequest(JoinRequest(playerID: UUID(), nickname: "신버전")),
            from: connection,
            contentVersion: Self.contentVersion,
            protocolVersion: MultiplayerEnvelope.currentProtocolVersion + 1
        )

        let responses = service.joinResponses(to: connection)
        #expect(responses.count == 1)
        #expect(responses.first?.accepted == false)
        #expect(coordinator.lobbyPlayers.count == 1)
        #expect(service.disconnected == [connection])
    }

    @Test func hostAcceptsJoinRequestWithSameVersion() throws {
        let (coordinator, service) = makeHost()
        defer { coordinator.leave() }
        let connection = UUID()
        let playerID = UUID()

        try service.deliver(.joinRequest(JoinRequest(playerID: playerID, nickname: "같은버전")), from: connection, contentVersion: Self.contentVersion)

        #expect(service.joinResponses(to: connection).map(\.accepted) == [true])
        #expect(coordinator.lobbyPlayers.map(\.id).contains(playerID))
        #expect(coordinator.lobbyPlayers.count == 2)
        #expect(service.disconnected.isEmpty)
    }

    @Test func participantFailsWithUpdateNoticeOnDifferentVersionMessage() throws {
        let hostConnection = UUID()
        let (coordinator, service) = makeJoiningParticipant(hostConnection: hostConnection)
        defer { coordinator.leave() }

        try service.deliver(
            .joinResponse(JoinResponse(accepted: false, reason: "버전이 달라요", player: nil)),
            from: hostConnection,
            contentVersion: "test-2"
        )

        #expect(coordinator.screenState == .failed(AppLocalization.text("multiplayer.error.updateRequired")))
        #expect(service.disconnected == [hostConnection])
        // 거절 후 연결이 끊겨도 재접속을 시도하지 않고 안내를 유지한다.
        service.disconnectHandler?(hostConnection)
        #expect(coordinator.screenState == .failed(AppLocalization.text("multiplayer.error.updateRequired")))
    }

    @Test func participantFailsWithUpdateNoticeOnDifferentProtocolVersion() throws {
        let hostConnection = UUID()
        let (coordinator, service) = makeJoiningParticipant(hostConnection: hostConnection)
        defer { coordinator.leave() }

        try service.deliver(
            .joinResponse(JoinResponse(accepted: false, reason: nil, player: nil)),
            from: hostConnection,
            contentVersion: Self.contentVersion,
            protocolVersion: MultiplayerEnvelope.currentProtocolVersion + 1
        )

        #expect(coordinator.screenState == .failed(AppLocalization.text("multiplayer.error.updateRequired")))
    }

    @Test func participantEntersLobbyWhenVersionsMatch() throws {
        let hostConnection = UUID()
        let (coordinator, service) = makeJoiningParticipant(hostConnection: hostConnection)
        defer { coordinator.leave() }

        let joinRequests = service.sent.filter {
            guard $0.connectionID == hostConnection, case .joinRequest = $0.envelope.message else { return false }
            return true
        }
        #expect(joinRequests.count == 1)

        let player = NearbyPlayer(id: coordinator.localPlayerID, nickname: "참가자", isHost: false, connectionState: .connected)
        try service.deliver(.joinResponse(JoinResponse(accepted: true, reason: nil, player: player)), from: hostConnection, contentVersion: Self.contentVersion)

        #expect(coordinator.screenState == .lobby)
        #expect(service.disconnected.isEmpty)
    }
}
