import SwiftUI

struct TutorialView: View {
    @StateObject private var session: GameSession
    @State private var answer = ""
    @State private var message = "아래에 다음 역 이름을 입력해 보세요."
    @FocusState private var focused: Bool
    let onComplete: () -> Void
    private let tutorialLine = Line(
        id: "tutorial-line-1",
        regionID: "tutorial",
        operatorID: "tutorial",
        name: "서울 1호선",
        shortName: "1",
        colorHex: "0052A4",
        sortOrder: 0
    )

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let stations = [
            Station(id: "tutorial-start", name: "서울역", fullName: nil, aliases: ["서울"]),
            Station(id: "tutorial-cityhall", name: "시청", fullName: "시청(서울광장)", aliases: []),
            Station(id: "tutorial-jonggak", name: "종각", fullName: nil, aliases: [])
        ]
        let segment = Segment(id: "tutorial", routePatternID: "tutorial", index: 0, stationIDs: stations.map(\.id))
        _session = StateObject(wrappedValue: GameSession(segment: segment, stationByID: Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) }), reverse: false))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        LineIdentityLabel(line: tutorialLine)
                        Spacer()
                        LivesView(lives: session.lives)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    VStack(spacing: 8) {
                        Text("역순서에 오신 것을 환영해요")
                            .font(.title2.bold())
                        Text("출발역 다음에 오는 역을 한 칸씩 맞혀 보세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 26)

                    StationSignView(
                        station: previousStation,
                        stationCode: tutorialStationCode,
                        line: tutorialLine
                    )
                    .padding(.top, 30)

                    VStack(spacing: 20) {
                        Text("다음 역은?")
                            .font(.largeTitle.bold())

                        if session.hintUsedForCurrentStation {
                            Text(session.hint ?? "")
                                .font(.title2.monospaced().bold())
                                .foregroundStyle(tutorialLine.color)
                        }

                        TextField("역 이름 입력", text: $answer)
                            .font(.title3)
                            .padding(.horizontal, 20)
                            .frame(minHeight: 64)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(focused ? tutorialLine.color : .secondary.opacity(0.22), lineWidth: focused ? 2 : 1)
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(submit)

                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 42)
                    .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { tutorialActionBar }
            .task { focused = true }
            .navigationTitle("빠른 시작")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .tint(tutorialLine.color)
        }
        .interactiveDismissDisabled()
    }

    private var previousStation: Station {
        session.stations[max(0, session.currentIndex - 1)]
    }

    private var tutorialStationCode: String {
        ["tutorial-start": "133", "tutorial-cityhall": "132", "tutorial-jonggak": "131"][previousStation.id] ?? "1"
    }

    @ViewBuilder private var tutorialActionBar: some View {
        if case .completed = session.outcome {
            Button("노선 고르기", systemImage: "arrow.right", action: onComplete)
                .buttonStyle(.glassProminent)
                .tint(tutorialLine.color)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        } else {
            GameGlassActionBar(
                color: tutorialLine.color,
                hintTitle: "초성 힌트",
                hintDisabled: session.hintUsedForCurrentStation,
                confirmDisabled: AnswerMatcher.normalize(answer).isEmpty,
                onHint: {
                    session.useHint()
                    message = "힌트를 쓰면 완료 별점이 하나 줄어요."
                },
                onConfirm: submit
            )
        }
    }

    private func submit() {
        switch session.submit(answer) {
        case .correct: answer = ""; message = session.outcome == .playing ? "좋아요! 다음 역도 맞혀 보세요." : "준비됐어요!"
        case .incorrect: message = "오답이면 목숨이 하나 줄어요. 같은 역을 다시 입력해 보세요."
        case .ignored: break
        }
    }
}
