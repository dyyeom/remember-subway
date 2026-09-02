import Foundation
import SwiftData

@Model
final class SegmentProgressRecord {
    @Attribute(.unique) var segmentID: String
    var routePatternID: String
    var bestStars: Int
    var attempts: Int
    var completions: Int
    var wrongAnswers: Int
    var updatedAt: Date

    init(segmentID: String, routePatternID: String, bestStars: Int = 0, attempts: Int = 0, completions: Int = 0, wrongAnswers: Int = 0, updatedAt: Date = .now) {
        self.segmentID = segmentID
        self.routePatternID = routePatternID
        self.bestStars = bestStars
        self.attempts = attempts
        self.completions = completions
        self.wrongAnswers = wrongAnswers
        self.updatedAt = updatedAt
    }
}

@Model
final class WeeklyBestRecord {
    @Attribute(.unique) var key: String
    var weekID: String
    var poolVersion: String
    var scopeID: String = "legacy"
    var leaderboardID: String = "kr.co.remembersubway.weekly.v1"
    var bestScore: Int
    var pendingSubmission: Bool
    var updatedAt: Date

    init(
        weekID: String,
        poolVersion: String,
        scopeID: String = "legacy",
        leaderboardID: String = "kr.co.remembersubway.weekly.v1",
        bestScore: Int = 0,
        pendingSubmission: Bool = false,
        updatedAt: Date = .now
    ) {
        self.key = "\(poolVersion):\(weekID):\(scopeID)"
        self.weekID = weekID
        self.poolVersion = poolVersion
        self.scopeID = scopeID
        self.leaderboardID = leaderboardID
        self.bestScore = bestScore
        self.pendingSubmission = pendingSubmission
        self.updatedAt = updatedAt
    }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var key: String
    var hasCompletedTutorial: Bool
    var hapticsEnabled: Bool
    var multiplayerNickname: String = ""
    var didRemoveLegacyProgress: Bool = false

    init(
        key: String = "settings",
        hasCompletedTutorial: Bool = false,
        hapticsEnabled: Bool = true,
        multiplayerNickname: String = "",
        didRemoveLegacyProgress: Bool = false
    ) {
        self.key = key
        self.hasCompletedTutorial = hasCompletedTutorial
        self.hapticsEnabled = hapticsEnabled
        self.multiplayerNickname = multiplayerNickname
        self.didRemoveLegacyProgress = didRemoveLegacyProgress
    }
}

@Model
final class MultiplayerProfileRecord {
    @Attribute(.unique) var key: String
    var matches: Int
    var wins: Int
    var podiums: Int
    var correctAnswers: Int
    var totalQuestions: Int
    var bestScore: Int
    var updatedAt: Date

    init(
        key: String = "multiplayer-profile",
        matches: Int = 0,
        wins: Int = 0,
        podiums: Int = 0,
        correctAnswers: Int = 0,
        totalQuestions: Int = 0,
        bestScore: Int = 0,
        updatedAt: Date = .now
    ) {
        self.key = key
        self.matches = matches
        self.wins = wins
        self.podiums = podiums
        self.correctAnswers = correctAnswers
        self.totalQuestions = totalQuestions
        self.bestScore = bestScore
        self.updatedAt = updatedAt
    }
}

@Model
final class MultiplayerMatchRecord {
    @Attribute(.unique) var id: UUID
    var playedAt: Date
    var regionID: String
    var lineID: String
    var score: Int
    var rank: Int
    var playerCount: Int
    var correctAnswers: Int
    var hintsUsed: Int
    var wrongAnswers: Int

    init(
        id: UUID = UUID(),
        playedAt: Date = .now,
        regionID: String,
        lineID: String,
        score: Int,
        rank: Int,
        playerCount: Int,
        correctAnswers: Int,
        hintsUsed: Int,
        wrongAnswers: Int
    ) {
        self.id = id
        self.playedAt = playedAt
        self.regionID = regionID
        self.lineID = lineID
        self.score = score
        self.rank = rank
        self.playerCount = playerCount
        self.correctAnswers = correctAnswers
        self.hintsUsed = hintsUsed
        self.wrongAnswers = wrongAnswers
    }
}

@Model
final class PendingAchievementRecord {
    @Attribute(.unique) var achievementID: String
    var percentComplete: Double
    var updatedAt: Date

    init(achievementID: String, percentComplete: Double = 100, updatedAt: Date = .now) {
        self.achievementID = achievementID
        self.percentComplete = percentComplete
        self.updatedAt = updatedAt
    }
}
