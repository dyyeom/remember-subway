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
    let anchor: Station
    let target: Station
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
    static func weekID(for date: Date = .now, calendar: Calendar = Calendar(identifier: .iso8601)) -> String {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    static func questions(catalog: TransitCatalog, weekID: String) -> [WeeklyQuestion] {
        let stations = catalog.stationByID
        var questions = catalog.routePatterns.flatMap { pattern in
            zip(pattern.stationIDs, pattern.stationIDs.dropFirst()).flatMap { firstID, secondID -> [WeeklyQuestion] in
                guard let first = stations[firstID], let second = stations[secondID] else { return [] }
                return [
                    WeeklyQuestion(lineID: pattern.lineID, routePatternID: pattern.id, anchor: first, target: second),
                    WeeklyQuestion(lineID: pattern.lineID, routePatternID: pattern.id, anchor: second, target: first)
                ]
            }
        }
        let seedText = "\(catalog.challengePoolVersion):\(weekID)"
        let seed = seedText.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        var generator = SeededGenerator(seed: seed)
        questions.shuffle(using: &generator)
        return questions
    }
}

@MainActor
final class WeeklyChallengeSession: ObservableObject {
    @Published private(set) var lives = 3
    @Published private(set) var score = 0
    @Published private(set) var index = 0
    @Published private(set) var hintVisible = false
    @Published private(set) var isFinished = false

    let questions: [WeeklyQuestion]
    init(questions: [WeeklyQuestion]) { self.questions = questions }

    var current: WeeklyQuestion? { questions.isEmpty ? nil : questions[index % questions.count] }
    var hint: String { current.map { AnswerMatcher.initialConsonants(of: $0.target.name) } ?? "" }

    func useHint() { guard !isFinished else { return }; hintVisible = true }

    @discardableResult
    func submit(_ answer: String) -> GameSession.SubmissionResult {
        guard !isFinished, let current else { return .ignored }
        if AnswerMatcher.matches(answer, station: current.target) {
            score += hintVisible ? 50 : 100
            index += 1
            hintVisible = false
            return .correct
        }
        lives -= 1
        if lives == 0 { isFinished = true }
        return .incorrect
    }
}
