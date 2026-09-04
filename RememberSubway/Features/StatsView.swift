import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @Query(sort: \SinglePlayerBestRecord.updatedAt, order: .reverse) private var singlePlayer: [SinglePlayerBestRecord]
    @Query private var multiplayerProfiles: [MultiplayerProfileRecord]
    @Query(sort: \MultiplayerMatchRecord.playedAt, order: .reverse) private var multiplayerHistory: [MultiplayerMatchRecord]

    var body: some View {
        List {
            Section(AppLocalization.text("stats.multiplayer.section")) {
                LabeledContent(AppLocalization.text("stats.matches"), value: AppLocalization.format("count.times.format", profile?.matches ?? 0))
                LabeledContent(AppLocalization.text("stats.wins"), value: AppLocalization.format("count.times.format", profile?.wins ?? 0))
                LabeledContent(AppLocalization.text("stats.podiums"), value: AppLocalization.format("count.times.format", profile?.podiums ?? 0))
                LabeledContent(AppLocalization.text("stats.accuracy"), value: correctRate)
                LabeledContent(AppLocalization.text("stats.bestScore"), value: AppLocalization.format("score.points.format", profile?.bestScore ?? 0))
            }
            if !singlePlayer.isEmpty {
                Section(AppLocalization.text("stats.recentSingle.section")) {
                    ForEach(singlePlayer.prefix(10)) { record in
                        LabeledContent(singlePlayerScopeName(record), value: AppLocalization.format("score.points.format", record.bestScore))
                    }
                }
            }
            if !multiplayerHistory.isEmpty {
                Section(AppLocalization.text("stats.recentMultiplayer.section")) {
                    ForEach(multiplayerHistory.prefix(20)) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(catalogStore.catalog.lineByID[record.lineID]?.name ?? AppLocalization.text("common.line")).font(.headline)
                                Spacer()
                                Text(AppLocalization.format("stats.rankAndScore.format", record.rank, record.score))
                            }
                            Text(AppLocalization.format("stats.playersAndCorrect.format", record.playerCount, record.correctAnswers))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(AppLocalization.text("common.records"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.text("common.done")) { dismiss() } }
        }
    }

    private var profile: MultiplayerProfileRecord? { multiplayerProfiles.first }

    private func singlePlayerScopeName(_ record: SinglePlayerBestRecord) -> String {
        if record.scopeID.hasPrefix("line:") {
            let lineID = String(record.scopeID.dropFirst("line:".count))
            return catalogStore.catalog.lineByID[lineID]?.name ?? AppLocalization.text("common.line")
        }
        if record.scopeID.hasPrefix("region:") {
            let regionID = String(record.scopeID.dropFirst("region:".count))
            let name = catalogStore.catalog.regions.first { $0.id == regionID }?.name ?? AppLocalization.text("common.region")
            return AppLocalization.format("single.regionAll.format", name)
        }
        return AppLocalization.text("stats.legacyRecord")
    }

    private var correctRate: String {
        guard let profile, profile.totalQuestions > 0 else { return "0%" }
        let percentage = Double(profile.correctAnswers) / Double(profile.totalQuestions) * 100
        return "\(Int(percentage.rounded()))%"
    }
}
