import SwiftData
import SwiftUI
import UIKit

struct SinglePlayerChallengeHomeView: View {
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query(sort: \SinglePlayerBestRecord.updatedAt, order: .reverse) private var bestRecords: [SinglePlayerBestRecord]
    @Binding var showSettings: Bool
    @Binding var showStats: Bool
    @State private var selectedRegionID: String?
    @State private var selectedLineID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SubwayHomeHeader(
                    symbol: "trophy.fill",
                    title: AppLocalization.text("single.home.title"),
                    message: scoreDescription,
                    accent: SubwayTheme.action
                )
                VStack(spacing: 0) {
                    HStack {
                        Label(AppLocalization.text("single.region.label"), systemImage: "map")
                            .font(.headline)
                            .foregroundStyle(SubwayTheme.ink)
                        Spacer()
                        Picker(AppLocalization.text("single.region.label"), selection: $selectedRegionID) {
                            Text(AppLocalization.text("common.selectRegion")).tag(Optional<String>.none)
                            ForEach(regions) { region in
                                Text(region.name).tag(Optional(region.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .frame(minHeight: 56)

                    Divider().padding(.leading, 36)

                    HStack {
                        Label(AppLocalization.text("single.line.label"), systemImage: "tram.fill")
                            .font(.headline)
                            .foregroundStyle(SubwayTheme.ink)
                        Spacer()
                        Picker(AppLocalization.text("single.line.label"), selection: $selectedLineID) {
                            Text(AppLocalization.text("single.allLines")).tag(Optional<String>.none)
                            ForEach(lines) { line in
                                Text(line.name).tag(Optional(line.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .frame(minHeight: 56)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
                        .stroke(SubwayTheme.border, lineWidth: 1)
                }
                SubwayPanel(accent: SubwayTheme.border) {
                    VStack(spacing: 12) {
                    LabeledContent(
                        AppLocalization.text("single.myBestScore"),
                        value: AppLocalization.format("score.points.format", currentBest)
                    )
                    LabeledContent(
                        AppLocalization.text("settings.gameCenter.section"),
                        value: gameCenter.isAuthenticated
                            ? AppLocalization.text("gameCenter.signedIn")
                            : AppLocalization.text("gameCenter.signedOut")
                    )
                    }
                    .padding(18)
                }
                if let selectedRegion {
                    NavigationLink {
                        SinglePlayerChallengePlayView(
                            catalog: catalogStore.catalog,
                            region: selectedRegion,
                            challengeLine: selectedLine
                        )
                    } label: {
                        Label(AppLocalization.format("single.startChallenge.format", challengeName), systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(SubwayActionButtonStyle(color: SubwayTheme.action, prominent: true))
                }
                if gameCenter.isAuthenticated {
                    Button(AppLocalization.format("single.ranking.format", challengeName), systemImage: "list.number") {
                        gameCenter.showLeaderboard(id: leaderboardID)
                    }
                        .buttonStyle(SubwayActionButtonStyle(color: SubwayTheme.action, prominent: false))
                }
            }
            .padding(.horizontal, AppLayout.pageHorizontal)
            .padding(.vertical, AppLayout.pageVertical)
        }
        .scrollContentBackground(.hidden)
        .background(SubwayTheme.background.ignoresSafeArea())
        .navigationTitle(AppLocalization.text("tab.singlePlayer"))
        .toolbar {
            AppToolbar(
                showStats: $showStats,
                showSettings: $showSettings,
            )
        }
        .task {
            if selectedRegionID == nil { selectedRegionID = regions.first?.id }
        }
        .onChange(of: selectedRegionID) { _, _ in selectedLineID = nil }
    }

    private var regions: [Region] {
        catalogStore.catalog.regions.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedRegion: Region? {
        regions.first { $0.id == selectedRegionID }
    }

    private var lines: [Line] {
        selectedRegion.map { catalogStore.catalog.lines(in: $0) } ?? []
    }

    private var selectedLine: Line? {
        catalogStore.catalog.lineByID[selectedLineID ?? ""]
    }

    private var scopeID: String {
        selectedLineID.map { "line:\($0)" } ?? "region:\(selectedRegionID ?? "unknown")"
    }

    private var leaderboardID: String {
        GameCenterService.singlePlayerLeaderboardID(regionID: selectedRegionID ?? "unknown", lineID: selectedLineID)
    }

    private var challengeName: String {
        selectedLine?.name
            ?? selectedRegion.map { AppLocalization.format("single.regionAll.format", $0.name) }
            ?? AppLocalization.text("single.allLines")
    }

    private var pointsPerCorrectAnswer: Int {
        SinglePlayerQuestionFactory.pointsPerCorrectAnswer(
            catalog: catalogStore.catalog,
            lineID: selectedLineID
        )
    }

    private var scoreDescription: String {
        AppLocalization.format(
            "single.scoreDescription.format",
            pointsPerCorrectAnswer,
            pointsPerCorrectAnswer / 2
        )
    }

    private var currentBest: Int {
        bestRecords.first {
            $0.poolVersion == catalogStore.catalog.challengePoolVersion
                && $0.scopeID == scopeID
        }?.bestScore ?? 0
    }
}

struct SinglePlayerChallengePlayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query private var settings: [AppSettingsRecord]
    @StateObject private var session: SinglePlayerSession
    @State private var answer = ""
    @State private var feedback = ""
    @State private var feedbackKind = SinglePlayerFeedbackKind.neutral
    @State private var feedbackColor = Color.secondary
    @State private var didRecord = false
    @State private var resultStatus = SinglePlayerResultStatus.saving
    @State private var keyboardPresented = false
    @State private var isPreparing = true
    @State private var isStarting = false
    @State private var preparationCountdown = 3
    @State private var revealTask: Task<Void, Never>?
    @State private var timerTask: Task<Void, Never>?
    @State private var preparationTask: Task<Void, Never>?
    @State private var timeRemaining = SinglePlayerSession.roundDuration
    @State private var showStopConfirmation = false
    @FocusState private var focused: Bool
    let poolVersion: String
    let catalog: TransitCatalog
    let region: Region
    let challengeLine: Line?
    let scopeID: String
    let leaderboardID: String

    init(catalog: TransitCatalog, region: Region, challengeLine: Line? = nil) {
        self.catalog = catalog
        self.region = region
        self.challengeLine = challengeLine
        scopeID = challengeLine.map { "line:\($0.id)" } ?? "region:\(region.id)"
        leaderboardID = GameCenterService.singlePlayerLeaderboardID(regionID: region.id, lineID: challengeLine?.id)
        poolVersion = catalog.challengePoolVersion
        let points = SinglePlayerQuestionFactory.pointsPerCorrectAnswer(
            catalog: catalog,
            lineID: challengeLine?.id
        )
        _session = StateObject(wrappedValue: SinglePlayerSession(
            questions: SinglePlayerQuestionFactory.questions(
                catalog: catalog,
                regionID: region.id,
                lineID: challengeLine?.id
            ),
            pointsPerCorrectAnswer: points
        ))
    }

    var body: some View {
        ScrollView {
            if let question = session.current, let line = currentLine {
                VStack(spacing: 0) {
                    HStack {
                        LineIdentityLabel(line: line)
                        Spacer()
                        Text(AppLocalization.format("score.points.format", session.score))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(SubwayTheme.ink)
                        Spacer()
                        LivesView(lives: session.lives)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, layout.statusTop)

                    Text(AppLocalization.format(
                        "single.challengeTitle.format",
                        challengeLine?.name ?? AppLocalization.format("single.regionAll.format", region.name)
                    ))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, layout.contextTop)

                    HStack(spacing: 12) {
                        Label(
                            AppLocalization.format("time.secondsPrecise.format", timeRemaining),
                            systemImage: "timer"
                        )
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(timeRemaining <= 5 ? SubwayTheme.danger : SubwayTheme.ink)

                        ProgressView(
                            value: timeRemaining,
                            total: SinglePlayerSession.roundDuration
                        )
                        .tint(timeRemaining <= 5 ? SubwayTheme.danger : line.color)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, keyboardPresented ? 6 : 12)
                    .accessibilityElement(children: .combine)

                    NeighborStationSignView(
                        previous: question.previous,
                        next: question.next,
                        line: line,
                        compact: keyboardPresented
                    )
                    .padding(.top, layout.signTop)
                    .padding(.horizontal, AppLayout.pageHorizontal)

                    VStack(spacing: layout.promptSpacing) {
                        if session.hintVisible {
                            Text(session.hint)
                                .font(.title2.monospaced().bold())
                                .foregroundStyle(line.color)
                                .accessibilityLabel(AppLocalization.format("accessibility.initialHint.format", session.hint))
                        }
                        promptFeedbackView
                        answerField
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, layout.promptTop)
                    .padding(.bottom, layout.promptBottom)
                }
            } else {
                EmptyStateView(
                    title: AppLocalization.text("single.noQuestions.title"),
                    message: AppLocalization.text("single.noQuestions.message"),
                    symbol: "questionmark.folder"
                )
                    .padding()
            }
        }
        .blur(radius: showStopConfirmation ? 3 : 0)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .accessibilityHidden(isPreparing || showStopConfirmation)
        .background(SubwayTheme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationTitle(AppLocalization.text("single.challenge"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .tint(currentLine?.color ?? .accentColor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentStopConfirmation()
                } label: {
                    Label(
                        AppLocalization.text("single.stopChallenge"),
                        systemImage: "xmark.circle"
                    )
                }
                .disabled(isPreparing || session.isFinished)
                .accessibilityHint(AppLocalization.text("single.stopChallenge.hint"))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            updateKeyboardLayout(presented: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            updateKeyboardLayout(presented: false)
        }
        .onChange(of: session.isFinished) { _, finished in if finished { finish() } }
        .onDisappear {
            revealTask?.cancel()
            timerTask?.cancel()
            preparationTask?.cancel()
        }
        .overlay {
            if isPreparing {
                preparationOverlay
            } else if session.isFinished {
                resultOverlay
            } else if showStopConfirmation {
                stopConfirmationOverlay
            }
        }
    }

    private var currentLine: Line? {
        session.current.flatMap { catalog.lineByID[$0.lineID] }
    }

    private var layout: GamePlayLayoutMetrics {
        keyboardPresented ? .keyboardPresented : .regular
    }

    private var answerField: some View {
        TextField(AppLocalization.text("game.answer.placeholder"), text: $answer)
            .font(.title3)
            .padding(.horizontal, 20)
            .frame(minHeight: 72)
            .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
                    .stroke(focused ? (currentLine?.color ?? .accentColor) : SubwayTheme.border, lineWidth: focused ? 2 : 1)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .disabled(session.isRevealingIncorrectAnswer)
            .submitLabel(.next)
            .onSubmit(submit)
            .accessibilityLabel(AppLocalization.text("game.answer.placeholder"))
    }

    private var actionBar: some View {
        GameGlassActionBar(
            color: currentLine?.color ?? .accentColor,
            hintTitle: AppLocalization.text("game.initialHint"),
            hintDisabled: session.hintVisible || session.isFinished || session.isRevealingIncorrectAnswer,
            confirmDisabled: AnswerMatcher.normalize(answer).isEmpty || session.isFinished || session.isRevealingIncorrectAnswer,
            onHint: { session.useHint() },
            onConfirm: submit
        )
    }

    private var preparationOverlay: some View {
        ZStack {
            Rectangle()
                .fill(SubwayTheme.background)
                .overlay { Color.black.opacity(0.04) }
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(AppLocalization.text("single.preparation.eyebrow"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SubwayTheme.muted)

                Text(AppLocalization.text("single.preparation.title"))
                    .font(.title2.bold())
                    .foregroundStyle(SubwayTheme.ink)
                    .multilineTextAlignment(.center)

                Text(AppLocalization.text("single.preparation.message"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SubwayTheme.ink)

                if isStarting {
                    Text("\(preparationCountdown)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(SubwayTheme.ink)
                        .frame(width: 56, height: 44)
                        .background(currentLine?.color ?? SubwayTheme.action, in: Capsule())
                        .transition(.opacity)
                }

                Button(action: beginPreparation) {
                    Text(AppLocalization.text("single.preparation.start"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(
                            isStarting
                                ? Color.secondary
                                : (currentLine?.colorForeground ?? .black)
                        )
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            isStarting
                                ? Color.gray.opacity(0.28)
                                : (currentLine?.color ?? SubwayTheme.action),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
            }
            .padding(28)
            .frame(maxWidth: 342)
            .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous)
                    .stroke(currentLine?.color ?? SubwayTheme.action, lineWidth: 2)
            }
            .padding(.horizontal, AppLayout.pageHorizontal)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var stopConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(currentLine?.color ?? SubwayTheme.action)
                    .accessibilityHidden(true)

                Text(AppLocalization.text("single.stopConfirmation.title"))
                    .font(.title2.bold())
                    .foregroundStyle(SubwayTheme.ink)
                    .multilineTextAlignment(.center)

                Text(AppLocalization.text("single.stopConfirmation.message"))
                    .font(.body)
                    .foregroundStyle(SubwayTheme.muted)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        showStopConfirmation = false
                        restoreAnswerFocus()
                    } label: {
                        Text(AppLocalization.text("single.stopConfirmation.continue"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(SubwayActionButtonStyle(color: SubwayTheme.ink, prominent: false))

                    Button {
                        stopChallenge()
                    } label: {
                        Text(AppLocalization.text("single.stopConfirmation.stop"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(SubwayActionButtonStyle(color: SubwayTheme.danger, prominent: true))
                }
            }
            .padding(24)
            .frame(maxWidth: 342)
            .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous)
                    .stroke(currentLine?.color ?? SubwayTheme.action, lineWidth: 2)
            }
            .padding(.horizontal, AppLayout.pageHorizontal)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func presentStopConfirmation() {
        guard !isPreparing, !session.isFinished else { return }
        focused = false
        showStopConfirmation = true
    }

    private func stopChallenge() {
        revealTask?.cancel()
        timerTask?.cancel()
        preparationTask?.cancel()
        showStopConfirmation = false
        dismiss()
    }

    private func beginPreparation() {
        guard isPreparing, !isStarting else { return }
        isStarting = true
        preparationTask?.cancel()
        preparationTask = Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                preparationCountdown = value
                impact(.warning)
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            isPreparing = false
            isStarting = false
            preparationTask = nil
            startQuestionTimer()
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            focused = true
        }
    }

    private func submit() {
        let submittedQuestion = session.current
        let submittedLine = submittedQuestion.flatMap { catalog.lineByID[$0.lineID] }
        let result = session.submit(answer, remainingTime: timeRemaining)
        guard result != .ignored else { return }
        timerTask?.cancel()
        switch result {
        case .correct:
            feedback = AppLocalization.format(
                "game.correct.format",
                submittedQuestion?.target.name ?? AppLocalization.text("station.nameFallback")
            )
            feedbackKind = .correct
            feedbackColor = submittedLine?.color ?? .accentColor
            answer = ""
            impact(.success)
            startQuestionTimer()
        case .incorrect:
            revealIncorrectAnswer(submittedQuestion, timedOut: false)
        case .ignored: break
        }
        UIAccessibility.post(notification: .announcement, argument: feedback)
        if !session.isRevealingIncorrectAnswer { restoreAnswerFocus() }
    }

    private var promptFeedbackView: some View {
        Group {
            if feedback.isEmpty {
                Text(AppLocalization.text("game.stationQuestion"))
                    .font(.largeTitle.bold())
            } else {
                Text(feedback)
                    .font(feedbackKind == .correct ? .largeTitle.bold() : .title2.bold())
                    .foregroundStyle(feedbackColor)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .id(feedback)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .frame(minHeight: feedbackKind == .correct ? 56 : 30)
        .animation(reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.28), value: feedback)
    }

    private func impact(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard settings.first?.hapticsEnabled ?? true else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private func restoreAnswerFocus() {
        guard !session.isFinished, !session.isRevealingIncorrectAnswer else { return }
        Task { @MainActor in
            await Task.yield()
            focused = true
        }
    }

    private func updateKeyboardLayout(presented: Bool) {
        guard keyboardPresented != presented else { return }
        guard !reduceMotion else {
            keyboardPresented = presented
            return
        }
        withAnimation(.easeOut(duration: 0.25)) {
            keyboardPresented = presented
        }
    }

    private func startQuestionTimer() {
        timerTask?.cancel()
        guard session.current != nil, !session.isFinished, !session.isRevealingIncorrectAnswer else { return }
        timeRemaining = SinglePlayerSession.roundDuration
        let deadline = Date().addingTimeInterval(SinglePlayerSession.roundDuration)
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                timeRemaining = max(0, deadline.timeIntervalSinceNow)
                if timeRemaining <= 0 {
                    timeRemaining = 0
                    timeExpired()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func timeExpired() {
        let expiredQuestion = session.current
        guard session.expireCurrentQuestion() == .incorrect else { return }
        revealIncorrectAnswer(expiredQuestion, timedOut: true)
        UIAccessibility.post(notification: .announcement, argument: feedback)
    }

    private func revealIncorrectAnswer(_ question: SinglePlayerQuestion?, timedOut: Bool) {
        timerTask?.cancel()
        let targetName = question?.target.name ?? AppLocalization.text("station.nameFallback")
        feedback = timedOut
            ? AppLocalization.format("game.timeoutReveal.format", targetName)
            : AppLocalization.format("game.incorrectReveal.format", targetName)
        feedbackKind = .incorrect
        feedbackColor = .red
        answer = ""
        focused = false
        impact(.error)
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            guard !Task.isCancelled else { return }
            session.continueAfterIncorrectAnswer()
            feedback = ""
            if !session.isFinished {
                startQuestionTimer()
                restoreAnswerFocus()
            }
        }
    }

    private func finish() {
        guard !didRecord else { return }
        didRecord = true
        let update: ProgressStore.SinglePlayerRecordUpdate
        do {
            update = try ProgressStore.recordSinglePlayer(
                score: session.score,
                poolVersion: poolVersion,
                scopeID: scopeID,
                leaderboardID: leaderboardID,
                context: modelContext
            )
        } catch {
            resultStatus = .saveFailed
            return
        }

        guard update.didImproveBest else {
            resultStatus = session.score == 0 ? .zeroScore : .bestUnchanged
            return
        }
        guard gameCenter.isAuthenticated else {
            resultStatus = .waitingForGameCenter
            return
        }

        resultStatus = .submitting
        Task {
            if await gameCenter.submitSinglePlayer(score: update.record.bestScore, leaderboardID: leaderboardID) {
                update.record.pendingSubmission = false
                try? modelContext.save()
                resultStatus = .submitted
            } else {
                resultStatus = .submissionFailed
            }
        }
    }

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "trophy.fill").font(.system(size: 54)).foregroundStyle(SubwayTheme.action)
                Text(AppLocalization.text("single.result.title")).font(.title.bold())
                Text(AppLocalization.format("score.points.format", session.score)).font(.largeTitle.bold().monospacedDigit())
                Text(resultStatus.message)
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(AppLocalization.text("single.tryAgain"), systemImage: "arrow.clockwise") { restart() }
                    .buttonStyle(SubwayActionButtonStyle(color: currentLine?.color ?? SubwayTheme.action, prominent: true))
                    .frame(maxWidth: .infinity, minHeight: 52)
                Button(AppLocalization.text("common.finish"), systemImage: "checkmark") { dismiss() }
                    .buttonStyle(SubwayActionButtonStyle(color: currentLine?.color ?? SubwayTheme.action, prominent: false))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .padding(28)
            .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous)
                    .stroke(SubwayTheme.border, lineWidth: 1)
            }
            .padding()
        }
    }

    private func restart() {
        revealTask?.cancel()
        timerTask?.cancel()
        didRecord = false
        resultStatus = .saving
        answer = ""
        feedback = ""
        feedbackKind = .neutral
        session.restart()
        startQuestionTimer()
        restoreAnswerFocus()
    }
}

enum SinglePlayerResultStatus: Equatable {
    case saving
    case zeroScore
    case bestUnchanged
    case waitingForGameCenter
    case submitting
    case submitted
    case submissionFailed
    case saveFailed

    var message: String {
        switch self {
        case .saving: AppLocalization.text("single.result.saving")
        case .zeroScore: AppLocalization.text("single.result.zeroScore")
        case .bestUnchanged: AppLocalization.text("single.result.bestUnchanged")
        case .waitingForGameCenter: AppLocalization.text("single.result.waitingForGameCenter")
        case .submitting: AppLocalization.text("single.result.submitting")
        case .submitted: AppLocalization.text("single.result.submitted")
        case .submissionFailed: AppLocalization.text("single.result.submissionFailed")
        case .saveFailed: AppLocalization.text("single.result.saveFailed")
        }
    }
}

private enum SinglePlayerFeedbackKind {
    case neutral
    case correct
    case incorrect
}
