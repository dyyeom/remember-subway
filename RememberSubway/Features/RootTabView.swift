import SwiftData
import SwiftUI

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query private var settings: [AppSettingsRecord]
    @Query private var pendingAchievements: [PendingAchievementRecord]
    @Query private var weeklyRecords: [WeeklyBestRecord]
    @State private var showSettings = false

    var body: some View {
        Group {
            if let error = catalogStore.loadingError {
                EmptyStateView(title: "노선 데이터를 열 수 없어요", message: error, symbol: "exclamationmark.triangle")
            } else {
                TabView {
                    Tab("노선", systemImage: "tram.fill") {
                        NavigationStack { RegionsView(showSettings: $showSettings) }
                    }
                    Tab("주간 도전", systemImage: "trophy.fill") {
                        NavigationStack { WeeklyChallengeHomeView(showSettings: $showSettings) }
                    }
                    Tab("기록", systemImage: "chart.bar.fill") {
                        NavigationStack { StatsView(showSettings: $showSettings) }
                    }
                }
            }
        }
        .task {
            prepareSettings()
            if gameCenter.isAuthenticated { await syncGameCenterQueue() }
        }
        .onChange(of: gameCenter.isAuthenticated) { _, authenticated in
            if authenticated { Task { await syncGameCenterQueue() } }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func prepareSettings() {
        if settings.isEmpty {
            let record = AppSettingsRecord()
            modelContext.insert(record)
            try? modelContext.save()
        }
    }

    private func syncGameCenterQueue() async {
        for record in pendingAchievements {
            if await gameCenter.reportAchievement(id: record.achievementID, percent: record.percentComplete) {
                modelContext.delete(record)
            }
        }
        for record in weeklyRecords where record.pendingSubmission {
            if await gameCenter.submitWeekly(score: record.bestScore) { record.pendingSubmission = false }
        }
        try? modelContext.save()
    }
}

struct SettingsButton: ToolbarContent {
    @Binding var isPresented: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("설정", systemImage: "gearshape") { isPresented = true }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalogStore: TransitCatalogStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @Query private var settings: [AppSettingsRecord]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Center") {
                    LabeledContent("상태", value: gameCenter.isAuthenticated ? "로그인됨" : "로그인 안 됨")
                    Button(gameCenter.isAuthenticated ? "대시보드 열기" : "로그인하기") {
                        gameCenter.isAuthenticated ? gameCenter.showDashboard() : gameCenter.authenticate()
                    }
                }
                Section("게임") {
                    Toggle("촉각 피드백", isOn: hapticsBinding)
                }
                Section("노선 데이터") {
                    LabeledContent("콘텐츠 버전", value: catalogStore.catalog.contentVersion)
                    LabeledContent("기준일", value: catalogStore.catalog.dataAsOf)
                    ForEach(catalogStore.catalog.sources, id: \.self) { source in
                        Link(source.title, destination: source.url)
                    }
                }
                Section("앱 정보") {
                    LabeledContent("개인정보", value: "별도 수집 없음")
                    Text("역순서 · 무료 · 광고 없음")
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } }
            }
        }
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { settings.first?.hapticsEnabled ?? true },
            set: { value in
                let record = settings.first ?? AppSettingsRecord()
                if record.modelContext == nil { modelContext.insert(record) }
                record.hapticsEnabled = value
                try? modelContext.save()
            }
        )
    }
}
