import Foundation
import GameKit
import UIKit

@MainActor
final class GameCenterService: NSObject, ObservableObject {
    static let shared = GameCenterService()

    @Published private(set) var isAuthenticated = GKLocalPlayer.local.isAuthenticated
    @Published private(set) var lastError: String?

    static let weeklyLeaderboardID = "kr.co.remembersubway.weekly.v1"

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController { self.topViewController?.present(viewController, animated: true) }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            self.lastError = error?.localizedDescription
            GKAccessPoint.shared.location = .topTrailing
            GKAccessPoint.shared.isActive = self.isAuthenticated
        }
    }

    func submitWeekly(score: Int) async -> Bool {
        guard isAuthenticated else { return false }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 1,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.weeklyLeaderboardID]
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

    private var topViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var controller = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
