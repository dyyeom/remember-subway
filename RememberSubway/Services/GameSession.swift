import Foundation

struct SinglePlayerQuestion: Hashable, Sendable {
    let lineID: String
    let routePatternID: String
    let previous: Station?
    let target: Station
    let next: Station?
}

/// 계통 안의 한 문제 자리(이전·정답·다음 역). 싱글·멀티 문제 생성이 같은 중복 제거 규칙을 쓴다.
struct RouteQuestionSlot {
    let pattern: RoutePattern
    let index: Int
    let previousStationID: String?
    let targetStationID: String
    let nextStationID: String?

    /// 계통 순서대로 훑으며 (이전 역 ID, 정답 역 ID, 다음 역 ID) 조합이 처음 나온 자리만 남긴다.
    static func uniqueSlots(in patterns: [RoutePattern], minimumStationCount: Int) -> [RouteQuestionSlot] {
        var seenTriples = Set<String>()
        var slots: [RouteQuestionSlot] = []
        for pattern in patterns where pattern.stationIDs.count >= minimumStationCount {
            let ids = pattern.stationIDs
            for index in ids.indices {
                let previous = index > 0 ? ids[index - 1] : (pattern.kind == .loop ? ids.last : nil)
                let target = ids[index]
                let next = index + 1 < ids.count ? ids[index + 1] : (pattern.kind == .loop ? ids.first : nil)
                let triple = "\(previous ?? "none")|\(target)|\(next ?? "none")"
                guard seenTriples.insert(triple).inserted else { continue }
                slots.append(RouteQuestionSlot(
                    pattern: pattern,
                    index: index,
                    previousStationID: previous,
                    targetStationID: target,
                    nextStationID: next
                ))
            }
        }
        return slots
    }
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

enum SinglePlayerQuestionFactory {
    static func pointsPerCorrectAnswer(catalog: TransitCatalog, lineID: String?) -> Int {
        // 싱글플레이는 노선 길이와 관계없이 모든 문제를 100점 기준으로 계산한다.
        return 100
    }

    static func questions(
        catalog: TransitCatalog,
        regionID: String,
        lineID: String? = nil,
        shuffleSeed: UInt64? = nil
    ) -> [SinglePlayerQuestion] {
        let stations = catalog.stationByID
        let regionLineIDs = Set(catalog.lines.lazy.filter { $0.regionID == regionID }.map(\.id))
        let patterns = catalog.routePatterns.filter {
            regionLineIDs.contains($0.lineID) && (lineID == nil || $0.lineID == lineID)
        }
        // 계통이 겹치는 구간(예: 경춘선 상봉~춘천)은 같은 (이전, 정답, 다음) 조합을 한 번만 출제한다.
        var questions = RouteQuestionSlot.uniqueSlots(in: patterns, minimumStationCount: 2).compactMap { slot -> SinglePlayerQuestion? in
            guard let target = stations[slot.targetStationID] else { return nil }
            return SinglePlayerQuestion(
                lineID: slot.pattern.lineID,
                routePatternID: slot.pattern.id,
                previous: slot.previousStationID.flatMap { stations[$0] },
                target: target,
                next: slot.nextStationID.flatMap { stations[$0] }
            )
        }
        let seedText = "\(catalog.challengePoolVersion):\(regionID):\(lineID ?? "all")"
        let seed = seedText.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        let attemptSeed = shuffleSeed ?? UInt64.random(in: UInt64.min...UInt64.max)
        var generator = SeededGenerator(seed: seed ^ attemptSeed)
        questions.shuffle(using: &generator)
        return questions
    }
}

/// 문제 제한 시간. 일시정지하면 남은 시간을 보존하고 재개 시 그 시간부터 다시 줄어든다.
struct QuestionCountdown: Equatable {
    let duration: TimeInterval
    private(set) var deadline: Date?
    private(set) var pausedRemaining: TimeInterval?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let deadline else { return duration }
        return max(0, deadline.timeIntervalSince(now))
    }

    mutating func start(at now: Date) {
        deadline = now.addingTimeInterval(duration)
        pausedRemaining = nil
    }

    mutating func pause(at now: Date) {
        guard !isPaused, deadline != nil else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }

    mutating func resume(at now: Date) {
        guard let pausedRemaining else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }
}

@MainActor
final class SinglePlayerSession: ObservableObject {
    enum SubmissionResult: Equatable { case correct, incorrect, ignored }

    static let roundDuration: TimeInterval = 15
    static let fullScoreRemainingTime: TimeInterval = 10

    @Published private(set) var lives = 3
    @Published private(set) var score = 0
    @Published private(set) var index = 0
    @Published private(set) var hintVisible = false
    @Published private(set) var isFinished = false
    @Published private(set) var isRevealingIncorrectAnswer = false
    /// 중단 확인 팝업이 떠 있는 동안 입력·힌트·시간 초과를 막는다.
    @Published private(set) var isPaused = false

    @Published private(set) var questions: [SinglePlayerQuestion]
    let pointsPerCorrectAnswer: Int

    init(questions: [SinglePlayerQuestion], pointsPerCorrectAnswer: Int = 100) {
        self.questions = questions
        self.pointsPerCorrectAnswer = pointsPerCorrectAnswer
    }

    var current: SinglePlayerQuestion? { questions.isEmpty ? nil : questions[index % questions.count] }
    var hint: String { current.map { AnswerMatcher.initialConsonants(of: $0.target.name) } ?? "" }

    func useHint() {
        guard !isFinished, !isRevealingIncorrectAnswer, !isPaused else { return }
        hintVisible = true
    }

    func pause() {
        guard !isFinished else { return }
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func restart() {
        lives = 3
        score = 0
        index = 0
        hintVisible = false
        isFinished = false
        isRevealingIncorrectAnswer = false
        isPaused = false
        questions.shuffle()
    }

    @discardableResult
    func submit(
        _ answer: String,
        remainingTime: TimeInterval = SinglePlayerSession.roundDuration
    ) -> SubmissionResult {
        guard !isFinished, !isRevealingIncorrectAnswer, !isPaused, let current else { return .ignored }
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
    func expireCurrentQuestion() -> SubmissionResult {
        guard !isFinished, !isRevealingIncorrectAnswer, !isPaused, current != nil else { return .ignored }
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
