import Foundation
import Testing
@testable import RememberSubway

@MainActor
struct GameSessionTests {
    private let stations = [
        Station(id: "a", name: "가역", fullName: nil, aliases: []),
        Station(id: "b", name: "나역", fullName: nil, aliases: []),
        Station(id: "c", name: "다역", fullName: nil, aliases: [])
    ]

    private func makeSession(reverse: Bool = false) -> GameSession {
        GameSession(
            segment: Segment(id: "s", routePatternID: "p", index: 0, stationIDs: stations.map(\.id)),
            stationByID: Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) }),
            reverse: reverse
        )
    }

    @Test func followsSelectedDirection() {
        #expect(makeSession().anchor.name == "가역")
        #expect(makeSession(reverse: true).anchor.name == "다역")
    }

    @Test func losesLivesAndFailsOnThirdError() {
        let session = makeSession()
        #expect(session.submit("오답") == .incorrect)
        #expect(session.submit("오답") == .incorrect)
        #expect(session.submit("오답") == .incorrect)
        #expect(session.lives == 0)
        #expect(session.outcome == .failed)
    }

    @Test func completesAndScoresStars() {
        let session = makeSession()
        session.useHint()
        #expect(session.submit("나") == .correct)
        #expect(session.submit("다역") == .correct)
        #expect(session.outcome == .completed(stars: 2))
    }

    @Test func weeklySessionKeepsPlayingAcrossConsecutiveCorrectAnswers() {
        let questions = [
            WeeklyQuestion(lineID: "line", routePatternID: "route", previous: stations[0], target: stations[1], next: stations[2]),
            WeeklyQuestion(lineID: "line", routePatternID: "route", previous: stations[1], target: stations[2], next: stations[0])
        ]
        let session = WeeklyChallengeSession(questions: questions)

        #expect(session.submit("나역") == .correct)
        #expect(session.current?.target.name == "다역")
        #expect(!session.isFinished)
        #expect(session.submit("다역") == .correct)
        #expect(Set(session.questions.map(\.target.name)) == Set(["나역", "다역"]))
        #expect(!session.isFinished)
    }

    @Test func lineScoreUsesConfiguredPointsAndHintAwardsHalf() {
        let questions = [WeeklyQuestion(
            lineID: "line", routePatternID: "route",
            previous: stations[0], target: stations[1], next: stations[2]
        )]
        let session = WeeklyChallengeSession(questions: questions, pointsPerCorrectAnswer: 510)

        session.useHint()
        #expect(session.submit("나역") == .correct)
        #expect(session.score == 255)
    }

    @Test func incorrectAnswerWaitsForRevealThenAdvances() {
        let questions = [
            WeeklyQuestion(lineID: "line", routePatternID: "route", previous: stations[0], target: stations[1], next: stations[2]),
            WeeklyQuestion(lineID: "line", routePatternID: "route", previous: stations[1], target: stations[2], next: stations[0])
        ]
        let session = WeeklyChallengeSession(questions: questions)

        #expect(session.submit("오답") == .incorrect)
        #expect(session.current?.target.name == "나역")
        #expect(session.isRevealingIncorrectAnswer)
        #expect(session.submit("나역") == .ignored)
        session.continueAfterIncorrectAnswer()
        #expect(session.current?.target.name == "다역")
        #expect(!session.isRevealingIncorrectAnswer)
    }

    @Test func lastLifeFinishesAfterIncorrectAnswerReveal() {
        let question = WeeklyQuestion(
            lineID: "line", routePatternID: "route",
            previous: stations[0], target: stations[1], next: stations[2]
        )
        let session = WeeklyChallengeSession(questions: [question])

        for _ in 0..<2 {
            #expect(session.submit("오답") == .incorrect)
            session.continueAfterIncorrectAnswer()
        }
        #expect(session.submit("오답") == .incorrect)
        #expect(!session.isFinished)
        session.continueAfterIncorrectAnswer()
        #expect(session.isFinished)
    }

    @Test func keyboardLayoutReducesOnlyVerticalSpacing() {
        let regular = GamePlayLayoutMetrics.regular
        let compact = GamePlayLayoutMetrics.keyboardPresented

        #expect(compact.totalVerticalSpacing < regular.totalVerticalSpacing)
        #expect(compact.statusTop > 0)
        #expect(compact.promptSpacing > 0)
        #expect(compact.promptBottom > 0)
    }
}
