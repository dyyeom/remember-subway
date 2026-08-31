import Foundation
import SwiftData

@MainActor
enum ProgressStore {
    private static let retiredAchievementIDs = ["first_segment", "perfect_segment", "first_line", "first_region", "all_regions"]

    struct WeeklyRecordUpdate {
        let record: WeeklyBestRecord
        let didImproveBest: Bool
    }

    static func recordAttempt(segment: Segment, session: GameSession, context: ModelContext) throws {
        let id = segment.id
        let descriptor = FetchDescriptor<SegmentProgressRecord>(predicate: #Predicate { $0.segmentID == id })
        let record = try context.fetch(descriptor).first ?? SegmentProgressRecord(segmentID: id, routePatternID: segment.routePatternID)
        if record.modelContext == nil { context.insert(record) }
        record.attempts += 1
        record.wrongAnswers += session.wrongAnswers
        if case .completed(let stars) = session.outcome {
            record.completions += 1
            record.bestStars = max(record.bestStars, stars)
        }
        record.updatedAt = .now
        try context.save()
    }

    static func recordWeekly(score: Int, weekID: String, poolVersion: String, context: ModelContext) throws -> WeeklyRecordUpdate {
        let key = "\(poolVersion):\(weekID)"
        let descriptor = FetchDescriptor<WeeklyBestRecord>(predicate: #Predicate { $0.key == key })
        let record = try context.fetch(descriptor).first ?? WeeklyBestRecord(weekID: weekID, poolVersion: poolVersion)
        if record.modelContext == nil { context.insert(record) }
        let didImproveBest = score > record.bestScore
        if didImproveBest {
            record.bestScore = score
            record.pendingSubmission = true
            record.updatedAt = .now
        }
        try context.save()
        return WeeklyRecordUpdate(record: record, didImproveBest: didImproveBest)
    }

    static func queueAchievement(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<PendingAchievementRecord>(predicate: #Predicate { $0.achievementID == id })
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(PendingAchievementRecord(achievementID: id))
        try context.save()
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

    static func earnedAchievementIDs(after segment: Segment, stars: Int, catalog: TransitCatalog, context: ModelContext) throws -> [String] {
        let completed = Set(try context.fetch(FetchDescriptor<SegmentProgressRecord>()).filter { $0.completions > 0 }.map(\.segmentID))
        var ids = ["first_segment"]
        if stars == 3 { ids.append("perfect_segment") }

        guard let pattern = catalog.routePatterns.first(where: { $0.id == segment.routePatternID }),
              let line = catalog.lineByID[pattern.lineID] else { return ids }
        let lineSegments = catalog.patterns(for: line).flatMap { catalog.segments(for: $0) }
        if lineSegments.allSatisfy({ completed.contains($0.id) }) { ids.append("first_line") }

        let regionLines = catalog.lines.filter { $0.regionID == line.regionID }
        let regionSegments = regionLines.flatMap { targetLine in catalog.patterns(for: targetLine).flatMap { catalog.segments(for: $0) } }
        if regionSegments.allSatisfy({ completed.contains($0.id) }) { ids.append("first_region") }

        let allSegments = catalog.routePatterns.flatMap { catalog.segments(for: $0) }
        if allSegments.allSatisfy({ completed.contains($0.id) }) { ids.append("all_regions") }
        return ids
    }
}
