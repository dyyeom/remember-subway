import Foundation

struct MultiplayerQuestion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let lineID: String
    let routePatternID: String
    let previousStationID: String
    let targetStationID: String
    let nextStationID: String
}

struct NearbyPlayer: Codable, Identifiable, Hashable, Sendable {
    enum ConnectionState: String, Codable, Sendable {
        case connected
        case reconnecting
        case forfeited
    }

    let id: UUID
    var nickname: String
    var isHost: Bool
    var connectionState: ConnectionState
}

struct MultiplayerRoomConfiguration: Codable, Hashable, Sendable {
    static let defaultQuestionCount = 10
    static let defaultRoundDuration: TimeInterval = 10
    static let defaultMaximumPlayers = 8

    let regionID: String
    let lineID: String
    var numberOfQuestions: Int = defaultQuestionCount
    var roundDuration: TimeInterval = defaultRoundDuration
    var maximumPlayers: Int = defaultMaximumPlayers
}

struct PlayerMatchState: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var nickname: String
    var score = 0
    var correctAnswers = 0
    var hintsUsed = 0
    var wrongAnswers = 0
    var rank = 1
    var isForfeited = false
}

struct MatchSnapshot: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Sendable {
        case lobby
        case countdown
        case playing
        case roundResult
        case matchResult
        case cancelled
    }

    let matchID: UUID
    var phase: Phase
    var roundIndex: Int
    var players: [PlayerMatchState]
}

struct MultiplayerRoundSubmission: Hashable, Sendable {
    let playerID: UUID
    let elapsed: TimeInterval
    let hintUsed: Bool
    let wrongAttempts: Int
}

struct MultiplayerRoundScore: Equatable, Sendable {
    let playerID: UUID
    let baseScore: Int
    let speedBonus: Int

    var total: Int { baseScore + speedBonus }
}

enum MultiplayerScoring {
    static let minimumSubmissionInterval: TimeInterval = 0.3

    static func scores(for submissions: [MultiplayerRoundSubmission]) -> [MultiplayerRoundScore] {
        let valid = submissions
            .filter { $0.elapsed >= 0 && $0.elapsed <= MultiplayerRoomConfiguration.defaultRoundDuration }
            .sorted {
                if $0.elapsed == $1.elapsed { return $0.playerID.uuidString < $1.playerID.uuidString }
                return $0.elapsed < $1.elapsed
            }

        return valid.enumerated().map { index, submission in
            let startingScore = submission.hintUsed ? 50 : 100
            let base = max(0, startingScore - submission.wrongAttempts * 20)
            let bonus = base > 0 ? [30, 20, 10].dropFirst(index).first ?? 0 : 0
            return MultiplayerRoundScore(playerID: submission.playerID, baseScore: base, speedBonus: bonus)
        }
    }

    static func ranked(_ players: [PlayerMatchState]) -> [PlayerMatchState] {
        let sorted = players.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.correctAnswers != rhs.correctAnswers { return lhs.correctAnswers > rhs.correctAnswers }
            if lhs.hintsUsed != rhs.hintsUsed { return lhs.hintsUsed < rhs.hintsUsed }
            if lhs.wrongAnswers != rhs.wrongAnswers { return lhs.wrongAnswers < rhs.wrongAnswers }
            return lhs.nickname.localizedStandardCompare(rhs.nickname) == .orderedAscending
        }

        var ranked: [PlayerMatchState] = []
        for (index, player) in sorted.enumerated() {
            var player = player
            if let previous = ranked.last,
               previous.score == player.score,
               previous.correctAnswers == player.correctAnswers,
               previous.hintsUsed == player.hintsUsed,
               previous.wrongAnswers == player.wrongAnswers {
                player.rank = previous.rank
            } else {
                player.rank = index + 1
            }
            ranked.append(player)
        }
        return ranked
    }
}

enum MultiplayerQuestionFactory {
    static func pool(catalog: TransitCatalog, lineID: String) -> [MultiplayerQuestion] {
        let patterns = catalog.routePatterns.filter { $0.lineID == lineID }
        var seenTriples = Set<String>()
        var questions: [MultiplayerQuestion] = []

        for pattern in patterns where pattern.stationIDs.count >= 3 {
            let indices: [Int]
            if pattern.kind == .loop {
                indices = Array(pattern.stationIDs.indices)
            } else {
                indices = Array(1..<(pattern.stationIDs.count - 1))
            }

            for index in indices {
                let previousIndex = index == 0 ? pattern.stationIDs.count - 1 : index - 1
                let nextIndex = index == pattern.stationIDs.count - 1 ? 0 : index + 1
                let previous = pattern.stationIDs[previousIndex]
                let target = pattern.stationIDs[index]
                let next = pattern.stationIDs[nextIndex]
                let triple = "\(previous)|\(target)|\(next)"
                guard seenTriples.insert(triple).inserted else { continue }
                questions.append(MultiplayerQuestion(
                    id: "\(pattern.id):\(index)",
                    lineID: lineID,
                    routePatternID: pattern.id,
                    previousStationID: previous,
                    targetStationID: target,
                    nextStationID: next
                ))
            }
        }
        return questions
    }

    static func questions(
        catalog: TransitCatalog,
        lineID: String,
        count: Int = MultiplayerRoomConfiguration.defaultQuestionCount,
        seed: UInt64
    ) -> [MultiplayerQuestion] {
        guard count > 0 else { return [] }
        let pool = pool(catalog: catalog, lineID: lineID)
        guard !pool.isEmpty else { return [] }

        var generator = SeededGenerator(seed: seed)
        var result: [MultiplayerQuestion] = []
        var previousID: String?
        while result.count < count {
            var batch = pool
            batch.shuffle(using: &generator)
            if batch.count > 1, batch.first?.id == previousID {
                batch.swapAt(0, 1)
            }
            let needed = count - result.count
            result.append(contentsOf: batch.prefix(needed))
            previousID = result.last?.id
        }
        return result
    }
}
