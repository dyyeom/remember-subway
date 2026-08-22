import SwiftData
import SwiftUI

struct WeeklyChallengeHomeView: View {
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query(sort: \WeeklyBestRecord.updatedAt, order: .reverse) private var bestRecords: [WeeklyBestRecord]
    @Binding var showSettings: Bool
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
                    LabeledContent("Game Center", value: gameCenter.isAuthenticated ? "연결됨" : "오프라인")
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
        .navigationTitle("주간 도전")
        .toolbar { SettingsButton(isPresented: $showSettings) }
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
    @EnvironmentObject private var gameCenter: GameCenterService
    @StateObject private var session: WeeklyChallengeSession
    @State private var answer = ""
    @State private var feedback = ""
    @State private var didRecord = false
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
                    .padding(.top, 12)

                    Text("\(region.name) 주간 도전")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 30)

                    WeeklyStationClueView(
                        previous: question.previous,
                        next: question.next,
                        line: line
                    )
                    .padding(.top, 34)

                    VStack(spacing: 20) {
                        Text("이 역의 이름은?")
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

private struct WeeklyStationClueView: View {
    let previous: Station
    let next: Station
    let line: Line

    var body: some View {
        ZStack {
            Capsule()
                .fill(line.color)
                .frame(height: 82)

            HStack(spacing: 8) {
                neighborLabel(title: "이전 역", station: previous, arrow: "chevron.left")

                VStack(spacing: 4) {
                    Text("현재 역")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("?")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(line.color)
                }
                .frame(width: 112, height: 112)
                .background(.background, in: Capsule())
                .overlay {
                    Capsule().stroke(line.color, lineWidth: 5)
                }

                neighborLabel(title: "다음 역", station: next, arrow: "chevron.right")
            }
            .padding(.horizontal, 12)
        }
        .frame(minHeight: 124)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("이전 역 \(previous.name), 다음 역 \(next.name). 두 역 사이의 현재 역을 맞혀 보세요.")
    }

    private func neighborLabel(title: String, station: Station, arrow: String) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: arrow)
                .font(.caption2.weight(.semibold))
            Text(station.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
        }
        .foregroundStyle(line.colorForeground)
        .frame(maxWidth: .infinity, minHeight: 72)
    }
}
