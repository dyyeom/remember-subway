import Foundation
import SwiftData

@MainActor
enum ProgressStore {
    private static let retiredAchievementIDs = ["first_segment", "perfect_segment", "first_line", "first_region", "all_regions"]

    struct SinglePlayerRecordUpdate {
        let record: SinglePlayerBestRecord
        let didImproveBest: Bool
    }

    static func recordSinglePlayer(
        score: Int,
        poolVersion: String,
        scopeID: String = "legacy",
        leaderboardID: String = GameCenterService.singlePlayerLeaderboardID,
        context: ModelContext
    ) throws -> SinglePlayerRecordUpdate {
        let key = "\(poolVersion):\(scopeID)"
        let descriptor = FetchDescriptor<SinglePlayerBestRecord>(predicate: #Predicate { $0.key == key })
        let record = try context.fetch(descriptor).first ?? SinglePlayerBestRecord(
            poolVersion: poolVersion,
            scopeID: scopeID,
            leaderboardID: leaderboardID
        )
        if record.modelContext == nil { context.insert(record) }
        let didImproveBest = score > record.bestScore
        if didImproveBest {
            record.bestScore = score
            record.pendingSubmission = true
            record.updatedAt = .now
        }
        try context.save()
        return SinglePlayerRecordUpdate(record: record, didImproveBest: didImproveBest)
    }

    static func removeLegacyProgressIfNeeded(settings: AppSettingsRecord, context: ModelContext) throws {
        guard !settings.didRemoveLegacyProgress else { return }
        for record in try context.fetch(FetchDescriptor<SegmentProgressRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<PendingAchievementRecord>())
            where retiredAchievementIDs.contains(record.achievementID) {
            context.delete(record)
        }
        settings.didRemoveLegacyProgress = true
        try context.save()
    }

    static func recordMultiplayerMatch(
        regionID: String,
        lineID: String,
        player: PlayerMatchState,
        playerCount: Int,
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<MultiplayerProfileRecord>(predicate: #Predicate { $0.key == "multiplayer-profile" })
        let profile = try context.fetch(descriptor).first ?? MultiplayerProfileRecord()
        if profile.modelContext == nil { context.insert(profile) }
        profile.matches += 1
        if player.rank == 1 { profile.wins += 1 }
        if player.rank <= 3 { profile.podiums += 1 }
        profile.correctAnswers += player.correctAnswers
        profile.totalQuestions += MultiplayerRoomConfiguration.defaultQuestionCount
        profile.bestScore = max(profile.bestScore, player.score)
        profile.updatedAt = .now

        context.insert(MultiplayerMatchRecord(
            regionID: regionID,
            lineID: lineID,
            score: player.score,
            rank: player.rank,
            playerCount: playerCount,
            correctAnswers: player.correctAnswers,
            hintsUsed: player.hintsUsed,
            wrongAnswers: player.wrongAnswers
        ))

        var history = try context.fetch(FetchDescriptor<MultiplayerMatchRecord>(sortBy: [SortDescriptor(\.playedAt, order: .reverse)]))
        if history.count > 20 {
            for record in history.dropFirst(20) { context.delete(record) }
            history.removeLast(history.count - 20)
        }
        try context.save()
    }
}
