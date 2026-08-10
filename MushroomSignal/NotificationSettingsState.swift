import Foundation
import UserNotifications
import MushroomSignalCore

@MainActor
final class NotificationSettingsState: ObservableObject {
    @Published var watchedAlerts: [WatchedAlert] = []
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let preferences: NotificationPreferences?

    init(preferences: NotificationPreferences? = NotificationPreferences()) {
        self.preferences = preferences
        self.watchedAlerts = preferences?.watchedAlerts() ?? []
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        guard authorizationStatus == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshAuthorizationStatus()
    }

    func addOrUpdateWatch(speciesId: String, regionId: String, threshold: Int) {
        let id = WatchedAlert(speciesId: speciesId, regionId: regionId, threshold: threshold).id
        let existingScore = watchedAlerts.first { $0.id == id }?.lastKnownScore
        let newAlert = WatchedAlert(speciesId: speciesId, regionId: regionId, threshold: threshold, lastKnownScore: existingScore)
        watchedAlerts.removeAll { $0.id == newAlert.id }
        watchedAlerts.append(newAlert)
        preferences?.setWatchedAlerts(watchedAlerts)
    }

    func removeWatch(_ alert: WatchedAlert) {
        watchedAlerts.removeAll { $0.id == alert.id }
        preferences?.setWatchedAlerts(watchedAlerts)
    }
}
