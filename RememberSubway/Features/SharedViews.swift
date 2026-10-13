import SwiftUI

enum AppLayout {
    static let pageHorizontal: CGFloat = 24
    static let pageVertical: CGFloat = 20
}

/// Shared visual tokens translated from the subway-themed Figma library.
/// Keep layout decisions in SwiftUI while centralising the visual language here.
enum SubwayTheme {
    static let pageHorizontal: CGFloat = 24
    static let stationCornerRadius: CGFloat = 28
    static let controlCornerRadius: CGFloat = 20
    static let pillCornerRadius: CGFloat = 32
    static let controlHeight: CGFloat = 56
    /// 지역·노선 선택 카드의 좌우 안쪽 여백. 노선 칩 줄은 이만큼 바깥으로 넓혀 카드 가장자리까지 스크롤된다.
    static let selectionCardInset: CGFloat = 16
    static let stationSurface = Color("SubwayStationSurface")
    static let background = Color("SubwayBackground")
    static let ink = Color("SubwayInk")
    static let muted = Color("SubwayMuted")
    static let border = Color("SubwayBorder")
    static let action = Color("SubwayAction")
    static let danger = Color("SubwayDanger")
    /// '전체 노선'을 나타내는 강조색(딥 틸 #124A50). 이 색 위 글자는 흰색.
    static let allLines = Color("SubwayAllLines")
}

/// 화면 전체 강조색. 선택한 노선(없으면 '전체 노선' 딥 틸)에서 한 번만 계산해 환경값으로 내려보낸다.
struct SubwayAccent: Equatable {
    /// 채움·테두리에 쓰는 원래 색.
    let color: Color
    /// `color`로 채운 면 위의 글자·아이콘 색.
    let foreground: Color
    /// 흰 표면 위 글자·아이콘·시스템 tint용 색. 밝은 노선은 읽히도록 어둡게 낮춘다.
    let emphasis: Color

    static let allLines = SubwayAccent(color: SubwayTheme.allLines, foreground: .white, emphasis: SubwayTheme.allLines)

    init(color: Color, foreground: Color, emphasis: Color) {
        self.color = color
        self.foreground = foreground
        self.emphasis = emphasis
    }

    /// 특정 노선이면 그 노선 색, `nil`(전체 노선·미선택)이면 딥 틸.
    init(line: Line?) {
        guard let line else {
            self = .allLines
            return
        }
        let isBright = line.colorForeground == .black
        self.init(
            color: line.color,
            foreground: line.colorForeground,
            emphasis: isBright ? line.color.scaledBrightness(0.55) : line.color
        )
    }
}

extension EnvironmentValues {
    @Entry var subwayAccent: SubwayAccent = .allLines
}

extension View {
    /// 강조색을 하위 컴포넌트(환경값)와 시스템 컨트롤(`tint`)에 함께 적용한다.
    func subwayAccent(_ accent: SubwayAccent) -> some View {
        environment(\.subwayAccent, accent)
            .tint(accent.emphasis)
    }

    /// 이 뷰를 화면 강조색 테두리의 `SubwayPanel`로 감싼다.
    func subwayPanelBackground() -> some View {
        SubwayPanel(accented: true) { self }
    }

    /// 선택이 바뀔 때 강조색을 부드럽게 전환하고 가벼운 햅틱을 준다. Reduce Motion이면 즉시 바꾼다.
    func animatedSubwayAccent(_ accent: SubwayAccent, hapticsEnabled: Bool) -> some View {
        modifier(AnimatedSubwayAccentModifier(target: accent, hapticsEnabled: hapticsEnabled))
    }
}

/// 탭 바 tint가 각 탭의 현재 강조색을 따라가도록 홈 화면이 올려 보내는 값.
struct SubwayTabAccentPreferenceKey: PreferenceKey {
    static let defaultValue: SubwayAccent? = nil
    static func reduce(value: inout SubwayAccent?, nextValue: () -> SubwayAccent?) {
        value = value ?? nextValue()
    }
}

private struct AnimatedSubwayAccentModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: SubwayAccent?
    let target: SubwayAccent
    let hapticsEnabled: Bool

    func body(content: Content) -> some View {
        let current = displayed ?? target
        content
            .subwayAccent(current)
            .preference(key: SubwayTabAccentPreferenceKey.self, value: current)
            .onAppear { displayed = target }
            .onChange(of: target) { _, newValue in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    displayed = newValue
                }
            }
            .sensoryFeedback(.selection, trigger: target) { _, _ in hapticsEnabled }
    }
}

struct SubwayPanel<Content: View>: View {
    @Environment(\.subwayAccent) private var subwayAccent
    private let accent: Color?
    @ViewBuilder let content: () -> Content

    init(accent: Color = SubwayTheme.border, @ViewBuilder content: @escaping () -> Content) {
        self.accent = accent
        self.content = content
    }

    /// 화면 강조색(`subwayAccent`) 테두리를 쓰는 패널.
    init(accented: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.accent = accented ? nil : SubwayTheme.border
        self.content = content
    }

    var body: some View {
        let stroke = accent ?? subwayAccent.color
        content()
            .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
                    .stroke(stroke.opacity(0.9), lineWidth: stroke == SubwayTheme.border ? 1 : 2)
            }
    }
}

/// Full-width action button. `minHeight` is the minimum height of the whole button,
/// padding included, so callers should not add their own height or width frames.
struct SubwayActionButtonStyle: ButtonStyle {
    /// `nil`이면 화면 강조색(`subwayAccent`)을 따른다.
    var color: Color? = nil
    let prominent: Bool
    var minHeight: CGFloat = 52
    /// false면 비활성이어도 흐리게 만들지 않는다. 공개된 초성처럼 읽혀야 하는 값에 쓴다.
    var dimsWhenDisabled = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.subwayAccent) private var subwayAccent

    func makeBody(configuration: Configuration) -> some View {
        let fill = color ?? subwayAccent.color
        let fillForeground = color.map(\.subwayForeground) ?? subwayAccent.foreground
        return configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? fillForeground : SubwayTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(
                prominent ? fill : SubwayTheme.stationSurface,
                in: RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
                    .stroke(fill, lineWidth: prominent ? 2 : 1.5)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : (dimsWhenDisabled ? 0.42 : 1))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SubwayHomeHeader: View {
    @Environment(\.subwayAccent) private var accent
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent.emphasis)
                .frame(width: 52, height: 52)
                .background(accent.color.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(SubwayTheme.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(SubwayTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SubwayTheme.stationCornerRadius, style: .continuous)
                .stroke(accent.color, lineWidth: 2)
        }
    }
}

struct GamePlayLayoutMetrics: Equatable {
    let statusTop: CGFloat
    let contextTop: CGFloat
    let signTop: CGFloat
    let promptTop: CGFloat
    let promptSpacing: CGFloat
    let promptBottom: CGFloat

    static let regular = GamePlayLayoutMetrics(
        statusTop: 12,
        contextTop: 30,
        signTop: 34,
        promptTop: 48,
        promptSpacing: 20,
        promptBottom: 32
    )

    static let keyboardPresented = GamePlayLayoutMetrics(
        statusTop: 4,
        contextTop: 8,
        signTop: 8,
        promptTop: 12,
        promptSpacing: 10,
        promptBottom: 8
    )

    var totalVerticalSpacing: CGFloat {
        statusTop + contextTop + signTop + promptTop + promptSpacing * 2 + promptBottom
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue: UInt64
        if cleaned.count == 6 {
            (red, green, blue) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        } else {
            (red, green, blue) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }

    /// 휘도 0.56 기준으로 이 색 위에 올릴 글자색(흑/백).
    var subwayForeground: Color {
        let resolved = resolve(in: EnvironmentValues())
        return Self.subwayForeground(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
    }

    static func subwayForeground(red: Double, green: Double, blue: Double) -> Color {
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.56 ? .black : .white
    }

    /// RGB 채널을 같은 비율로 낮춰 색상은 유지하고 밝기만 줄인다.
    func scaledBrightness(_ factor: Double) -> Color {
        let resolved = resolve(in: EnvironmentValues())
        return Color(
            .sRGB,
            red: Double(resolved.red) * factor,
            green: Double(resolved.green) * factor,
            blue: Double(resolved.blue) * factor,
            opacity: Double(resolved.opacity)
        )
    }
}

extension Line {
    var color: Color { Color(hex: colorHex) }

    var colorForeground: Color {
        let cleaned = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return .white }
        let red = Double(value >> 16) / 255
        let green = Double(value >> 8 & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color.subwayForeground(red: red, green: green, blue: blue)
    }
}

struct LivesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lives: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                BreakingHeartView(isAlive: index < lives, reduceMotion: reduceMotion)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.format("accessibility.lives.format", lives))
    }
}

private struct BreakingHeartView: View {
    let isAlive: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Image(systemName: "heart")
                .foregroundStyle(.secondary)
                .opacity(isAlive ? 0 : 1)

            heartHalf(alignment: .leading, direction: -1)
            heartHalf(alignment: .trailing, direction: 1)
        }
        .frame(width: 22, height: 22)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.46), value: isAlive)
    }

    private func heartHalf(alignment: Alignment, direction: CGFloat) -> some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(SubwayTheme.danger)
            .frame(width: 22, height: 22)
            .mask {
                Rectangle()
                    .frame(width: 11, height: 22)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
            .rotationEffect(.degrees(isAlive ? 0 : Double(direction * 18)))
            .offset(
                x: isAlive ? 0 : direction * 7,
                y: isAlive ? 0 : 6
            )
            .opacity(isAlive ? 1 : 0)
            .scaleEffect(isAlive ? 1 : 0.82)
    }
}

struct LineIdentityLabel: View {
    let line: Line

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(line.color)
                .frame(width: 24, height: 24)
                .overlay {
                    Text(line.shortName)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(line.colorForeground)
                }
            Text(line.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SubwayTheme.ink)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(SubwayTheme.stationSurface, in: Capsule())
        .overlay { Capsule().stroke(line.color, lineWidth: 2) }
        .accessibilityElement(children: .combine)
    }
}

struct NeighborStationSignView: View {
    let previous: Station?
    let next: Station?
    let line: Line
    var compact = false
    /// 카운트다운 중처럼 문제를 아직 공개하면 안 될 때 이전·다음 역 이름을 자리 표시로 가린다.
    var concealed = false

    var body: some View {
        let centerWidth: CGFloat = 204
        let signHeight: CGFloat = 84

        ZStack {
            GeometryReader { proxy in
                let sideWidth = max(0, (proxy.size.width - centerWidth) / 2)

                HStack(spacing: 0) {
                    neighborPanel(
                        station: previous,
                        arrow: "chevron.left"
                    )
                    .frame(width: sideWidth)

                    Color.clear.frame(width: centerWidth)

                    neighborPanel(
                        station: next,
                        arrow: "chevron.right"
                    )
                    .frame(width: sideWidth)
                }
            }
            .frame(height: 48)
            .background(line.color, in: Capsule())

            currentPanel
                .frame(width: centerWidth, height: signHeight)
        }
        .frame(maxWidth: .infinity, minHeight: signHeight, maxHeight: signHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard !concealed else { return AppLocalization.text("accessibility.stationQuestion.concealed") }
        return AppLocalization.format(
            "accessibility.stationQuestion.format",
            previous?.name ?? AppLocalization.text("station.previous.none"),
            next?.name ?? AppLocalization.text("station.next.none")
        )
    }

    private var currentPanel: some View {
        Circle()
            .fill(line.color)
            .frame(width: 42, height: 42)
            .overlay {
                Text("?")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(line.colorForeground)
            }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(SubwayTheme.stationSurface, in: Capsule())
        .overlay {
            Capsule().stroke(line.color, lineWidth: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.text("station.current"))
    }

    private func neighborPanel(station: Station?, arrow: String) -> some View {
        let fallback = arrow == "chevron.left"
            ? AppLocalization.text("station.previous.none")
            : AppLocalization.text("station.next.none")

        return VStack(spacing: 5) {
            Image(systemName: arrow)
                .font(.system(size: 15, weight: .bold))

            if concealed {
                Capsule()
                    .fill(line.colorForeground.opacity(0.35))
                    .frame(width: 52, height: 12)
                    .frame(height: 20)
            } else {
                Text(station?.name ?? fallback)
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
            }
        }
        .foregroundStyle(line.colorForeground)
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.horizontal, 5)
        .accessibilityHidden(true)
    }
}

struct GameGlassActionBar: View {
    let color: Color
    let hintTitle: String
    let hintText: String?
    let hintDisabled: Bool
    let confirmDisabled: Bool
    let onHint: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        SubwayPanel(accent: color) {
            HStack(spacing: 12) {
                hintButton
                    .buttonStyle(SubwayActionButtonStyle(color: color, prominent: false, dimsWhenDisabled: hintText == nil))
                    .disabled(hintDisabled)

                Button(AppLocalization.text("game.checkAnswer"), systemImage: "checkmark.circle", action: onConfirm)
                    .buttonStyle(SubwayActionButtonStyle(color: color, prominent: true))
                    .disabled(confirmDisabled)
            }
            .padding(12)
        }
        .controlSize(.large)
        .padding(.horizontal, AppLayout.pageHorizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var hintButton: some View {
        if let hintText {
            Button(hintText, action: onHint)
                .accessibilityLabel(AppLocalization.format("accessibility.initialHint.format", hintText))
        } else {
            Button(hintTitle, systemImage: "lightbulb", action: onHint)
        }
    }
}

// MARK: - 지역 세그먼트

/// 지역 5칸 세그먼트. 시스템 `.segmented`는 iOS 26에서 글래스 재질이 될 수 있어 직접 그린다.
/// 40pt 캡슐 트랙 안에서 선택 칸만 흰 바탕 + 강조색 1.5pt 테두리. 각 칸의 터치 영역은 44pt 이상.
struct RegionSegmentedControl: View {
    @Environment(\.subwayAccent) private var accent
    let title: String
    let regions: [Region]
    @Binding var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(regions) { region in
                segment(region)
            }
        }
        .padding(.horizontal, 4)
        .background {
            // 트랙은 터치 영역(44pt)보다 위아래 2pt씩 작은 40pt.
            Capsule()
                .fill(SubwayTheme.background)
                .overlay { Capsule().stroke(SubwayTheme.border, lineWidth: 1) }
                .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func segment(_ region: Region) -> some View {
        let isSelected = region.id == selection
        return Button {
            selection = region.id
        } label: {
            Text(region.name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? accent.emphasis : SubwayTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(SubwayTheme.stationSurface)
                            .overlay { Capsule().stroke(accent.color, lineWidth: 1.5) }
                    }
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(region.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 노선 칩

/// 제목 행("도전 노선" + "N개 노선") 아래에 노선 칩을 가로로 늘어놓는 선택 UI.
/// `includesAllLines`면 맨 앞에 `전체` 칩이 붙고, 이때 `selection == nil`이 `전체`다.
struct LineChipPicker<Title: View>: View {
    @Environment(\.subwayAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lines: [Line]
    @Binding var selection: String?
    var includesAllLines = false
    /// 값이 바뀌면(지역 변경) 칩 줄을 처음으로 되돌린다.
    var scrollResetKey: String?
    /// 첫 실행 코치마크 표시 여부. 사용자가 칩을 고르거나 ✕를 누르면 false가 된다.
    var showsCoachmark: Binding<Bool> = .constant(false)
    @ViewBuilder let title: () -> Title

    private static var cardInset: CGFloat { SubwayTheme.selectionCardInset }
    private static var allLinesID: String { "__all_lines__" }
    /// 칩 줄 전체(앞 여백 포함)의 ID. 처음 위치로 되돌릴 때 쓴다.
    private static var rowStartID: String { "__line_chip_row__" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chipRow
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                title()
                    .opacity(showsCoachmark.wrappedValue ? 0 : 1)
                    .accessibilityHidden(showsCoachmark.wrappedValue)
                if showsCoachmark.wrappedValue {
                    LineChipCoachmarkBubble(
                        message: AppLocalization.text("single.coachmark.lineChips"),
                        dismiss: dismissCoachmark
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            Text(lineCountText)
                .font(.footnote)
                .foregroundStyle(SubwayTheme.muted)
                .fixedSize()
        }
    }

    private var lineCountText: String {
        lines.count == 1
            ? AppLocalization.text("home.lineCount.one")
            : AppLocalization.format("home.lineCount.format", lines.count)
    }

    private var chipRow: some View {
        ScrollViewReader { proxy in
            FadingHorizontalScrollView {
                HStack(spacing: 8) {
                    if includesAllLines {
                        LineChip(line: nil, isSelected: selection == nil) { select(nil) }
                            .id(Self.allLinesID)
                    }
                    ForEach(lines) { line in
                        LineChip(line: line, isSelected: selection == line.id) { select(line.id) }
                            .id(line.id)
                    }
                }
                .padding(.horizontal, Self.cardInset)
                .padding(.vertical, 1)
                .id(Self.rowStartID)
            }
            .padding(.horizontal, -Self.cardInset)
            .background {
                if showsCoachmark.wrappedValue {
                    CoachmarkPulseRing(color: accent.color)
                        .padding(.horizontal, -Self.cardInset + 6)
                        .padding(.vertical, -4)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                Task { @MainActor in scrollToSelection(proxy) }
            }
            .onChange(of: selection) { _, _ in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    scrollToSelection(proxy)
                }
            }
            .onChange(of: scrollResetKey) { _, _ in
                Task { @MainActor in proxy.scrollTo(Self.rowStartID, anchor: .leading) }
            }
        }
    }

    /// 선택 칩을 가운데로. 첫 칩은 가운데 정렬 시 앞 여백이 밀리지 않도록 처음 위치로 둔다.
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = selectedChipID else { return }
        if id == firstChipID {
            proxy.scrollTo(Self.rowStartID, anchor: .leading)
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private var selectedChipID: String? {
        selection ?? (includesAllLines ? Self.allLinesID : nil)
    }

    private var firstChipID: String? {
        includesAllLines ? Self.allLinesID : lines.first?.id
    }

    private func select(_ id: String?) {
        if showsCoachmark.wrappedValue { dismissCoachmark() }
        selection = id
    }

    private func dismissCoachmark() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            showsCoachmark.wrappedValue = false
        }
    }
}

/// 노선 칩 하나. `line == nil`이면 딥 틸 `전체` 칩.
private struct LineChip: View {
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 24
    let line: Line?
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { line?.color ?? SubwayTheme.allLines }
    private var fillForeground: Color { line?.colorForeground ?? .white }
    /// 흰 원 위 약칭 색. 밝은 노선은 강조색 규칙대로 어둡게 낮춘다.
    private var badgeEmphasis: Color { SubwayAccent(line: line).emphasis }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                badge
                Text(line?.chipName ?? AppLocalization.text("single.allLines.short"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? fillForeground : SubwayTheme.ink)
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(isSelected ? color : SubwayTheme.stationSurface, in: Capsule())
            .overlay {
                if !isSelected {
                    Capsule().stroke(SubwayTheme.border, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(LineChipButtonStyle())
        .accessibilityLabel(line?.name ?? AppLocalization.text("single.allLines"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var badge: some View {
        Circle()
            .fill(isSelected ? Color.white : color)
            .frame(width: badgeSize, height: badgeSize)
            .overlay {
                Group {
                    if let line {
                        Text(line.shortName)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 2)
                    } else {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(isSelected ? badgeEmphasis : fillForeground)
            }
            .accessibilityHidden(true)
    }
}

private struct LineChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 가로 스크롤 뷰. 더 스크롤할 내용이 있는 쪽 가장자리만 40pt 페이드로 흐린다.
private struct FadingHorizontalScrollView<Content: View>: View {
    private struct EdgeOverflow: Equatable {
        var leading = false
        var trailing = false
    }

    @State private var overflow = EdgeOverflow()
    @ViewBuilder let content: () -> Content
    private let fadeWidth: CGFloat = 40

    var body: some View {
        ScrollView(.horizontal) {
            content()
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: EdgeOverflow.self) { geometry in
            let offset = geometry.contentOffset.x + geometry.contentInsets.leading
            let maxOffset = geometry.contentSize.width + geometry.contentInsets.leading + geometry.contentInsets.trailing
                - geometry.containerSize.width
            return EdgeOverflow(leading: offset > 1, trailing: maxOffset - offset > 1)
        } action: { _, newValue in
            withAnimation(.easeOut(duration: 0.15)) { overflow = newValue }
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(overflow.leading ? 0 : 1), .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                Color.black
                LinearGradient(
                    colors: [.black, .black.opacity(overflow.trailing ? 0 : 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
            }
        }
    }
}

// MARK: - 첫 실행 코치마크

/// 딥 틸 캡슐 말풍선 + ✕(44pt) + 칩 줄을 가리키는 꼬리. 화면을 막지 않는다.
private struct LineChipCoachmarkBubble: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16)
                .padding(.vertical, 4)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.text("common.close"))
        }
        .frame(minHeight: 44)
        .background(SubwayTheme.allLines, in: Capsule())
        .overlay(alignment: .bottomLeading) {
            CoachmarkTail()
                .fill(SubwayTheme.allLines)
                .frame(width: 14, height: 7)
                .offset(x: 34, y: 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
    }
}

private struct CoachmarkTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 칩 줄 뒤의 8% 틴트 + 35% 2pt 링. 1.2초 주기로 은은하게 펄스하고, Reduce Motion이면 멈춰 있다.
private struct CoachmarkPulseRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    let color: Color

    var body: some View {
        Capsule()
            .fill(color.opacity(0.08))
            .overlay { Capsule().stroke(color.opacity(0.35), lineWidth: 2) }
            .opacity(reduceMotion ? 1 : (dimmed ? 0.35 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

struct CelebrationFireworksView: View {
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
