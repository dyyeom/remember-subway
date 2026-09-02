import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @State private var hintVisible = false
    @State private var completed = false
    @State private var message = AppLocalization.text("tutorial.instruction")
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
                    Text(AppLocalization.text("tutorial.welcome")).font(.title2.bold())
                    Text(AppLocalization.text("tutorial.description")).foregroundStyle(.secondary)
                    NeighborStationSignView(previous: previous, next: next, line: line)
                    Text(AppLocalization.text("game.stationQuestion")).font(.largeTitle.bold())
                    if hintVisible {
                        Text(AnswerMatcher.initialConsonants(of: target.name))
                            .font(.title2.monospaced().bold())
                            .foregroundStyle(line.color)
                    }
                    TextField(AppLocalization.text("game.answer.placeholder"), text: $answer)
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
                    Button(AppLocalization.text("tutorial.getStarted"), systemImage: "arrow.right", action: onComplete)
                        .buttonStyle(.glassProminent)
                        .tint(line.color)
                        .controlSize(.large)
                        .padding()
                } else {
                    GameGlassActionBar(
                        color: line.color,
                        hintTitle: AppLocalization.text("game.initialHint"),
                        hintDisabled: hintVisible,
                        confirmDisabled: AnswerMatcher.normalize(answer).isEmpty,
                        onHint: { hintVisible = true; message = AppLocalization.text("tutorial.hintMessage") },
                        onConfirm: submit
                    )
                }
            }
            .navigationTitle(AppLocalization.text("tutorial.quickStart"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.text("common.close"), systemImage: "xmark") { dismiss() }
                }
            }
            .task { focused = true }
        }
    }

    private func submit() {
        if AnswerMatcher.matches(answer, station: target) {
            completed = true
            message = AppLocalization.format("tutorial.correct.format", target.name)
            focused = false
        } else {
            message = AppLocalization.text("game.incorrectTryAgain")
            focused = true
        }
    }
}
