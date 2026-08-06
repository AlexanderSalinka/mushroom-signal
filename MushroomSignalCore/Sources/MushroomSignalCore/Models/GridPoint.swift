import Foundation

public struct GridPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, latitude: Double, longitude: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
    }
}
