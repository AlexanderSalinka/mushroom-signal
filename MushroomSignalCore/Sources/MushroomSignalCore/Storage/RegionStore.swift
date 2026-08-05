import Foundation

public enum RegionStoreConstants {
    public static let appGroupId = "group.com.alexandersalinka.MushroomSignal"
    public static let selectedRegionKey = "selectedRegionId"
    public static let defaultRegionId = "zilinsky"
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
