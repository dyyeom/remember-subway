import SwiftData
import SwiftUI
import UIKit

struct GameSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settings: [AppSettingsRecord]
    @StateObject private var session: GameSession
    @State private var answer = ""
    @State private var feedback = ""
    @State private var feedbackKind: FeedbackKind = .neutral
    @State private var didRecord = false
    @FocusState private var answerFocused: Bool
    let line: Line
    let catalog: TransitCatalog

    init(segment: Segment, line: Line, catalog: TransitCatalog) {
        self.line = line
        self.catalog = catalog
        _session = StateObject(wrappedValue: GameSession(segment: segment, stationByID: catalog.stationByID))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                statusRow
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Text(directionLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)

                StationSignView(
                    station: previousStation,
                    stationCode: currentStationCode,
                    line: line
                )
                .padding(.top, 34)

                VStack(spacing: 20) {
                    Text("다음 역은?")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    if session.hintUsedForCurrentStation {
                        Text(session.hint ?? "")
                            .font(.title2.monospaced().bold())
                            .foregroundStyle(line.color)
                            .accessibilityLabel("초성 힌트 \(session.hint ?? "")")
                    }

                    answerField

                    feedbackView
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationTitle("\(session.segment.index + 1)구간")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isCompleted)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .tint(line.color)
        .task { answerFocused = true }
        .onChange(of: session.outcome) { _, outcome in handleOutcome(outcome) }
        .overlay { resultOverlay }
    }

    private var previousStation: Station {
        session.stations[max(0, session.currentIndex - 1)]
    }

    private var routePattern: RoutePattern? {
        catalog.routePatterns.first { $0.id == session.segment.routePatternID }
    }

    private var currentStationCode: String {
        routePattern?.stationCode(for: previousStation.id, fallback: line.shortName) ?? line.shortName
    }

    private var directionLabel: String {
        guard let pattern = routePattern,
              let terminalID = session.isReversed ? pattern.stationIDs.first : pattern.stationIDs.last,
              let terminal = catalog.stationByID[terminalID] else {
            return session.isReversed ? "역방향" : "정방향"
        }
        return "\(terminal.name) 방면"
    }

    private var statusRow: some View {
        VStack(spacing: 10) {
            HStack {
                LineIdentityLabel(line: line)
                Spacer()
                Text("\(session.currentIndex - 1) / \(max(session.stations.count - 1, 1))")
                    .font(.headline.monospacedDigit())
                    .accessibilityLabel("진행 \(session.currentIndex - 1), 전체 \(max(session.stations.count - 1, 1))")
                Spacer()
                LivesView(lives: session.lives)
            }
            ProgressView(value: session.progress)
                .tint(line.color)
                .accessibilityLabel("구간 진행률")
        }
    }

    private var answerField: some View {
        TextField("역 이름 입력", text: $answer)
            .font(.title3)
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(answerFocused ? line.color : .secondary.opacity(0.22), lineWidth: answerFocused ? 2 : 1)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($answerFocused)
            .onSubmit(submit)
            .accessibilityLabel("역 이름 입력")
    }

    private var actionBar: some View {
        GameGlassActionBar(
            color: line.color,
            hintTitle: "초성 힌트",
            hintDisabled: session.hintUsedForCurrentStation,
            confirmDisabled: AnswerMatcher.normalize(answer).isEmpty,
            onHint: {
                session.useHint()
                feedback = "초성 힌트를 사용했어요."
                feedbackKind = .neutral
                restoreAnswerFocus()
            },
            onConfirm: submit
        )
    }

    private func submit() {
        let submittedStationName = session.target?.name
        switch session.submit(answer) {
        case .correct:
            feedback = "\(submittedStationName ?? "역 이름"), 정답이에요!"
            feedbackKind = .correct
            answer = ""
            impact(.success)
        case .incorrect:
            feedback = session.lives > 0 ? "아니에요. 다시 생각해 보세요." : "목숨을 모두 사용했어요."
            feedbackKind = .incorrect
            impact(.error)
        case .ignored: break
        }
        UIAccessibility.post(notification: .announcement, argument: feedback)
        restoreAnswerFocus()
    }

    private var feedbackView: some View {
        Group {
            if feedback.isEmpty {
                Color.clear
            } else {
                Text(feedback)
                    .font(feedbackKind == .correct ? .largeTitle.bold() : .callout)
                    .foregroundStyle(feedbackColor)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .id(feedback)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .frame(minHeight: feedbackKind == .correct ? 48 : 24)
        .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.28), value: feedback)
    }

    private var feedbackColor: Color {
        switch feedbackKind {
        case .correct: line.color
        case .incorrect: .red
        case .neutral: .secondary
        }
    }

    private func restoreAnswerFocus() {
        guard session.outcome == .playing else { return }
        Task { @MainActor in
            await Task.yield()
            answerFocused = true
        }
    }

    private func handleOutcome(_ outcome: GameSession.Outcome) {
        guard outcome != .playing, !didRecord else { return }
        answerFocused = false
        didRecord = true
        try? ProgressStore.recordAttempt(segment: session.segment, session: session, context: modelContext)
        if case .completed(let stars) = outcome {
            UIAccessibility.post(
                notification: .announcement,
                argument: "축하해요. \(line.name) \(session.segment.index + 1)구간의 모든 역을 맞혔어요."
            )
            let achievementIDs = (try? ProgressStore.earnedAchievementIDs(after: session.segment, stars: stars, catalog: catalog, context: modelContext)) ?? []
            for id in achievementIDs { try? ProgressStore.queueAchievement(id: id, context: modelContext) }
            Task {
                for id in achievementIDs {
                    if await GameCenterService.shared.reportAchievement(id: id) {
                        let descriptor = FetchDescriptor<PendingAchievementRecord>(predicate: #Predicate { $0.achievementID == id })
                        if let record = try? modelContext.fetch(descriptor).first { modelContext.delete(record) }
                    }
                }
                try? modelContext.save()
            }
        }
    }

    private func impact(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard settings.first?.hapticsEnabled ?? true else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    @ViewBuilder private var resultOverlay: some View {
        if case .completed(let stars) = session.outcome {
            completionOverlay(stars: stars)
        } else if case .failed = session.outcome {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "heart.slash.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.red)
                    Text("다시 도전해 볼까요?")
                        .font(.title2.bold())
                    if let target = session.currentTarget {
                        Text("이번 정답: \(target.name)")
                            .foregroundStyle(.secondary)
                    }
                    Button("즉시 재도전") {
                        didRecord = false
                        answer = ""
                        feedback = ""
                        feedbackKind = .neutral
                        session.retry()
                        answerFocused = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(28)
                .frame(maxWidth: 340)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                .padding()
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
    }

    private var isCompleted: Bool {
        if case .completed = session.outcome { true } else { false }
    }

    private func completionOverlay(stars: Int) -> some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            CelebrationFireworksView(color: line.color, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer(minLength: 56)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(line.color)
                    .accessibilityHidden(true)

                Text("축하해요!")
                    .font(.largeTitle.bold())
                    .padding(.top, 24)

                Text("\(line.name) \(session.segment.index + 1)구간의\n모든 역을 맞혔어요.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                VStack(spacing: 16) {
                    StarsView(stars: stars)
                    Divider()
                    LabeledContent("오답", value: "\(session.wrongAnswers)회")
                }
                .padding(22)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.top, 32)

                Spacer(minLength: 32)

                Button {
                    dismiss()
                } label: {
                    Label("끝내기", systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.glassProminent)
                .tint(line.color)
                .accessibilityHint("완료 화면을 닫고 노선 화면으로 이동합니다")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
    }
}

private enum FeedbackKind {
    case neutral
    case correct
    case incorrect
}

private struct CelebrationFireworksView: View {
    @State private var exploded = false
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            if reduceMotion {
                staticSparkles(in: proxy.size)
            } else {
                ForEach(0..<42, id: \.self) { index in
                    particle(index, in: proxy.size)
                }
            }
        }
        .ignoresSafeArea()
        .task {
            guard !reduceMotion else { return }
            await Task.yield()
            exploded = true
        }
    }

    private func particle(_ index: Int, in size: CGSize) -> some View {
        let burst = index / 14
        let ray = index % 14
        let angle = (Double(ray) / 14 * Double.pi * 2) - Double.pi / 2
        let origin = burstOrigin(burst, in: size)
        let distance: CGFloat = burst == 2 ? 112 : 88
        let destination = CGPoint(
            x: origin.x + CGFloat(cos(angle)) * distance,
            y: origin.y + CGFloat(sin(angle)) * distance
        )

        return Capsule(style: .continuous)
            .fill(particleColor(index))
            .frame(width: 6, height: 16)
            .rotationEffect(.radians(angle + Double.pi / 2))
            .scaleEffect(exploded ? 0.45 : 1)
            .position(exploded ? destination : origin)
            .opacity(exploded ? 0 : 1)
            .animation(
                .easeOut(duration: 1.05)
                    .delay(Double(burst) * 0.16 + Double(ray % 3) * 0.025),
                value: exploded
            )
    }

    private func burstOrigin(_ burst: Int, in size: CGSize) -> CGPoint {
        switch burst {
        case 0: CGPoint(x: size.width * 0.22, y: size.height * 0.24)
        case 1: CGPoint(x: size.width * 0.78, y: size.height * 0.28)
        default: CGPoint(x: size.width * 0.5, y: size.height * 0.12)
        }
    }

    private func particleColor(_ index: Int) -> Color {
        switch index % 5 {
        case 0: color
        case 1: .yellow
        case 2: .orange
        case 3: .pink
        default: .cyan
        }
    }

    private func staticSparkles(in size: CGSize) -> some View {
        ZStack {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundStyle(color)
                .position(x: size.width * 0.2, y: size.height * 0.2)
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(.yellow)
                .position(x: size.width * 0.82, y: size.height * 0.25)
        }
        .opacity(0.7)
    }
}
