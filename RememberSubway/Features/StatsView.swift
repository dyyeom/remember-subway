import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @Query(sort: \WeeklyBestRecord.updatedAt, order: .reverse) private var weekly: [WeeklyBestRecord]
    @Query private var multiplayerProfiles: [MultiplayerProfileRecord]
    @Query(sort: \MultiplayerMatchRecord.playedAt, order: .reverse) private var multiplayerHistory: [MultiplayerMatchRecord]

    var body: some View {
        List {
            Section("멀티플레이 전적") {
                LabeledContent("경기", value: "\(profile?.matches ?? 0)회")
                LabeledContent("승리", value: "\(profile?.wins ?? 0)회")
                LabeledContent("3위 이내", value: "\(profile?.podiums ?? 0)회")
                LabeledContent("정답률", value: correctRate)
                LabeledContent("최고 점수", value: "\(profile?.bestScore ?? 0)점")
            }
            if !weekly.isEmpty {
                Section("최근 싱글플레이") {
                    ForEach(weekly.prefix(10)) { record in
                        LabeledContent("\(weeklyScopeName(record)) · \(record.weekID)", value: "\(record.bestScore)점")
                    }
                }
            }
            if !multiplayerHistory.isEmpty {
                Section("최근 멀티플레이") {
                    ForEach(multiplayerHistory.prefix(20)) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(catalogStore.catalog.lineByID[record.lineID]?.name ?? "노선").font(.headline)
                                Spacer()
                                Text("\(record.rank)위 · \(record.score)점")
                            }
                            Text("\(record.playerCount)명 · 정답 \(record.correctAnswers)개")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("기록")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
        }
    }

    private var profile: MultiplayerProfileRecord? { multiplayerProfiles.first }

    private func weeklyScopeName(_ record: WeeklyBestRecord) -> String {
        if record.scopeID.hasPrefix("line:") {
            let lineID = String(record.scopeID.dropFirst("line:".count))
            return catalogStore.catalog.lineByID[lineID]?.name ?? "노선"
        }
        if record.scopeID.hasPrefix("region:") {
            let regionID = String(record.scopeID.dropFirst("region:".count))
            let name = catalogStore.catalog.regions.first { $0.id == regionID }?.name ?? "지역"
            return "\(name) 전체"
        }
        return "이전 기록"
    }

    private var correctRate: String {
        guard let profile, profile.totalQuestions > 0 else { return "0%" }
        let percentage = Double(profile.correctAnswers) / Double(profile.totalQuestions) * 100
        return "\(Int(percentage.rounded()))%"
    }
}
