import Foundation

/// A user's request to be notified when `speciesId`'s score crosses `threshold` in `regionId`.
/// `lastKnownScore` is the score observed on the most recent check — used by
/// `NotificationThreshold` to detect an upward crossing rather than re-notifying every refresh.
public struct WatchedAlert: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(speciesId)|\(regionId)" }
    public let speciesId: String
    public let regionId: String
    public let threshold: Int
    public var lastKnownScore: Int?

    public init(speciesId: String, regionId: String, threshold: Int, lastKnownScore: Int? = nil) {
        self.speciesId = speciesId
        self.regionId = regionId
        self.threshold = threshold
        self.lastKnownScore = lastKnownScore
    }
}
