import Foundation

public enum Edibility: String, Codable, Equatable, Sendable {
    case edible
    case caution
    case poisonous
}

public enum RainfallSensitivity: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct Species: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let commonNameSk: String
    public let latinName: String
    public let edibility: Edibility
    public let lookAlikes: [String]
    public let fruitingMonths: Set<Int>
    public let idealTempMinC: Double
    public let idealTempMaxC: Double
    public let idealHumidityMinPercent: Double
    public let idealHumidityMaxPercent: Double
    public let rainfallSensitivity: RainfallSensitivity
    public let habitat: String
    public let regionalAffinity: Set<String>

    public init(
        id: String,
        commonNameSk: String,
        latinName: String,
        edibility: Edibility,
        lookAlikes: [String] = [],
        fruitingMonths: Set<Int>,
        idealTempMinC: Double,
        idealTempMaxC: Double,
        idealHumidityMinPercent: Double,
        idealHumidityMaxPercent: Double,
        rainfallSensitivity: RainfallSensitivity,
        habitat: String,
        regionalAffinity: Set<String>
    ) {
        self.id = id
        self.commonNameSk = commonNameSk
        self.latinName = latinName
        self.edibility = edibility
        self.lookAlikes = lookAlikes
        self.fruitingMonths = fruitingMonths
        self.idealTempMinC = idealTempMinC
        self.idealTempMaxC = idealTempMaxC
        self.idealHumidityMinPercent = idealHumidityMinPercent
        self.idealHumidityMaxPercent = idealHumidityMaxPercent
        self.rainfallSensitivity = rainfallSensitivity
        self.habitat = habitat
        self.regionalAffinity = regionalAffinity
    }
}
