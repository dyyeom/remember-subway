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
