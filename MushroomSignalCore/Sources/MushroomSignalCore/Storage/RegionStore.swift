import Foundation
import Security

public enum TeamIdentifier {
    public static func current() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil) as? String
    }
}

public enum RegionStoreConstants {
    static let appGroupSuffix = "group.com.alexandersalinka.MushroomSignal"
    public static let selectedRegionKey = "selectedRegionId"
    public static let defaultRegionId = "zilinsky"

    /// Composes the team-ID-prefixed App Group identifier macOS requires.
    /// Exposed with an injectable parameter so the composition logic is unit-testable
    /// without needing an actual signed/sandboxed process (SecTask resolves to nil there).
    public static func resolvedAppGroupId(teamIdentifier: String? = TeamIdentifier.current()) -> String {
        if let teamIdentifier {
            return "\(teamIdentifier).\(appGroupSuffix)"
        }
        return appGroupSuffix
    }

    public static var appGroupId: String { resolvedAppGroupId() }
}

public struct RegionStore {
    private let defaults: UserDefaults

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func selectedRegion() -> Region {
        let id = defaults.string(forKey: RegionStoreConstants.selectedRegionKey) ?? RegionStoreConstants.defaultRegionId
        return RegionDatabase.find(id: id) ?? RegionDatabase.find(id: RegionStoreConstants.defaultRegionId) ?? RegionDatabase.all[0]
    }

    public func setSelectedRegion(_ region: Region) {
        defaults.set(region.id, forKey: RegionStoreConstants.selectedRegionKey)
    }
}
