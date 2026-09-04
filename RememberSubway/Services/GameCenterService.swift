import Foundation
import GameKit
import UIKit

@MainActor
final class GameCenterService: NSObject, ObservableObject, @preconcurrency GKGameCenterControllerDelegate {
    static let shared = GameCenterService()

    @Published private(set) var isAuthenticated = GKLocalPlayer.local.isAuthenticated
    @Published private(set) var lastError: String?

    static let singlePlayerLeaderboardID = "kr.co.remembersubway.single.v1"

    static func singlePlayerLeaderboardID(regionID: String, lineID: String?) -> String {
        let scope = lineID.map { "line.\(leaderboardComponent($0))" }
            ?? "region.\(leaderboardComponent(regionID))"
        return "kr.co.remembersubway.single.\(scope).v1"
    }

    func authenticate() {
        GKAccessPoint.shared.isActive = false
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController { self.topViewController?.present(viewController, animated: true) }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            self.lastError = error?.localizedDescription
            GKAccessPoint.shared.isActive = false
        }
    }

    func submitSinglePlayer(score: Int, leaderboardID: String = singlePlayerLeaderboardID) async -> Bool {
        guard isAuthenticated else { return false }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 1,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardID]
            )
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func reportAchievement(id: String, percent: Double = 100) async -> Bool {
        guard isAuthenticated else { return false }
        let achievement = GKAchievement(identifier: id)
        achievement.percentComplete = percent
        achievement.showsCompletionBanner = true
        do { try await GKAchievement.report([achievement]); return true }
        catch { lastError = error.localizedDescription; return false }
    }

    func showDashboard() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    func showLeaderboard(id: String) {
        guard isAuthenticated, let topViewController else { return }
        let controller = GKGameCenterViewController(
            leaderboardID: id,
            playerScope: .global,
            timeScope: .allTime
        )
        controller.gameCenterDelegate = self
        topViewController.present(controller, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }

    private static func leaderboardComponent(_ value: String) -> String {
        value.map { $0.isLetter || $0.isNumber ? String($0).lowercased() : "_" }.joined()
    }

    private var topViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var controller = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
