import SwiftData
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @Query private var progress: [SegmentProgressRecord]
    @Query(sort: \WeeklyBestRecord.updatedAt, order: .reverse) private var weekly: [WeeklyBestRecord]
    @Binding var showSettings: Bool

    var body: some View {
        List {
            Section("전체 기록") {
                LabeledContent("완료한 구간", value: "\(completedSegments)/\(totalSegments)")
                LabeledContent("획득한 별", value: "\(progress.reduce(0) { $0 + $1.bestStars })개")
                LabeledContent("총 도전", value: "\(progress.reduce(0) { $0 + $1.attempts })회")
                LabeledContent("오답", value: "\(progress.reduce(0) { $0 + $1.wrongAnswers })회")
            }
            Section("지역별 진행률") {
                ForEach(catalogStore.catalog.regions.sorted { $0.sortOrder < $1.sortOrder }) { region in
                    let counts = regionCounts(region)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(region.name); Spacer(); Text("\(counts.done)/\(counts.total)").foregroundStyle(.secondary) }
                        ProgressView(value: counts.total == 0 ? 0 : Double(counts.done) / Double(counts.total))
                    }
                    .padding(.vertical, 4)
                }
            }
            if !weekly.isEmpty {
                Section("최근 주간 기록") {
                    ForEach(weekly.prefix(5)) { record in
                        LabeledContent(record.weekID, value: "\(record.bestScore)점")
                    }
                }
            }
        }
        .navigationTitle("기록")
        .toolbar { SettingsButton(isPresented: $showSettings) }
    }

    private var allSegments: [Segment] {
        catalogStore.catalog.routePatterns.flatMap { catalogStore.catalog.segments(for: $0) }
    }
    private var totalSegments: Int { allSegments.count }
    private var completedSegments: Int { progress.filter { $0.completions > 0 }.count }

    private func regionCounts(_ region: Region) -> (done: Int, total: Int) {
        let lineIDs = Set(catalogStore.catalog.lines(in: region).map(\.id))
        let patternIDs = Set(catalogStore.catalog.routePatterns.filter { lineIDs.contains($0.lineID) }.map(\.id))
        let segments = allSegments.filter { patternIDs.contains($0.routePatternID) }
        let completed = Set(progress.filter { $0.completions > 0 }.map(\.segmentID))
        return (segments.filter { completed.contains($0.id) }.count, segments.count)
    }
}

