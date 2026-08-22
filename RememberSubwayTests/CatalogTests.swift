import Foundation
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

    @Test func weeklyOrderIsDeterministic() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let first = WeeklyChallengeFactory.questions(catalog: catalog, weekID: "2026-W33", regionID: "capital")
        let second = WeeklyChallengeFactory.questions(catalog: catalog, weekID: "2026-W33", regionID: "capital")
        #expect(first == second)
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

    @Test func bundledCatalogCoversAllOperatingUrbanRailLines() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let expectedStationCounts = [
            "seoul-1": 10, "seoul-2": 51, "seoul-3": 34, "seoul-4": 29,
            "seoul-5": 56, "seoul-6": 39, "seoul-7": 53, "seoul-8": 24,
            "seoul-9": 38, "seoul-ui": 13, "seoul-sillim": 11,
            "incheon-1": 33, "incheon-2": 27,
            "suin-bundang": 63, "gyeongui-jungang": 55,
            "shinbundang": 16, "arex": 14,
            "busan-1": 40, "busan-2": 43, "busan-3": 17, "busan-4": 14,
            "busan-gimhae": 21,
            "daegu-1": 35, "daegu-2": 29, "daegu-3": 30,
            "gwangju-1": 20, "daejeon-1": 22
        ]

        #expect(Set(catalog.lines.map(\.id)) == Set(expectedStationCounts.keys))
        for line in catalog.lines {
            let stationIDs = Set(catalog.patterns(for: line).flatMap(\.stationIDs))
            #expect(stationIDs.count == expectedStationCounts[line.id])
        }
        let capital = try #require(catalog.regions.first { $0.id == "capital" })
        #expect(capital.name == "수도권")
        #expect(catalog.lines(in: capital).count == 17)
        #expect(!catalog.regions.contains { $0.id == "seoul" || $0.id == "incheon" })
        #expect(catalog.sources.count >= 14)
        #expect(catalog.dataAsOf == "2026-08-22")
    }
}
