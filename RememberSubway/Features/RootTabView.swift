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
    @State private var showStats = false
    @State private var showTutorial = false

    var body: some View {
        Group {
            if let error = catalogStore.loadingError {
                EmptyStateView(title: AppLocalization.text("catalog.error.open.title"), message: error, symbol: "exclamationmark.triangle")
            } else {
                TabView {
                    Tab(AppLocalization.text("tab.singlePlayer"), systemImage: "person.fill") {
                        NavigationStack {
                            WeeklyChallengeHomeView(
                                showSettings: $showSettings,
                                showStats: $showStats,
                                showTutorial: $showTutorial
                            )
                        }
                    }
                    Tab(AppLocalization.text("tab.multiplayer"), systemImage: "person.3.fill") {
                        MultiplayerContainerView(
                            catalog: catalogStore.catalog,
                            showSettings: $showSettings,
                            showStats: $showStats,
                            showTutorial: $showTutorial
                        )
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
        .sheet(isPresented: $showStats) { NavigationStack { StatsView() } }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView {
                let record = settings.first ?? AppSettingsRecord()
                if record.modelContext == nil { modelContext.insert(record) }
                record.hasCompletedTutorial = true
                try? modelContext.save()
                showTutorial = false
            }
        }
    }

    private func prepareSettings() {
        let record: AppSettingsRecord
        if let existing = settings.first {
            record = existing
        } else {
            record = AppSettingsRecord()
            modelContext.insert(record)
        }
        try? ProgressStore.removeLegacyProgressIfNeeded(settings: record, context: modelContext)
    }

    private func syncGameCenterQueue() async {
        for record in pendingAchievements {
            if await gameCenter.reportAchievement(id: record.achievementID, percent: record.percentComplete) {
                modelContext.delete(record)
            }
        }
        for record in weeklyRecords where record.pendingSubmission {
            if await gameCenter.submitWeekly(score: record.bestScore, leaderboardID: record.leaderboardID) {
                record.pendingSubmission = false
            }
        }
        try? modelContext.save()
    }
}

struct SettingsButton: ToolbarContent {
    @Binding var isPresented: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(AppLocalization.text("common.settings"), systemImage: "gearshape") { isPresented = true }
        }
    }
}

struct AppToolbar: ToolbarContent {
    @Binding var showStats: Bool
    @Binding var showSettings: Bool
    @Binding var showTutorial: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(AppLocalization.text("common.howToPlay"), systemImage: "questionmark.circle") { showTutorial = true }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(AppLocalization.text("common.records"), systemImage: "chart.bar.fill") { showStats = true }
            Button(AppLocalization.text("common.settings"), systemImage: "gearshape") { showSettings = true }
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
                Section(AppLocalization.text("settings.gameCenter.section")) {
                    LabeledContent(
                        AppLocalization.text("common.status"),
                        value: gameCenter.isAuthenticated
                            ? AppLocalization.text("gameCenter.signedIn")
                            : AppLocalization.text("gameCenter.signedOut")
                    )
                    Button(gameCenter.isAuthenticated
                        ? AppLocalization.text("gameCenter.openDashboard")
                        : AppLocalization.text("gameCenter.signIn")) {
                        gameCenter.isAuthenticated ? gameCenter.showDashboard() : gameCenter.authenticate()
                    }
                }
                Section(AppLocalization.text("settings.game.section")) {
                    Toggle(AppLocalization.text("settings.haptics"), isOn: hapticsBinding)
                    TextField(AppLocalization.text("settings.multiplayerNickname"), text: nicknameBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section(AppLocalization.text("settings.transitData.section")) {
                    LabeledContent(AppLocalization.text("settings.contentVersion"), value: catalogStore.catalog.contentVersion)
                    LabeledContent(AppLocalization.text("settings.dataAsOf"), value: catalogStore.catalog.dataAsOf)
                    ForEach(catalogStore.catalog.sources, id: \.self) { source in
                        Link(source.title, destination: source.url)
                    }
                }
                Section(AppLocalization.text("settings.appInfo.section")) {
                    LabeledContent(
                        AppLocalization.text("settings.privacy"),
                        value: AppLocalization.text("settings.privacy.none")
                    )
                    Text(AppLocalization.text("settings.appSummary"))
                }
            }
            .navigationTitle(AppLocalization.text("common.settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(AppLocalization.text("common.done")) { dismiss() } }
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

    private var nicknameBinding: Binding<String> {
        Binding(
            get: { settings.first?.multiplayerNickname ?? "" },
            set: { value in
                let record = settings.first ?? AppSettingsRecord()
                if record.modelContext == nil { modelContext.insert(record) }
                record.multiplayerNickname = String(value.prefix(10))
                try? modelContext.save()
            }
        )
    }
}
