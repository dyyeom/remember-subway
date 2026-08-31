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
