import Foundation
import UserNotifications
import MushroomSignalCore
import os

private let notificationLogger = Logger(subsystem: "com.alexandersalinka.MushroomSignal.Widget", category: "NotificationPoster")

enum NotificationPoster {
    /// Checks every watched alert against current weather and posts a local notification for
    /// any that just crossed its threshold upward. Always updates lastKnownScore for every
    /// alert it successfully evaluates, whether or not it notified — this is how the
    /// upward-crossing-only logic in NotificationThreshold has a baseline to compare against
    /// on the next refresh. Deliberately isolates all failures (never throws) so a bug here
    /// can never prevent the widget's own completion(timeline) call.
    static func checkAndPostWatchedAlerts() async {
        guard let preferences = NotificationPreferences() else {
            notificationLogger.error("NotificationPreferences unavailable — App Group entitlement missing or misconfigured")
            return
        }
        let alerts = preferences.watchedAlerts()
        guard !alerts.isEmpty else { return }

        guard let allSpecies = try? SpeciesDatabase.loadAll() else {
            notificationLogger.error("Failed to load species dataset for notification check")
            return
        }

        let month = Calendar.current.component(.month, from: Date())
        let updates = await WatchedAlertEvaluator.evaluate(alerts: alerts, species: allSpecies, weatherClient: OpenMeteoClient(), month: month)

        // Merge updates back into the FULL alert list, keyed by id — evaluate() can skip an
        // alert (e.g. its region's weather fetch failed) without that alert being silently
        // dropped from storage, since setWatchedAlerts below is a full replace.
        var alertsByID = Dictionary(uniqueKeysWithValues: alerts.map { ($0.id, $0) })

        for update in updates {
            var alert = update.alert
            alert.lastKnownScore = update.newScore
            alertsByID[alert.id] = alert

            guard update.shouldNotify else { continue }
            let speciesName = allSpecies.first { $0.id == alert.speciesId }?.commonNameSk ?? alert.speciesId
            let regionName = RegionDatabase.find(id: alert.regionId)?.nameSk ?? alert.regionId
            let content = UNMutableNotificationContent()
            content.title = "Hríby sa dnes darí"
            content.body = "\(speciesName) v \(regionName)"
            content.sound = .default
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                notificationLogger.error("Failed to post notification for \(alert.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        preferences.setWatchedAlerts(Array(alertsByID.values))
    }
}
