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
        let updatesByAlertID = Dictionary(uniqueKeysWithValues: updates.map { ($0.alert.id, $0) })

        // Rebuild in the original stored order (not the update dictionary's unspecified
        // order) so the settings list doesn't silently reshuffle after every widget refresh.
        // An alert missing from `updates` (e.g. its region's weather fetch failed) is carried
        // over unchanged rather than dropped, since setWatchedAlerts below is a full replace.
        var finalAlerts: [WatchedAlert] = []
        finalAlerts.reserveCapacity(alerts.count)

        for var alert in alerts {
            guard let update = updatesByAlertID[alert.id] else {
                finalAlerts.append(alert)
                continue
            }
            alert.lastKnownScore = update.newScore
            finalAlerts.append(alert)

            guard update.shouldNotify else { continue }
            let speciesName = allSpecies.first { $0.id == alert.speciesId }?.commonNameSk ?? alert.speciesId
            let regionName = RegionDatabase.find(id: alert.regionId)?.nameSk ?? alert.regionId
            let content = UNMutableNotificationContent()
            content.title = "Hubám sa dnes darí"
            content.body = "\(speciesName) — \(regionName)"
            content.sound = .default
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                notificationLogger.error("Failed to post notification for \(alert.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        preferences.setWatchedAlerts(finalAlerts)
    }
}
