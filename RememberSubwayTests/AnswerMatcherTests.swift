import Foundation
import Testing
@testable import RememberSubway

struct AnswerMatcherTests {
    let station = Station(id: "one", name: "학동·증심사입구", fullName: "학동·증심사입구(조선대병원)", aliases: ["학동증심사입구"])

    @Test func normalizesStationSuffixAndPunctuation() {
        #expect(AnswerMatcher.normalize(" 학동·증심사입구역 ") == "학동증심사입구")
        #expect(AnswerMatcher.matches("학동 증심사입구", station: station))
    }

    @Test func doesNotAcceptTypos() {
        #expect(!AnswerMatcher.matches("학동증심사입고", station: station))
    }

    @Test func extractsKoreanInitials() {
        #expect(AnswerMatcher.initialConsonants(of: "을지로3가") == "ㅇㅈㄹ3ㄱ")
    }

    @Test(arguments: [
        ("sui-003", "4", "19민주묘지"),
        ("ev-008", "시청", "용인대"),
        ("ev-015", "전대", "에버랜드"),
        ("b2-012", "경성대", "부경대"),
        ("b2-017", "국제금융센터", "부산은행"),
        ("g1-003", "학동", "증심사입구"),
        ("s2-023", "교대(법원", "검찰청)")
    ])
    @MainActor
    func acceptsMiddleDotVariantsInStationNames(stationID: String, head: String, tail: String) throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let station = try #require(catalog.stationByID[stationID])
        let separators = ["", ".", " "] + AnswerMatcher.middleDotVariants.map { String(Character($0)) }
        for separator in separators {
            let answer = head + separator + tail
            #expect(AnswerMatcher.matches(answer, station: station), "\(stationID): \(answer.unicodeScalars.map { String($0.value, radix: 16) })")
            #expect(AnswerMatcher.matches(answer + "역", station: station) || stationID == "s2-023", "\(stationID): \(answer)역")
        }
    }

    @Test(arguments: [
        ("ev-008", "시청·용인대", "시청", "용인대"),
        ("ev-015", "전대·에버랜드", "전대", "에버랜드"),
        ("b2-012", "경성대·부경대", "경성대", "부경대"),
        ("b2-017", "국제금융센터·부산은행", "국제금융센터", "부산은행"),
        ("g1-003", "학동·증심사입구", "학동", "증심사입구")
    ])
    @MainActor
    func acceptsEachPartOfMiddleDotJoinedStationNames(stationID: String, name: String, head: String, tail: String) throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let station = try #require(catalog.stationByID[stationID])
        #expect(station.name == name)
        let answers = [name, head + tail, head + "ㆍ" + tail, head, tail, head + "역", tail + "역"]
        for answer in answers {
            #expect(AnswerMatcher.matches(answer, station: station), "\(stationID): \(answer)")
        }
    }

    @Test @MainActor
    func doesNotSplitFourNineteenMemorialStation() throws {
        let catalog = try TransitCatalogStore.load(from: .main)
        let station = try #require(catalog.stationByID["sui-003"])
        #expect(station.name == "4·19민주묘지")
        #expect(AnswerMatcher.matches("419민주묘지", station: station))
        #expect(AnswerMatcher.matches("4ㆍ19민주묘지", station: station))
        #expect(!AnswerMatcher.matches("4", station: station))
        #expect(!AnswerMatcher.matches("19민주묘지", station: station))
    }

    @Test func middleDotVariantsDoNotStripHangulJamo() {
        #expect(AnswerMatcher.normalize("ㆍ전대ᆞ에버랜드ㆍ") == "전대에버랜드")
        #expect(AnswerMatcher.normalize("ㄱㅏㅎ") == "ㄱㅏㅎ")
        #expect(AnswerMatcher.normalize("한") != "")
        #expect(!AnswerMatcher.matches("전대ㆍ에버", station: Station(id: "x", name: "전대·에버랜드", fullName: nil, aliases: [])))
    }

    @Test func initialConsonantsKeepMiddleDot() {
        #expect(AnswerMatcher.initialConsonants(of: "전대·에버랜드") == "ㅈㄷ·ㅇㅂㄹㄷ")
        #expect(AnswerMatcher.initialConsonants(of: "4·19민주묘지") == "4·19ㅁㅈㅁㅈ")
    }
}
