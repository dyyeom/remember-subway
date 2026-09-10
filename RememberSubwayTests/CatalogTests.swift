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

    @Test func  singlePlayerOrderChangesByAttemptSeedWithoutChangingQuestionPool() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let first = SinglePlayerQuestionFactory.questions(catalog: catalog, regionID: "capital", shuffleSeed: 1)
        let repeated = SinglePlayerQuestionFactory.questions(catalog: catalog, regionID: "capital", shuffleSeed: 1)
        let second = SinglePlayerQuestionFactory.questions(catalog: catalog, regionID: "capital", shuffleSeed: 2)
        #expect(first == repeated)
        #expect(first != second)
        #expect(Set(first) == Set(second))
        #expect(!first.isEmpty)
    }

    @Test func singlePlayerQuestionsIncludeLineEndpoints() throws {
        let catalog = try TransitCatalogStore.load(from: .main)

        for region in catalog.regions {
            let questions = SinglePlayerQuestionFactory.questions(catalog: catalog, regionID: region.id)
            #expect(!questions.isEmpty)

            for question in questions {
                let line = try #require(catalog.lineByID[question.lineID])
                let pattern = try #require(catalog.routePatterns.first { $0.id == question.routePatternID })
                #expect(line.regionID == region.id)
                if let previous = question.previous {
                    #expect(zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).contains { $0 == previous.id && $1 == question.target.id })
                }
                if let next = question.next {
                    #expect(zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).contains { $0 == question.target.id && $1 == next.id })
                }
            }
        }
    }

    @Test func  singlePlayerLineQuestionsStayInsideSelectedLine() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let questions = SinglePlayerQuestionFactory.questions(
            catalog: catalog,
            regionID: "capital",
            lineID: "seoul-4",
            shuffleSeed: 1
        )

        #expect(!questions.isEmpty)
        #expect(questions.allSatisfy { $0.lineID == "seoul-4" })
        #expect(SinglePlayerQuestionFactory.pointsPerCorrectAnswer(catalog: catalog, lineID: "seoul-4") == 100)
        #expect(SinglePlayerQuestionFactory.pointsPerCorrectAnswer(catalog: catalog, lineID: nil) == 100)
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

    @Test func  singlePlayerResultMessagesDistinguishLoginAndSubmissionStates() {
        let messages = [
            SinglePlayerResultStatus.zeroScore.message,
            SinglePlayerResultStatus.bestUnchanged.message,
            SinglePlayerResultStatus.waitingForGameCenter.message,
            SinglePlayerResultStatus.submissionFailed.message,
            SinglePlayerResultStatus.submitted.message
        ]
        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(Set(messages).count == messages.count)
        #expect(SinglePlayerResultStatus.zeroScore.message.contains("0"))
        #expect(SinglePlayerResultStatus.zeroScore.message.contains("Game Center"))
    }

    @Test func appBundleContainsEnglishAndKoreanLocalizations() throws {
        let englishPath = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let koreanPath = try #require(Bundle.main.path(forResource: "ko", ofType: "lproj"))
        let english = try #require(Bundle(path: englishPath))
        let korean = try #require(Bundle(path: koreanPath))

        #expect(english.localizedString(forKey: "tab.singlePlayer", value: nil, table: nil) == "Single Player")
        #expect(korean.localizedString(forKey: "tab.singlePlayer", value: nil, table: nil) == "싱글플레이")

        let englishInfo = try localizedInfo(at: englishPath)
        let koreanInfo = try localizedInfo(at: koreanPath)
        #expect(englishInfo["CFBundleDisplayName"] as? String == "RememberSubway")
        #expect(koreanInfo["CFBundleDisplayName"] as? String == "사이역")
    }

    private func localizedInfo(at localizationPath: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: localizationPath).appendingPathComponent("InfoPlist.strings")
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func  singlePlayerZeroScoreDoesNotEnterGameCenterSubmissionQueue() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SinglePlayerBestRecord.self, configurations: configuration)
        let context = container.mainContext

        let zero = try ProgressStore.recordSinglePlayer(score: 0, poolVersion: "test", context: context)
        #expect(!zero.didImproveBest)
        #expect(zero.record.bestScore == 0)
        #expect(!zero.record.pendingSubmission)

        let best = try ProgressStore.recordSinglePlayer(score: 100, poolVersion: "test", context: context)
        #expect(best.didImproveBest)
        #expect(best.record.pendingSubmission)

        let lower = try ProgressStore.recordSinglePlayer(score: 50, poolVersion: "test", context: context)
        #expect(!lower.didImproveBest)
        #expect(lower.record.bestScore == 100)
    }

    @Test func singlePlayerRecordsAndLeaderboardsAreSeparatedByScope() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SinglePlayerBestRecord.self, configurations: configuration)
        let context = container.mainContext
        let regionLeaderboard = GameCenterService.singlePlayerLeaderboardID(regionID: "capital", lineID: nil)
        let lineLeaderboard = GameCenterService.singlePlayerLeaderboardID(regionID: "capital", lineID: "seoul-4")

        _ = try ProgressStore.recordSinglePlayer(
            score: 100, poolVersion: "test",
            scopeID: "region:capital", leaderboardID: regionLeaderboard, context: context
        )
        _ = try ProgressStore.recordSinglePlayer(
            score: 510, poolVersion: "test",
            scopeID: "line:seoul-4", leaderboardID: lineLeaderboard, context: context
        )

        let records = try context.fetch(FetchDescriptor<SinglePlayerBestRecord>())
        #expect(records.count == 2)
        #expect(Set(records.map(\.leaderboardID)) == Set([regionLeaderboard, lineLeaderboard]))
        #expect(lineLeaderboard.hasSuffix("line.seoul_4.v1"))
    }
}
