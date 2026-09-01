import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @State private var hintVisible = false
    @State private var completed = false
    @State private var message = "이전 역과 다음 역 사이의 역 이름을 입력해 보세요."
    @FocusState private var focused: Bool
    let onComplete: () -> Void

    private let line = Line(id: "tutorial-line", regionID: "tutorial", operatorID: "tutorial", name: "서울 1호선", shortName: "1", colorHex: "0052A4", sortOrder: 0)
    private let previous = Station(id: "tutorial-seoul", name: "서울역", fullName: nil, aliases: [])
    private let target = Station(id: "tutorial-cityhall", name: "시청", fullName: "시청(서울광장)", aliases: [])
    private let next = Station(id: "tutorial-jonggak", name: "종각", fullName: nil, aliases: [])

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("역순서에 오신 것을 환영해요").font(.title2.bold())
                    Text("두 역 사이에 있는 현재 역을 맞혀 보세요.").foregroundStyle(.secondary)
                    NeighborStationSignView(previous: previous, next: next, line: line)
                    Text("이 역의 이름은?").font(.largeTitle.bold())
                    if hintVisible {
                        Text(AnswerMatcher.initialConsonants(of: target.name))
                            .font(.title2.monospaced().bold())
                            .foregroundStyle(line.color)
                    }
                    TextField("역 이름 입력", text: $answer)
                        .font(.title3)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 64)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22))
                        .focused($focused)
                        .submitLabel(.done)
                        .disabled(completed)
                        .onSubmit(submit)
                    Text(message)
                        .font(completed ? .title2.bold() : .callout)
                        .foregroundStyle(completed ? line.color : .secondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, AppLayout.pageHorizontal)
                .padding(.vertical, AppLayout.pageVertical)
            }
            .safeAreaInset(edge: .bottom) {
                if completed {
                    Button("시작하기", systemImage: "arrow.right", action: onComplete)
                        .buttonStyle(.glassProminent)
                        .tint(line.color)
                        .controlSize(.large)
                        .padding()
                } else {
                    GameGlassActionBar(
                        color: line.color,
                        hintTitle: "초성 힌트",
                        hintDisabled: hintVisible,
                        confirmDisabled: AnswerMatcher.normalize(answer).isEmpty,
                        onHint: { hintVisible = true; message = "힌트를 쓰면 싱글 점수는 50점이에요." },
                        onConfirm: submit
                    )
                }
            }
            .navigationTitle("빠른 시작")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                }
            }
            .task { focused = true }
        }
    }

    private func submit() {
        if AnswerMatcher.matches(answer, station: target) {
            completed = true
            message = "시청, 정답이에요! 이제 준비됐어요."
            focused = false
        } else {
            message = "아니에요. 다시 생각해 보세요."
            focused = true
        }
    }
}
