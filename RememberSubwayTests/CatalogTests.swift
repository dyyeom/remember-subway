import Foundation
import SwiftData
import Testing
@testable import RememberSubway

@MainActor
struct CatalogTests {
    @Test func bundledCatalogIsValidAndSegmentsOverlapAtAnchor() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        #expect(CatalogValidator.validate(catalog).isEmpty)
        for pattern in catalog.routePatterns {
            let segments = catalog.segments(for: pattern)
            #expect(segments.allSatisfy { (2...9).contains($0.stationIDs.count) })
            for pair in zip(segments, segments.dropFirst()) {
                #expect(pair.0.stationIDs.last == pair.1.stationIDs.first)
            }
        }
    }

    @Test func weeklyOrderChangesByAttemptSeedWithoutChangingQuestionPool() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let first = WeeklyChallengeFactory.questions(catalog: catalog, weekID: "2026-W33", regionID: "capital", shuffleSeed: 1)
        let repeated = WeeklyChallengeFactory.questions(catalog: catalog, weekID: "2026-W33", regionID: "capital", shuffleSeed: 1)
        let second = WeeklyChallengeFactory.questions(catalog: catalog, weekID: "2026-W33", regionID: "capital", shuffleSeed: 2)
        #expect(first == repeated)
        #expect(first != second)
        #expect(Set(first) == Set(second))
        #expect(!first.isEmpty)
    }

    @Test func weeklyQuestionsStayInsideRegionAndUseThreeAdjacentStations() throws {
        let catalog = try TransitCatalogStore.load(from: .main)

        for region in catalog.regions {
            let questions = WeeklyChallengeFactory.questions(catalog: catalog, weekID: "2026-W33", regionID: region.id)
            #expect(!questions.isEmpty)

            for question in questions {
                let line = try #require(catalog.lineByID[question.lineID])
                let pattern = try #require(catalog.routePatterns.first { $0.id == question.routePatternID })
                #expect(line.regionID == region.id)
                #expect(zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).contains {
                    $0 == question.previous.id && $1 == question.target.id
                })
                #expect(zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).contains {
                    $0 == question.target.id && $1 == question.next.id
                })
            }
        }
    }

    @Test func weeklyLineQuestionsStayInsideSelectedLine() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let questions = WeeklyChallengeFactory.questions(
            catalog: catalog,
            weekID: "2026-W33",
            regionID: "capital",
            lineID: "seoul-4",
            shuffleSeed: 1
        )

        #expect(!questions.isEmpty)
        #expect(questions.allSatisfy { $0.lineID == "seoul-4" })
        let stationCount = Set(catalog.patterns(for: catalog.lineByID["seoul-4"]!).flatMap(\.stationIDs)).count
        #expect(stationCount * 10 == 510)
    }

    @Test func bundledCatalogCoversAllOperatingUrbanRailLines() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let expectedStationCounts = [
            "seoul-1": 102, "seoul-2": 51, "seoul-3": 44, "seoul-4": 51,
            "seoul-5": 56, "seoul-6": 39, "seoul-7": 53, "seoul-8": 24,
            "seoul-9": 38, "seoul-ui": 13, "seoul-sillim": 11,
            "incheon-1": 33, "incheon-2": 27,
            "suin-bundang": 63, "gyeongui-jungang": 58,
            "gyeongchun": 24, "gyeonggang": 12, "seohae": 21,
            "shinbundang": 16, "arex": 14,
            "busan-1": 40, "busan-2": 43, "busan-3": 17, "busan-4": 14,
            "busan-gimhae": 21, "donghae": 23,
            "daegu-1": 35, "daegu-2": 29, "daegu-3": 30,
            "daegyeong": 7,
            "gwangju-1": 20, "daejeon-1": 22
        ]

        #expect(Set(catalog.lines.map(\.id)) == Set(expectedStationCounts.keys))
        for line in catalog.lines {
            let stationIDs = Set(catalog.patterns(for: line).flatMap(\.stationIDs))
            #expect(stationIDs.count == expectedStationCounts[line.id])
        }
        let capital = try #require(catalog.regions.first { $0.id == "capital" })
        #expect(capital.name == "수도권")
        #expect(catalog.lines(in: capital).count == 20)
        #expect(!catalog.regions.contains { $0.id == "seoul" || $0.id == "incheon" })
        #expect(catalog.sources.count >= 15)
        #expect(catalog.dataAsOf == "2026-08-22")
    }

    @Test func bundledCatalogIncludesKorailMetropolitanCoverage() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let requiredStations: [String: Set<String>] = [
            "seoul-1": ["연천", "인천", "신창", "광명", "서동탄"],
            "seoul-3": ["대화", "오금"],
            "seoul-4": ["진접", "오이도"],
            "gyeongui-jungang": ["도라산", "지평", "서울역"],
            "gyeongchun": ["청량리", "춘천"],
            "gyeonggang": ["판교", "성남", "여주"],
            "suin-bundang": ["청량리", "인천"],
            "seohae": ["일산", "원시"],
            "donghae": ["부전", "태화강"],
            "daegyeong": ["구미", "경산"]
        ]

        for (lineID, requiredNames) in requiredStations {
            let line = try #require(catalog.lineByID[lineID])
            let stationNames = Set(catalog.patterns(for: line).flatMap(\.stationIDs).compactMap { catalog.stationByID[$0]?.name })
            #expect(requiredNames.isSubset(of: stationNames))
        }

        #expect(catalog.lineByID["seoul-1"]?.name == "서울 1호선")
    }

    @Test func bundledCatalogExposesOnlyReviewedMetropolitanRoutePatterns() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let expectedPatternNames: [String: Set<String>] = [
            "seoul-1": ["연천 → 인천", "광운대 → 신창", "영등포 → 광명", "병점 → 서동탄"],
            "seoul-3": ["대화 → 오금"],
            "seoul-4": ["진접 → 오이도"]
        ]

        for (lineID, expectedNames) in expectedPatternNames {
            let line = try #require(catalog.lineByID[lineID])
            #expect(Set(catalog.patterns(for: line).map(\.name)) == expectedNames)
        }
    }

    @Test func weeklyResultMessagesDistinguishLoginAndSubmissionStates() {
        #expect(WeeklyResultStatus.zeroScore.message.contains("0점"))
        #expect(WeeklyResultStatus.zeroScore.message.contains("전송하지 않아요"))
        #expect(WeeklyResultStatus.waitingForGameCenter.message.contains("Game Center에 로그인하면"))
        #expect(WeeklyResultStatus.submissionFailed.message.contains("전송에 실패"))
        #expect(WeeklyResultStatus.submitted.message.contains("전송했어요"))
    }

    @Test func weeklyZeroScoreDoesNotEnterGameCenterSubmissionQueue() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WeeklyBestRecord.self, configurations: configuration)
        let context = container.mainContext

        let zero = try ProgressStore.recordWeekly(score: 0, weekID: "2026-W34", poolVersion: "test", context: context)
        #expect(!zero.didImproveBest)
        #expect(zero.record.bestScore == 0)
        #expect(!zero.record.pendingSubmission)

        let best = try ProgressStore.recordWeekly(score: 100, weekID: "2026-W34", poolVersion: "test", context: context)
        #expect(best.didImproveBest)
        #expect(best.record.pendingSubmission)

        let lower = try ProgressStore.recordWeekly(score: 50, weekID: "2026-W34", poolVersion: "test", context: context)
        #expect(!lower.didImproveBest)
        #expect(lower.record.bestScore == 100)
    }

    @Test func weeklyRecordsAndLeaderboardsAreSeparatedByScope() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WeeklyBestRecord.self, configurations: configuration)
        let context = container.mainContext
        let regionLeaderboard = GameCenterService.weeklyLeaderboardID(regionID: "capital", lineID: nil)
        let lineLeaderboard = GameCenterService.weeklyLeaderboardID(regionID: "capital", lineID: "seoul-4")

        _ = try ProgressStore.recordWeekly(
            score: 100, weekID: "2026-W36", poolVersion: "test",
            scopeID: "region:capital", leaderboardID: regionLeaderboard, context: context
        )
        _ = try ProgressStore.recordWeekly(
            score: 510, weekID: "2026-W36", poolVersion: "test",
            scopeID: "line:seoul-4", leaderboardID: lineLeaderboard, context: context
        )

        let records = try context.fetch(FetchDescriptor<WeeklyBestRecord>())
        #expect(records.count == 2)
        #expect(Set(records.map(\.leaderboardID)) == Set([regionLeaderboard, lineLeaderboard]))
        #expect(lineLeaderboard.hasSuffix("line.seoul_4.v1"))
    }
}
