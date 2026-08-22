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
}

