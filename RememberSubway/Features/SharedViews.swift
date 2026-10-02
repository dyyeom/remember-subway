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
    static let stationSurface = Color("SubwayStationSurface")
    static let background = Color("SubwayBackground")
    static let ink = Color("SubwayInk")
    static let muted = Color("SubwayMuted")
    static let border = Color("SubwayBorder")
    static let action = Color("SubwayAction")
    static let danger = Color("SubwayDanger")
}

struct SubwayPanel<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: () -> Content

    init(accent: Color = SubwayTheme.border, @ViewBuilder content: @escaping () -> Content) {
        self.accent = accent
        self.content = content
    }

    var body: some View {
        content()
            .background(SubwayTheme.stationSurface, in: RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
                    .stroke(accent.opacity(0.9), lineWidth: accent == SubwayTheme.border ? 1 : 2)
            }
    }
}

struct SubwayActionButtonStyle: ButtonStyle {
    let color: Color
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? colorForeground : SubwayTheme.ink)
            .background(
                prominent ? color : SubwayTheme.stationSurface,
                in: RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SubwayTheme.controlCornerRadius, style: .continuous)
                    .stroke(prominent ? color : SubwayTheme.border, lineWidth: prominent ? 2 : 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var colorForeground: Color {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.56 ? .black : .white
    }
}

struct SubwayHomeHeader: View {
    let symbol: String
    let title: String
    let message: String
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 52, height: 52)
                .background(accent.opacity(0.14), in: Circle())
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
                .stroke(accent, lineWidth: 2)
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
}

extension Line {
    var color: Color { Color(hex: colorHex) }

    var colorForeground: Color {
        let cleaned = colorHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return .white }
        let red = Double(value >> 16) / 255
        let green = Double(value >> 8 & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.56 ? .black : .white
    }
}

struct LineBadge: View {
    let line: Line
    var body: some View {
        Text(line.shortName)
            .font(.headline.monospacedDigit())
            .foregroundStyle(line.colorForeground)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, 4)
            .background(Color(hex: line.colorHex), in: Circle())
            .accessibilityLabel(AppLocalization.format("accessibility.line.format", line.name))
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

struct StationSignView: View {
    let station: Station
    let stationCode: String
    let line: Line
    var compact = false

    var body: some View {
        ZStack {
            line.color
                .frame(height: compact ? 28 : 34)
                .accessibilityHidden(true)

            HStack(spacing: compact ? 10 : 14) {
                Text(stationCode)
                    .font(.title3.bold().monospaced())
                    .foregroundStyle(line.colorForeground)
                    .minimumScaleFactor(0.7)
                    .frame(width: compact ? 56 : 66, height: compact ? 56 : 66)
                    .background(line.color, in: Circle())

                VStack(spacing: compact ? 2 : 4) {
                    Text(station.fullName ?? station.name)
                        .font(.title2.bold())
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)

                    if station.fullName != nil {
                        Text(station.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, compact ? 8 : 12)
            .padding(.leading, 12)
            .padding(.trailing, 24)
            .background(SubwayTheme.stationSurface, in: Capsule())
            .overlay {
                Capsule().stroke(line.color, lineWidth: 6)
            }
            .padding(.horizontal, 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLocalization.format(
            "accessibility.currentStation.format",
            station.fullName ?? station.name,
            stationCode
        ))
    }
}

struct NeighborStationSignView: View {
    let previous: Station?
    let next: Station?
    let line: Line
    var compact = false

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
        .accessibilityLabel(AppLocalization.format("accessibility.stationQuestion.format", previous?.name ?? AppLocalization.text("station.previous.none"), next?.name ?? AppLocalization.text("station.next.none")))
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

            Text(station?.name ?? fallback)
                .font(.system(size: 16, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.58)
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
    let hintDisabled: Bool
    let confirmDisabled: Bool
    let onHint: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        SubwayPanel(accent: color) {
            HStack(spacing: 12) {
                Button(hintTitle, systemImage: "lightbulb", action: onHint)
                    .buttonStyle(SubwayActionButtonStyle(color: color, prominent: false))
                    .disabled(hintDisabled)
                    .frame(maxWidth: .infinity, minHeight: 52)

                Button(AppLocalization.text("game.checkAnswer"), systemImage: "checkmark.circle", action: onConfirm)
                    .buttonStyle(SubwayActionButtonStyle(color: color, prominent: true))
                    .disabled(confirmDisabled)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .padding(12)
        }
        .controlSize(.large)
        .padding(.horizontal, AppLayout.pageHorizontal)
        .padding(.vertical, 12)
    }
}

struct StarsView: View {
    let stars: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { value in
                Image(systemName: value <= stars ? "star.fill" : "star")
                    .foregroundStyle(value <= stars ? .yellow : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.format("accessibility.stars.format", stars))
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
