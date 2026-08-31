import SwiftData
import SwiftUI
import UIKit

struct WeeklyChallengeHomeView: View {
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query(sort: \WeeklyBestRecord.updatedAt, order: .reverse) private var bestRecords: [WeeklyBestRecord]
    @Binding var showSettings: Bool
    @Binding var showStats: Bool
    @State private var selectedRegionID: String?

    private var weekID: String { WeeklyChallengeFactory.weekID() }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text("어느 지역에 도전할까요?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("이전 역과 다음 역 사이의 역을 맞혀 보세요.\n힌트 없이 100점 · 힌트 사용 시 50점")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Label("도전 지역", systemImage: "map")
                        .font(.headline)
                    Spacer()
                    Picker("도전 지역", selection: $selectedRegionID) {
                        ForEach(regions) { region in
                            Text(region.name).tag(Optional(region.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 18)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                GroupBox {
                    LabeledContent("이번 주", value: weekID)
                    LabeledContent("내 최고 점수", value: "\(currentBest)점")
                    LabeledContent("Game Center", value: gameCenter.isAuthenticated ? "로그인됨" : "로그인 안 됨")
                }
                if let selectedRegion {
                    NavigationLink {
                        WeeklyChallengePlayView(catalog: catalogStore.catalog, weekID: weekID, region: selectedRegion)
                    } label: {
                        Label("\(selectedRegion.name) 도전 시작", systemImage: "play.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if gameCenter.isAuthenticated {
                    Button("주간 순위 보기", systemImage: "list.number") { gameCenter.showDashboard() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("싱글플레이")
        .toolbar { AppToolbar(showStats: $showStats, showSettings: $showSettings) }
        .task {
            if selectedRegionID == nil { selectedRegionID = regions.first?.id }
        }
    }

    private var regions: [Region] {
        catalogStore.catalog.regions.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedRegion: Region? {
        regions.first { $0.id == selectedRegionID }
    }

    private var currentBest: Int {
        bestRecords.first { $0.weekID == weekID && $0.poolVersion == catalogStore.catalog.challengePoolVersion }?.bestScore ?? 0
    }
}

struct WeeklyChallengePlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query private var settings: [AppSettingsRecord]
    @StateObject private var session: WeeklyChallengeSession
    @State private var answer = ""
    @State private var feedback = ""
    @State private var feedbackKind = WeeklyFeedbackKind.neutral
    @State private var feedbackColor = Color.secondary
    @State private var didRecord = false
    @State private var resultStatus = WeeklyResultStatus.saving
    @State private var keyboardPresented = false
    @FocusState private var focused: Bool
    let weekID: String
    let poolVersion: String
    let catalog: TransitCatalog
    let region: Region

    init(catalog: TransitCatalog, weekID: String, region: Region) {
        self.catalog = catalog
        self.weekID = weekID
        self.region = region
        poolVersion = catalog.challengePoolVersion
        _session = StateObject(wrappedValue: WeeklyChallengeSession(
            questions: WeeklyChallengeFactory.questions(catalog: catalog, weekID: weekID, regionID: region.id)
        ))
    }

    var body: some View {
        ScrollView {
            if let question = session.current, let line = currentLine {
                VStack(spacing: 0) {
                    HStack {
                        LineIdentityLabel(line: line)
                        Spacer()
                        Text("\(session.score)점")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        LivesView(lives: session.lives)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, layout.statusTop)

                    Text("\(region.name) 주간 도전")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, layout.contextTop)

                    NeighborStationSignView(
                        previous: question.previous,
                        next: question.next,
                        line: line,
                        compact: keyboardPresented
                    )
                    .padding(.top, layout.signTop)
                    .padding(.horizontal, 20)

                    VStack(spacing: layout.promptSpacing) {
                        Text("이 역의 이름은?")
                            .font(.largeTitle.bold())
                        if session.hintVisible {
                            Text(session.hint)
                                .font(.title2.monospaced().bold())
                                .foregroundStyle(line.color)
                                .accessibilityLabel("초성 힌트 \(session.hint)")
                        }
                        answerField
                        feedbackView
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, layout.promptTop)
                    .padding(.bottom, layout.promptBottom)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: keyboardPresented)
            } else {
                EmptyStateView(title: "출제할 역이 없어요", message: "노선 데이터를 확인해 주세요.", symbol: "questionmark.folder")
                    .padding()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .navigationTitle("주간 도전")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .tint(currentLine?.color ?? .accentColor)
        .task { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardPresented = false
        }
        .onChange(of: session.isFinished) { _, finished in if finished { finish() } }
        .overlay { if session.isFinished { resultOverlay } }
    }

    private var currentLine: Line? {
        session.current.flatMap { catalog.lineByID[$0.lineID] }
    }

    private var layout: GamePlayLayoutMetrics {
        keyboardPresented ? .keyboardPresented : .regular
    }

    private var answerField: some View {
        TextField("역 이름 입력", text: $answer)
            .font(.title3)
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(focused ? (currentLine?.color ?? .accentColor) : .secondary.opacity(0.22), lineWidth: focused ? 2 : 1)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .submitLabel(.next)
            .onSubmit(submit)
            .accessibilityLabel("역 이름 입력")
    }

    private var actionBar: some View {
        GameGlassActionBar(
            color: currentLine?.color ?? .accentColor,
            hintTitle: "초성 힌트",
            hintDisabled: session.hintVisible || session.isFinished,
            confirmDisabled: AnswerMatcher.normalize(answer).isEmpty || session.isFinished,
            onHint: { session.useHint() },
            onConfirm: submit
        )
    }

    private func submit() {
        let submittedQuestion = session.current
        let submittedLine = submittedQuestion.flatMap { catalog.lineByID[$0.lineID] }
        switch session.submit(answer) {
        case .correct:
            feedback = "\(submittedQuestion?.target.name ?? "역 이름"), 정답이에요!"
            feedbackKind = .correct
            feedbackColor = submittedLine?.color ?? .accentColor
            answer = ""
            impact(.success)
        case .incorrect:
            feedback = session.isFinished ? "목숨을 모두 사용했어요." : "아니에요. 목숨이 하나 줄었어요."
            feedbackKind = .incorrect
            feedbackColor = .red
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
        guard !session.isFinished else { return }
        Task { @MainActor in
            await Task.yield()
            focused = true
        }
    }

    private func finish() {
        guard !didRecord else { return }
        didRecord = true
        let update: ProgressStore.WeeklyRecordUpdate
        do {
            update = try ProgressStore.recordWeekly(score: session.score, weekID: weekID, poolVersion: poolVersion, context: modelContext)
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
            if await gameCenter.submitWeekly(score: update.record.bestScore) {
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
                Image(systemName: "trophy.fill").font(.system(size: 54)).foregroundStyle(.yellow)
                Text("이번 기록").font(.title.bold())
                Text("\(session.score)점").font(.largeTitle.bold().monospacedDigit())
                Text(resultStatus.message)
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28)).padding()
        }
    }
}

enum WeeklyResultStatus: Equatable {
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
        case .saving: "기록을 저장하는 중이에요."
        case .zeroScore: "이번 점수는 0점이라 Game Center에는 전송하지 않아요."
        case .bestUnchanged: "기기에 저장된 기존 최고 기록을 유지했어요."
        case .waitingForGameCenter: "최고 기록을 기기에 저장했어요. Game Center에 로그인하면 전송할게요."
        case .submitting: "최고 기록을 Game Center에 전송하는 중이에요."
        case .submitted: "최고 기록을 Game Center에 전송했어요."
        case .submissionFailed: "Game Center 전송에 실패했어요. 최고 기록은 기기에 저장되어 있어요."
        case .saveFailed: "기록을 기기에 저장하지 못했어요. 다시 도전해 주세요."
        }
    }
}

private enum WeeklyFeedbackKind {
    case neutral
    case correct
    case incorrect
}
