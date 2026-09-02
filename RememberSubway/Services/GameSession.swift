import Foundation

@MainActor
final class GameSession: ObservableObject {
    enum Outcome: Equatable { case playing, completed(stars: Int), failed }
    enum SubmissionResult: Equatable { case correct, incorrect, ignored }

    let segment: Segment
    let stations: [Station]
    let isReversed: Bool

    @Published private(set) var currentIndex = 1
    @Published private(set) var lives = 3
    @Published private(set) var penalties = 0
    @Published private(set) var wrongAnswers = 0
    @Published private(set) var hintUsedForCurrentStation = false
    @Published private(set) var outcome: Outcome = .playing

    init(segment: Segment, stationByID: [String: Station], reverse: Bool = Bool.random()) {
        self.segment = segment
        isReversed = reverse
        let resolved = segment.stationIDs.compactMap { stationByID[$0] }
        stations = reverse ? resolved.reversed() : resolved
        if stations.count < 2 { outcome = .failed }
    }

    var anchor: Station { stations[0] }
    var currentTarget: Station? { currentIndex < stations.count ? stations[currentIndex] : nil }
    var target: Station? { outcome == .playing ? currentTarget : nil }
    var progress: Double { guard stations.count > 1 else { return 0 }; return Double(currentIndex - 1) / Double(stations.count - 1) }
    var stars: Int { max(1, 3 - penalties) }
    var hint: String? { target.map { AnswerMatcher.initialConsonants(of: $0.name) } }

    func useHint() {
        guard outcome == .playing, !hintUsedForCurrentStation else { return }
        hintUsedForCurrentStation = true
        penalties += 1
    }

    func retry() {
        currentIndex = 1
        lives = 3
        penalties = 0
        wrongAnswers = 0
        hintUsedForCurrentStation = false
        outcome = stations.count < 2 ? .failed : .playing
    }

    @discardableResult
    func submit(_ answer: String) -> SubmissionResult {
        guard outcome == .playing, let target else { return .ignored }
        if AnswerMatcher.matches(answer, station: target) {
            currentIndex += 1
            hintUsedForCurrentStation = false
            if currentIndex >= stations.count { outcome = .completed(stars: stars) }
            return .correct
        }

        lives -= 1
        penalties += 1
        wrongAnswers += 1
        if lives == 0 { outcome = .failed }
        return .incorrect
    }
}

struct WeeklyQuestion: Hashable, Sendable {
    let lineID: String
    let routePatternID: String
    let previous: Station
    let target: Station
    let next: Station
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

enum WeeklyChallengeFactory {
    static func pointsPerCorrectAnswer(catalog: TransitCatalog, lineID: String?) -> Int {
        guard let lineID, let line = catalog.lineByID[lineID] else { return 100 }
        let stationCount = Set(catalog.patterns(for: line).flatMap(\.stationIDs)).count
        return stationCount * 10
    }

    static func weekID(for date: Date = .now, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    static func questions(
        catalog: TransitCatalog,
        weekID: String,
        regionID: String,
        lineID: String? = nil,
        shuffleSeed: UInt64? = nil
    ) -> [WeeklyQuestion] {
        let stations = catalog.stationByID
        let regionLineIDs = Set(catalog.lines.lazy.filter { $0.regionID == regionID }.map(\.id))
        var questions = catalog.routePatterns.filter {
            regionLineIDs.contains($0.lineID) && (lineID == nil || $0.lineID == lineID)
        }.flatMap { pattern -> [WeeklyQuestion] in
            guard pattern.stationIDs.count >= 3 else { return [] }
            return (1..<(pattern.stationIDs.count - 1)).compactMap { index in
                guard let previous = stations[pattern.stationIDs[index - 1]],
                      let target = stations[pattern.stationIDs[index]],
                      let next = stations[pattern.stationIDs[index + 1]] else { return nil }
                return WeeklyQuestion(
                    lineID: pattern.lineID,
                    routePatternID: pattern.id,
                    previous: previous,
                    target: target,
                    next: next
                )
            }
        }
        let seedText = "\(catalog.challengePoolVersion):\(weekID):\(regionID):\(lineID ?? "all")"
        let seed = seedText.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        let attemptSeed = shuffleSeed ?? UInt64.random(in: UInt64.min...UInt64.max)
        var generator = SeededGenerator(seed: seed ^ attemptSeed)
        questions.shuffle(using: &generator)
        return questions
    }
}

@MainActor
final class WeeklyChallengeSession: ObservableObject {
    static let roundDuration: TimeInterval = 15
    static let fullScoreRemainingTime: TimeInterval = 10

    @Published private(set) var lives = 3
    @Published private(set) var score = 0
    @Published private(set) var index = 0
    @Published private(set) var hintVisible = false
    @Published private(set) var isFinished = false
    @Published private(set) var isRevealingIncorrectAnswer = false

    @Published private(set) var questions: [WeeklyQuestion]
    let pointsPerCorrectAnswer: Int

    init(questions: [WeeklyQuestion], pointsPerCorrectAnswer: Int = 100) {
        self.questions = questions
        self.pointsPerCorrectAnswer = pointsPerCorrectAnswer
    }

    var current: WeeklyQuestion? { questions.isEmpty ? nil : questions[index % questions.count] }
    var hint: String { current.map { AnswerMatcher.initialConsonants(of: $0.target.name) } ?? "" }

    func useHint() {
        guard !isFinished, !isRevealingIncorrectAnswer else { return }
        hintVisible = true
    }

    func restart() {
        lives = 3
        score = 0
        index = 0
        hintVisible = false
        isFinished = false
        isRevealingIncorrectAnswer = false
        questions.shuffle()
    }

    @discardableResult
    func submit(
        _ answer: String,
        remainingTime: TimeInterval = WeeklyChallengeSession.roundDuration
    ) -> GameSession.SubmissionResult {
        guard !isFinished, !isRevealingIncorrectAnswer, let current else { return .ignored }
        if AnswerMatcher.matches(answer, station: current.target) {
            score += Self.points(
                basePoints: pointsPerCorrectAnswer,
                hintUsed: hintVisible,
                remainingTime: remainingTime
            )
            advanceQuestion()
            return .correct
        }
        return expireCurrentQuestion()
    }

    @discardableResult
    func expireCurrentQuestion() -> GameSession.SubmissionResult {
        guard !isFinished, !isRevealingIncorrectAnswer, current != nil else { return .ignored }
        lives -= 1
        isRevealingIncorrectAnswer = true
        return .incorrect
    }

    static func points(basePoints: Int, hintUsed: Bool, remainingTime: TimeInterval) -> Int {
        let hintAdjustedPoints = hintUsed ? basePoints / 2 : basePoints
        let clampedTime = min(max(remainingTime, 0), fullScoreRemainingTime)
        let multiplier = clampedTime / fullScoreRemainingTime
        return Int((Double(hintAdjustedPoints) * multiplier).rounded(.down))
    }

    func continueAfterIncorrectAnswer() {
        guard isRevealingIncorrectAnswer else { return }
        isRevealingIncorrectAnswer = false
        if lives == 0 {
            isFinished = true
        } else {
            advanceQuestion()
        }
    }

    private func advanceQuestion() {
        index += 1
        hintVisible = false
        if index >= questions.count {
            questions.shuffle()
            index = 0
        }
    }
}
