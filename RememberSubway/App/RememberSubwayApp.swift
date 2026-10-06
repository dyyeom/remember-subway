import os
import SwiftData
import SwiftUI

@main
struct RememberSubwayApp: App {
    @StateObject private var catalogStore = TransitCatalogStore()
    @StateObject private var gameCenter = GameCenterService.shared

    private let storage = AppModelContainer.make()

    var body: some Scene {
        WindowGroup {
            RootTabView(isStorageVolatile: !storage.isPersistent)
                .environmentObject(catalogStore)
                .environmentObject(gameCenter)
                .task { gameCenter.authenticate() }
        }
        .modelContainer(storage.container)
    }
}

enum AppModelContainer {
    static let schema = Schema([
        SegmentProgressRecord.self,
        SinglePlayerBestRecord.self,
        AppSettingsRecord.self,
        PendingAchievementRecord.self,
        MultiplayerProfileRecord.self,
        MultiplayerMatchRecord.self
    ])

    private static let logger = Logger(subsystem: "com.evolvingark.remembersubway.app", category: "Storage")

    /// 영구 저장소를 열지 못하면 기존 저장 파일은 건드리지 않고 이번 실행만 인메모리 저장소로 이어 간다.
    /// `configuration`이 없으면 기본 영구 저장소를 연다.
    static func make(configuration: ModelConfiguration? = nil) -> (container: ModelContainer, isPersistent: Bool) {
        do {
            let container = if let configuration {
                try ModelContainer(for: schema, configurations: configuration)
            } else {
                try ModelContainer(for: schema)
            }
            return (container, true)
        } catch {
            logger.error("Persistent store unavailable, falling back to in-memory store: \(String(describing: error), privacy: .public)")
        }
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            return (container, false)
        } catch {
            // 인메모리 저장소까지 실패하면 스키마 자체가 잘못된 프로그래밍 오류다.
            logger.fault("In-memory store creation failed: \(String(describing: error), privacy: .public)")
            fatalError(AppLocalization.format("storage.error.create.format", String(describing: error)))
        }
    }
}
