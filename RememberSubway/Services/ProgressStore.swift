import Foundation
import SwiftData

@MainActor
enum ProgressStore {
    private static let retiredAchievementIDs = ["first_segment", "perfect_segment", "first_line", "first_region", "all_regions"]

    struct SinglePlayerRecordUpdate {
        let record: SinglePlayerBestRecord
        let didImproveBest: Bool
    }

    /// 범위(지역·노선)의 대표 최고 기록. 문제 풀 버전(`poolVersion`)과 상관없이 bestScore가 가장 높은 기록을 쓰고,
    /// 같으면 최근에 갱신된 기록을 고른다. 버전별 레코드는 지우지 않으므로 Game Center 제출 대기 상태도 그대로 남는다.
    static func bestRecord(scopeID: String, in records: [SinglePlayerBestRecord]) -> SinglePlayerBestRecord? {
        records
            .filter { $0.scopeID == scopeID }
            .max { ($0.bestScore, $0.updatedAt) < ($1.bestScore, $1.updatedAt) }
    }

    static func bestScore(scopeID: String, in records: [SinglePlayerBestRecord]) -> Int {
        bestRecord(scopeID: scopeID, in: records)?.bestScore ?? 0
    }

    /// 범위마다 대표 기록 하나만 남긴 목록. 최근 갱신 순으로 정렬한다.
    static func representativeRecords(_ records: [SinglePlayerBestRecord]) -> [SinglePlayerBestRecord] {
        Set(records.map(\.scopeID))
            .compactMap { bestRecord(scopeID: $0, in: records) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 최고 기록은 범위 기준으로 이어진다. 같은 범위의 기존 대표 기록보다 높을 때만 그 기록을 갱신하고,
    /// 범위에 기록이 없을 때만 현재 `poolVersion` 키로 새 기록을 만든다.
    static func recordSinglePlayer(
        score: Int,
        poolVersion: String,
        scopeID: String = "legacy",
        leaderboardID: String = GameCenterService.singlePlayerLeaderboardID,
        context: ModelContext
    ) throws -> SinglePlayerRecordUpdate {
        let descriptor = FetchDescriptor<SinglePlayerBestRecord>(predicate: #Predicate { $0.scopeID == scopeID })
        let record = bestRecord(scopeID: scopeID, in: try context.fetch(descriptor)) ?? SinglePlayerBestRecord(
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
