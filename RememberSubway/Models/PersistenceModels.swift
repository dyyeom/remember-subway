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
    var bestScore: Int
    var pendingSubmission: Bool
    var updatedAt: Date

    init(weekID: String, poolVersion: String, bestScore: Int = 0, pendingSubmission: Bool = false, updatedAt: Date = .now) {
        self.key = "\(poolVersion):\(weekID)"
        self.weekID = weekID
        self.poolVersion = poolVersion
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

    init(key: String = "settings", hasCompletedTutorial: Bool = false, hapticsEnabled: Bool = true) {
        self.key = key
        self.hasCompletedTutorial = hasCompletedTutorial
        self.hapticsEnabled = hapticsEnabled
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
