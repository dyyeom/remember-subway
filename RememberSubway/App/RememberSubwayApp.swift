import SwiftData
import SwiftUI

@main
struct RememberSubwayApp: App {
    @StateObject private var catalogStore = TransitCatalogStore()
    @StateObject private var gameCenter = GameCenterService.shared

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            SegmentProgressRecord.self,
            WeeklyBestRecord.self,
            AppSettingsRecord.self,
            PendingAchievementRecord.self,
            MultiplayerProfileRecord.self,
            MultiplayerMatchRecord.self
        ])
        do { return try ModelContainer(for: schema) }
        catch { fatalError(AppLocalization.format("storage.error.create.format", String(describing: error))) }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(catalogStore)
                .environmentObject(gameCenter)
                .task { gameCenter.authenticate() }
        }
        .modelContainer(modelContainer)
    }
}
