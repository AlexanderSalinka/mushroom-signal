import Foundation

public struct Region: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let nameSk: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, nameSk: String, latitude: Double, longitude: Double) {
        self.id = id
        self.nameSk = nameSk
        self.latitude = latitude
        self.longitude = longitude
    }
}
