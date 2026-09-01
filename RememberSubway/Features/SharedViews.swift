import SwiftUI

enum AppLayout {
    static let pageHorizontal: CGFloat = 20
    static let pageVertical: CGFloat = 16
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
            .accessibilityLabel("\(line.name) 노선")
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
        .accessibilityLabel("남은 목숨 \(lives)개")
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
            .foregroundStyle(.red)
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
        Label {
            Text(line.name)
                .font(.subheadline.weight(.semibold))
        } icon: {
            Circle()
                .fill(line.color)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().stroke(.primary.opacity(0.12), lineWidth: 0.5)
                }
        }
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
            .background(.white, in: Capsule())
            .overlay {
                Capsule().stroke(line.color, lineWidth: 6)
            }
            .padding(.horizontal, 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("현재 역, \(station.fullName ?? station.name), 역 번호 \(stationCode)")
    }
}

struct NeighborStationSignView: View {
    let previous: Station
    let next: Station
    let line: Line
    var compact = false

    var body: some View {
        ZStack {
            Capsule().fill(line.color).frame(height: compact ? 68 : 82)
            HStack(spacing: 8) {
                neighborLabel(title: "이전 역", station: previous, arrow: "chevron.left")
                VStack(spacing: 4) {
                    Text("현재 역").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("?")
                        .font(.system(size: compact ? 38 : 46, weight: .bold, design: .rounded))
                        .foregroundStyle(line.color)
                }
                .frame(width: compact ? 96 : 112, height: compact ? 96 : 112)
                .background(.background, in: Capsule())
                .overlay { Capsule().stroke(line.color, lineWidth: 5) }
                neighborLabel(title: "다음 역", station: next, arrow: "chevron.right")
            }
            .padding(.horizontal, 12)
        }
        .frame(minHeight: compact ? 106 : 124)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("이전 역 \(previous.name), 다음 역 \(next.name). 이 역의 이름을 맞혀 보세요.")
    }

    private func neighborLabel(title: String, station: Station, arrow: String) -> some View {
        VStack(spacing: 5) {
            Label(title, systemImage: arrow).font(.caption2.weight(.semibold))
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

struct GameGlassActionBar: View {
    let color: Color
    let hintTitle: String
    let hintDisabled: Bool
    let confirmDisabled: Bool
    let onHint: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(hintTitle, systemImage: "lightbulb", action: onHint)
                    .buttonStyle(.glass)
                    .disabled(hintDisabled)
                    .frame(maxWidth: .infinity, minHeight: 52)

                Button("정답 확인", systemImage: "checkmark.circle", action: onConfirm)
                    .buttonStyle(.glassProminent)
                    .tint(color)
                    .disabled(confirmDisabled)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
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
        .accessibilityLabel("별 \(stars)개")
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
