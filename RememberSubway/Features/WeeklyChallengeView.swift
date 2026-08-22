import SwiftData
import SwiftUI

struct WeeklyChallengeHomeView: View {
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query(sort: \WeeklyBestRecord.updatedAt, order: .reverse) private var bestRecords: [WeeklyBestRecord]
    @Binding var showSettings: Bool

    private var weekID: String { WeeklyChallengeFactory.weekID() }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text("3개의 목숨으로 얼마나 멀리 갈 수 있을까요?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("전국의 인접한 역이 매주 같은 순서로 출제됩니다.\n힌트 없이 100점 · 힌트 사용 시 50점")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                GroupBox {
                    LabeledContent("이번 주", value: weekID)
                    LabeledContent("내 최고 점수", value: "\(currentBest)점")
                    LabeledContent("Game Center", value: gameCenter.isAuthenticated ? "연결됨" : "오프라인")
                }
                NavigationLink {
                    WeeklyChallengePlayView(catalog: catalogStore.catalog, weekID: weekID)
                } label: {
                    Label("도전 시작", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                if gameCenter.isAuthenticated {
                    Button("주간 순위 보기", systemImage: "list.number") { gameCenter.showDashboard() }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("주간 도전")
        .toolbar { SettingsButton(isPresented: $showSettings) }
    }

    private var currentBest: Int {
        bestRecords.first { $0.weekID == weekID && $0.poolVersion == catalogStore.catalog.challengePoolVersion }?.bestScore ?? 0
    }
}

struct WeeklyChallengePlayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var gameCenter: GameCenterService
    @StateObject private var session: WeeklyChallengeSession
    @State private var answer = ""
    @State private var feedback = ""
    @State private var didRecord = false
    @FocusState private var focused: Bool
    let weekID: String
    let poolVersion: String
    let catalog: TransitCatalog

    init(catalog: TransitCatalog, weekID: String) {
        self.catalog = catalog
        self.weekID = weekID
        poolVersion = catalog.challengePoolVersion
        _session = StateObject(wrappedValue: WeeklyChallengeSession(questions: WeeklyChallengeFactory.questions(catalog: catalog, weekID: weekID)))
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
                    .padding(.top, 12)

                    Text("전국 주간 도전")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)

                    StationSignView(
                        station: question.anchor,
                        stationCode: currentStationCode,
                        line: line
                    )
                    .padding(.top, 34)

                    VStack(spacing: 20) {
                        Text("다음 역은?")
                            .font(.largeTitle.bold())
                        if session.hintVisible {
                            Text(session.hint)
                                .font(.title2.monospaced().bold())
                                .foregroundStyle(line.color)
                                .accessibilityLabel("초성 힌트 \(session.hint)")
                        }
                        answerField
                        Text(feedback)
                            .font(.callout)
                            .foregroundStyle(feedback.contains("아니") ? .red : .secondary)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 30)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 32)
                }
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
        .onChange(of: session.isFinished) { _, finished in if finished { finish() } }
        .overlay { if session.isFinished { resultOverlay } }
    }

    private var currentLine: Line? {
        session.current.flatMap { catalog.lineByID[$0.lineID] }
    }

    private var currentPattern: RoutePattern? {
        guard let id = session.current?.routePatternID else { return nil }
        return catalog.routePatterns.first { $0.id == id }
    }

    private var currentStationCode: String {
        guard let question = session.current, let line = currentLine else { return "" }
        return currentPattern?.stationCode(for: question.anchor.id, fallback: line.shortName) ?? line.shortName
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
            .submitLabel(.done)
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
        switch session.submit(answer) {
        case .correct: answer = ""; feedback = "정답!"
        case .incorrect: feedback = session.isFinished ? "도전 종료" : "아니에요. 목숨이 하나 줄었어요."
        case .ignored: break
        }
    }

    private func finish() {
        guard !didRecord else { return }
        didRecord = true
        guard let record = try? ProgressStore.recordWeekly(score: session.score, weekID: weekID, poolVersion: poolVersion, context: modelContext), record.pendingSubmission else { return }
        Task {
            if await gameCenter.submitWeekly(score: record.bestScore) {
                record.pendingSubmission = false
                try? modelContext.save()
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
                Text(gameCenter.isAuthenticated ? "최고 기록을 Game Center에 전송했어요." : "기록을 저장했어요. 연결되면 전송할게요.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28)).padding()
        }
    }
}
