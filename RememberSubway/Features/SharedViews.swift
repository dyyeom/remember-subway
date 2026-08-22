import SwiftUI

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
    let lives: Int
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < lives ? "heart.fill" : "heart")
                    .foregroundStyle(index < lives ? .red : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 목숨 \(lives)개")
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

    var body: some View {
        ZStack {
            line.color
                .frame(height: 34)
                .accessibilityHidden(true)

            HStack(spacing: 14) {
                Text(stationCode)
                    .font(.title3.bold().monospaced())
                    .foregroundStyle(line.colorForeground)
                    .minimumScaleFactor(0.7)
                    .frame(width: 66, height: 66)
                    .background(line.color, in: Circle())

                VStack(spacing: 4) {
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
            .padding(.vertical, 12)
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
        .padding(.horizontal, 16)
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
