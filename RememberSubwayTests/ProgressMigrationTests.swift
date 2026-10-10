import Foundation
import SwiftData
import Testing
@testable import RememberSubway

@MainActor
struct ProgressMigrationTests {
    @Test func legacyProgressIsRemovedOnceWithoutDeletingSinglePlayerRecords() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SegmentProgressRecord.self,
            SinglePlayerBestRecord.self,
            AppSettingsRecord.self,
            PendingAchievementRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        let settings = AppSettingsRecord()
        context.insert(settings)
        context.insert(SegmentProgressRecord(segmentID: "old", routePatternID: "route"))
        context.insert(SinglePlayerBestRecord(poolVersion: "v1", bestScore: 300))
        context.insert(PendingAchievementRecord(achievementID: "first_segment"))

        try ProgressStore.removeLegacyProgressIfNeeded(settings: settings, context: context)
        #expect(try context.fetch(FetchDescriptor<SegmentProgressRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingAchievementRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SinglePlayerBestRecord>()).count == 1)
        #expect(settings.didRemoveLegacyProgress)

        context.insert(SegmentProgressRecord(segmentID: "later", routePatternID: "route"))
        try ProgressStore.removeLegacyProgressIfNeeded(settings: settings, context: context)
        #expect(try context.fetch(FetchDescriptor<SegmentProgressRecord>()).count == 1)
    }

    private func makeBestRecordContainer() throws -> ModelContainer {
        try ModelContainer(for: SinglePlayerBestRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func previousPoolVersionBestStillShowsAfterPoolVersionChange() throws {
        let container = try makeBestRecordContainer()
        let context = container.mainContext
        _ = try ProgressStore.recordSinglePlayer(score: 700, poolVersion: "2026.10.1", scopeID: "region:capital", context: context)

        // 새 문제 풀 버전에서도 같은 범위의 이전 기록이 내 최고 점수로 보인다.
        let records = try context.fetch(FetchDescriptor<SinglePlayerBestRecord>())
        #expect(ProgressStore.bestScore(scopeID: "region:capital", in: records) == 700)
        #expect(ProgressStore.bestScore(scopeID: "line:seoul-4", in: records) == 0)

        // 새 버전에서 더 낮은 점수는 새 레코드를 만들지 않고 기존 최고 기록을 유지한다.
        let lower = try ProgressStore.recordSinglePlayer(score: 500, poolVersion: "2026.10.2", scopeID: "region:capital", context: context)
        #expect(!lower.didImproveBest)
        #expect(lower.record.bestScore == 700)
        #expect(try context.fetch(FetchDescriptor<SinglePlayerBestRecord>()).count == 1)
    }

    @Test func bestScoreUsesHighestRecordAcrossPoolVersions() throws {
        let container = try makeBestRecordContainer()
        let context = container.mainContext
        context.insert(SinglePlayerBestRecord(poolVersion: "v1", scopeID: "line:gyeongchun", bestScore: 300))
        context.insert(SinglePlayerBestRecord(poolVersion: "v2", scopeID: "line:gyeongchun", bestScore: 900))
        context.insert(SinglePlayerBestRecord(poolVersion: "v3", scopeID: "line:gyeongchun", bestScore: 600))
        context.insert(SinglePlayerBestRecord(poolVersion: "v3", scopeID: "region:capital", bestScore: 1_200))
        try context.save()

        let records = try context.fetch(FetchDescriptor<SinglePlayerBestRecord>())
        #expect(ProgressStore.bestScore(scopeID: "line:gyeongchun", in: records) == 900)
        #expect(ProgressStore.bestRecord(scopeID: "line:gyeongchun", in: records)?.poolVersion == "v2")
        let representatives = ProgressStore.representativeRecords(records)
        #expect(representatives.count == 2)
        #expect(Set(representatives.map(\.bestScore)) == [900, 1_200])

        let update = try ProgressStore.recordSinglePlayer(score: 800, poolVersion: "v4", scopeID: "line:gyeongchun", context: context)
        #expect(!update.didImproveBest)
        #expect(update.record.bestScore == 900)
    }

    @Test func bestRecordUpdatesOnlyWhenNewScoreIsHigher() throws {
        let container = try makeBestRecordContainer()
        let context = container.mainContext
        context.insert(SinglePlayerBestRecord(poolVersion: "v1", scopeID: "line:seoul-2", bestScore: 500))
        try context.save()

        let equal = try ProgressStore.recordSinglePlayer(score: 500, poolVersion: "v2", scopeID: "line:seoul-2", context: context)
        #expect(!equal.didImproveBest)
        #expect(!equal.record.pendingSubmission)

        let higher = try ProgressStore.recordSinglePlayer(score: 650, poolVersion: "v2", scopeID: "line:seoul-2", context: context)
        #expect(higher.didImproveBest)
        #expect(higher.record.bestScore == 650)
        #expect(higher.record.pendingSubmission)

        let records = try context.fetch(FetchDescriptor<SinglePlayerBestRecord>())
        #expect(records.count == 1)
        #expect(ProgressStore.bestScore(scopeID: "line:seoul-2", in: records) == 650)
    }

    @Test func pendingGameCenterSubmissionsArePreservedAcrossPoolVersions() throws {
        let container = try makeBestRecordContainer()
        let context = container.mainContext
        let leaderboard = GameCenterService.singlePlayerLeaderboardID(regionID: "capital", lineID: nil)
        context.insert(SinglePlayerBestRecord(
            poolVersion: "v1", scopeID: "region:capital", leaderboardID: leaderboard,
            bestScore: 400, pendingSubmission: true
        ))
        context.insert(SinglePlayerBestRecord(
            poolVersion: "v2", scopeID: "region:capital", leaderboardID: leaderboard,
            bestScore: 800, pendingSubmission: true
        ))
        try context.save()

        // 낮은 점수는 아무 레코드도 바꾸지 않아 대기 중인 제출이 모두 남는다.
        _ = try ProgressStore.recordSinglePlayer(score: 300, poolVersion: "v3", scopeID: "region:capital", leaderboardID: leaderboard, context: context)
        var records = try context.fetch(FetchDescriptor<SinglePlayerBestRecord>())
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.pendingSubmission })
        #expect(Set(records.map(\.leaderboardID)) == [leaderboard])

        // 더 높은 점수는 대표 기록을 갱신하고 제출 대기로 둔다. 다른 버전 기록의 대기 상태도 지우지 않는다.
        let update = try ProgressStore.recordSinglePlayer(score: 1_000, poolVersion: "v3", scopeID: "region:capital", leaderboardID: leaderboard, context: context)
        #expect(update.didImproveBest)
        #expect(update.record.pendingSubmission)
        records = try context.fetch(FetchDescriptor<SinglePlayerBestRecord>())
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.pendingSubmission })
        #expect(ProgressStore.bestScore(scopeID: "region:capital", in: records) == 1_000)
    }

    @Test func multiplayerHistoryKeepsTwentyMostRecentMatches() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: MultiplayerProfileRecord.self,
            MultiplayerMatchRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        let player = PlayerMatchState(id: UUID(), nickname: "테스터", score: 700, correctAnswers: 7, hintsUsed: 1, wrongAnswers: 2, rank: 1)

        for index in 0..<22 {
            try ProgressStore.recordMultiplayerMatch(
                regionID: "capital", lineID: "seoul-1", player: player,
                playerCount: 4, context: context
            )
            if let newest = try context.fetch(FetchDescriptor<MultiplayerMatchRecord>(sortBy: [SortDescriptor(\.playedAt, order: .reverse)])).first {
                newest.playedAt = Date(timeIntervalSince1970: TimeInterval(index))
            }
        }

        let history = try context.fetch(FetchDescriptor<MultiplayerMatchRecord>())
        let profile = try #require(context.fetch(FetchDescriptor<MultiplayerProfileRecord>()).first)
        #expect(history.count == 20)
        #expect(profile.matches == 22)
        #expect(profile.wins == 22)
    }

    @Test func unavailablePersistentStoreFallsBackToInMemoryStore() throws {
        // 상위 경로가 일반 파일이라 영구 저장소를 만들 수 없는 위치.
        let blocker = FileManager.default.temporaryDirectory.appending(path: "storage-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let storage = AppModelContainer.make(configuration: ModelConfiguration(url: blocker.appending(path: "default.store")))
        #expect(!storage.isPersistent)
        #expect(try Data(contentsOf: blocker) == Data("x".utf8))

        let context = storage.container.mainContext
        context.insert(SinglePlayerBestRecord(poolVersion: "v1", bestScore: 100))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SinglePlayerBestRecord>()).count == 1)
    }
}
