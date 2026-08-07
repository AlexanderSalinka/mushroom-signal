import Foundation
import Security

public enum RegionStoreConstants {
    static let appGroupSuffix = "group.com.alexandersalinka.MushroomSignal"
    public static let selectedRegionKey = "selectedRegionId"
    public static let defaultRegionId = "zilinsky"

    /// Reads the team-ID-prefixed App Group identifier macOS requires directly from this
    /// process's own `com.apple.security.application-groups` entitlement — the same array
    /// Xcode/codesign already resolves `$(TeamIdentifierPrefix)` into at build time, so it
    /// can't drift out of sync with what MushroomSignal.entitlements declares. (A prior
    /// version derived this by separately reading `com.apple.developer.team-identifier` and
    /// concatenating it with the suffix — that entitlement is never actually present in this
    /// app's signed output, so it always resolved nil, silently redirecting every read/write
    /// to a bare, non-team-prefixed suite the App Group container never sees.)
    /// Exposed with an injectable parameter so the fallback logic is unit-testable without
    /// needing an actual signed/sandboxed process (SecTask resolves to nil there).
    public static func resolvedAppGroupId(
        applicationGroupsEntitlement: [String]? = Self.currentApplicationGroupsEntitlement()
    ) -> String {
        applicationGroupsEntitlement?.first ?? appGroupSuffix
    }

    public static func currentApplicationGroupsEntitlement() -> [String]? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String]
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
