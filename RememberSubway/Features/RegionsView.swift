import SwiftData
import SwiftUI

struct RegionsView: View {
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @Query private var progress: [SegmentProgressRecord]
    @Binding var showSettings: Bool
    @State private var selectedRegionID: String?
    @State private var selectedLineID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.text("legacy.lines.title"))
                        .font(.largeTitle.bold())
                    Text(AppLocalization.text("legacy.lines.description"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    selectionRow(title: AppLocalization.text("common.region"), systemImage: "map") {
                        Picker(AppLocalization.text("common.region"), selection: $selectedRegionID) {
                            Text(AppLocalization.text("common.selectRegion")).tag(Optional<String>.none)
                            ForEach(regions) { region in
                                Text(region.name).tag(Optional(region.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Divider().padding(.leading, 52)

                    selectionRow(title: AppLocalization.text("common.line"), systemImage: "tram.fill") {
                        Picker(AppLocalization.text("common.line"), selection: $selectedLineID) {
                            Text(AppLocalization.text("common.selectLine")).tag(Optional<String>.none)
                            ForEach(linesForSelectedRegion) { line in
                                Text(line.name).tag(Optional(line.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.horizontal, 16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if let line = selectedLine {
                    selectedLineCard(line)
                    startActions(line)
                } else {
                    ContentUnavailableView(
                        AppLocalization.text("legacy.lines.empty.title"),
                        systemImage: "tram",
                        description: Text(AppLocalization.text("legacy.lines.empty.message"))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle(AppLocalization.text("common.line"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Line.self) { line in LineDetailView(line: line) }
        .toolbar { SettingsButton(isPresented: $showSettings) }
        .task { initializeSelection() }
        .onChange(of: selectedRegionID) { _, _ in selectFirstLine() }
    }

    private var regions: [Region] {
        catalogStore.catalog.regions.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedRegion: Region? {
        regions.first { $0.id == selectedRegionID }
    }

    private var linesForSelectedRegion: [Line] {
        guard let selectedRegion else { return [] }
        return catalogStore.catalog.lines(in: selectedRegion)
    }

    private var selectedLine: Line? {
        linesForSelectedRegion.first { $0.id == selectedLineID }
    }

    private func initializeSelection() {
        guard selectedRegionID == nil else { return }
        selectedRegionID = regions.first?.id
        selectFirstLine()
    }

    private func selectFirstLine() {
        selectedLineID = linesForSelectedRegion.first?.id
    }

    private func selectionRow<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.body.weight(.medium))
            Spacer()
            content()
                .labelsHidden()
                .tint(selectedLine?.color ?? .accentColor)
        }
        .frame(minHeight: 58)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func selectedLineCard(_ line: Line) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LineBadge(line: line)
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name)
                        .font(.title3.bold())
                    Text(lineProgress(line))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let segment = nextSegment(for: line) {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.format("legacy.nextChallenge.format", segment.index + 1))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(line.color)
                    Text(stationRange(segment))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(line.color.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }

    @ViewBuilder private func startActions(_ line: Line) -> some View {
        VStack(spacing: 12) {
            if let segment = nextSegment(for: line) {
                NavigationLink {
                    GameSessionView(segment: segment, line: line, catalog: catalogStore.catalog)
                } label: {
                    Label(AppLocalization.text("common.startGame"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .tint(line.color)
                .controlSize(.large)
            }

            NavigationLink(value: line) {
                Label(AppLocalization.text("legacy.browseSegments"), systemImage: "list.bullet")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func nextSegment(for line: Line) -> Segment? {
        let patterns = catalogStore.catalog.patterns(for: line)
        let completed = Dictionary(uniqueKeysWithValues: progress.map { ($0.segmentID, $0.completions) })

        for pattern in patterns {
            let segments = catalogStore.catalog.segments(for: pattern)
            if let next = segments.first(where: { segment in
                guard completed[segment.id, default: 0] == 0 else { return false }
                guard segment.index > 0 else { return true }
                return completed[segments[segment.index - 1].id, default: 0] > 0
            }) {
                return next
            }
        }

        return patterns.first.flatMap { catalogStore.catalog.segments(for: $0).first }
    }

    private func stationRange(_ segment: Segment) -> String {
        let names = segment.stationIDs.compactMap { catalogStore.catalog.stationByID[$0]?.name }
        return "\(names.first ?? "") → \(names.last ?? "")"
    }

    private func lineProgress(_ line: Line) -> String {
        let segments = catalogStore.catalog.patterns(for: line).flatMap { catalogStore.catalog.segments(for: $0) }
        let completed = Set(progress.filter { $0.completions > 0 }.map(\.segmentID))
        return AppLocalization.format(
            "legacy.segmentsCompleted.format",
            segments.filter { completed.contains($0.id) }.count,
            segments.count
        )
    }
}

struct LineDetailView: View {
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @Query private var progress: [SegmentProgressRecord]
    let line: Line

    var body: some View {
        List {
            ForEach(catalogStore.catalog.patterns(for: line)) { pattern in
                Section(pattern.name) {
                    let segments = catalogStore.catalog.segments(for: pattern)
                    ForEach(segments) { segment in
                        if isUnlocked(segment, in: segments) {
                            NavigationLink {
                                GameSessionView(segment: segment, line: line, catalog: catalogStore.catalog)
                            } label: {
                                SegmentRow(segment: segment, line: line, catalog: catalogStore.catalog, stars: stars(for: segment))
                            }
                        } else {
                            SegmentRow(segment: segment, line: line, catalog: catalogStore.catalog, stars: 0, isLocked: true)
                        }
                    }
                }
            }
        }
        .navigationTitle(line.name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(line.color)
    }

    private func stars(for segment: Segment) -> Int {
        progress.first { $0.segmentID == segment.id }?.bestStars ?? 0
    }

    private func isUnlocked(_ segment: Segment, in segments: [Segment]) -> Bool {
        guard segment.index > 0 else { return true }
        return (progress.first { $0.segmentID == segments[segment.index - 1].id }?.completions ?? 0) > 0
    }
}

private struct SegmentRow: View {
    let segment: Segment
    let line: Line
    let catalog: TransitCatalog
    let stars: Int
    var isLocked = false

    var body: some View {
        HStack {
            Image(systemName: isLocked ? "lock.fill" : "point.bottomleft.forward.to.point.topright.scurvepath")
                .frame(width: 30)
                .foregroundStyle(isLocked ? Color.secondary : line.color)
            VStack(alignment: .leading) {
                Text(AppLocalization.format("legacy.segmentNumber.format", segment.index + 1))
                    .font(.headline)
                Text(stationRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !isLocked { StarsView(stars: stars) }
        }
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }

    private var stationRange: String {
        let stations = segment.stationIDs.compactMap { catalog.stationByID[$0]?.name }
        return "\(stations.first ?? "") → \(stations.last ?? "")"
    }
}
