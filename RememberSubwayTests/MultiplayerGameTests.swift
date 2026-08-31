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
        #expect(MultiplayerQuestionFactory.pool(catalog: catalog, lineID: "line").count == 1)
    }
}
