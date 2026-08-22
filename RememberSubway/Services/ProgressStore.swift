import Foundation
import SwiftData

@MainActor
enum ProgressStore {
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
