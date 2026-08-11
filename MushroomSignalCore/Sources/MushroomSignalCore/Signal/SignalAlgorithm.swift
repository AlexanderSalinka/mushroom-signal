import Foundation

public enum SignalAlgorithm {
    public static func computeSignal(species: Species, weather: WeatherSnapshot, month: Int, flushTriggered: Bool) -> SpeciesSignal {
        let calendarScore = calendarFit(species: species, month: month)

        guard calendarScore > 0 else {
            return SpeciesSignal(species: species, score: 0, reason: "mimo hlavnej sezóny", flushTriggered: flushTriggered)
        }

        let tempScore = temperatureFit(species: species, weather: weather)
        let humidityScore = humidityFit(species: species, weather: weather)
        let rainScore = rainfallFit(species: species, weather: weather, flushTriggered: flushTriggered)

        let total = calendarScore + tempScore + humidityScore + rainScore
        let score = Int(total.rounded())

        let reason = reasonText(species: species, tempScore: tempScore, humidityScore: humidityScore, rainScore: rainScore, flushTriggered: flushTriggered)

        return SpeciesSignal(species: species, score: min(4, max(0, score)), reason: reason, flushTriggered: flushTriggered)
    }

    public static func calendarFit(species: Species, month: Int) -> Double {
        if species.fruitingMonths.contains(month) { return 1.0 }
        let previousMonth = month == 1 ? 12 : month - 1
        let nextMonth = month == 12 ? 1 : month + 1
        if species.fruitingMonths.contains(previousMonth) || species.fruitingMonths.contains(nextMonth) {
            return 0.5
        }
        return 0.0
    }

    static func temperatureFit(species: Species, weather: WeatherSnapshot) -> Double {
        let temp = weather.averageTempLast10DaysC
        if temp >= species.idealTempMinC && temp <= species.idealTempMaxC {
            return 1.0
        }
        let distance = temp < species.idealTempMinC ? species.idealTempMinC - temp : temp - species.idealTempMaxC
        return distance <= 3.0 ? 0.5 : 0.0
    }

    static func humidityFit(species: Species, weather: WeatherSnapshot) -> Double {
        let humidity = weather.averageHumidityLast10DaysPercent
        if humidity >= species.idealHumidityMinPercent && humidity <= species.idealHumidityMaxPercent {
            return 1.0
        }
        let distance = humidity < species.idealHumidityMinPercent ? species.idealHumidityMinPercent - humidity : humidity - species.idealHumidityMaxPercent
        return distance <= 10.0 ? 0.5 : 0.0
    }

    static func rainfallFit(species: Species, weather: WeatherSnapshot, flushTriggered: Bool) -> Double {
        let precipitation = weather.totalPrecipitationLast10DaysMm
        let baseScore: Double
        switch species.rainfallSensitivity {
        case .high:
            if precipitation >= 20 { baseScore = 1.0 }
            else if precipitation >= 8 { baseScore = 0.5 }
            else { baseScore = 0.0 }
        case .medium:
            if precipitation >= 10 { baseScore = 1.0 }
            else if precipitation >= 3 { baseScore = 0.5 }
            else { baseScore = 0.0 }
        case .low:
            baseScore = 1.0
        }

        guard flushTriggered else { return baseScore }

        let bonus: Double
        switch species.rainfallSensitivity {
        case .high: bonus = 1.0
        case .medium: bonus = 0.5
        case .low: bonus = 0.0
        }
        return min(1.0, baseScore + bonus)
    }

    static func reasonText(species: Species, tempScore: Double, humidityScore: Double, rainScore: Double, flushTriggered: Bool) -> String? {
        if flushTriggered && species.rainfallSensitivity != .low && tempScore > 0.0 && humidityScore > 0.0 {
            return "nedávno teplo a dážď — čoskoro môže prísť nová vlna"
        }
        if rainScore < 1.0 && species.rainfallSensitivity != .low {
            return "málo zrážok v poslednej dobe"
        }
        if tempScore < 1.0 {
            return "teplota mimo ideálneho rozsahu"
        }
        if humidityScore < 1.0 {
            return "vlhkosť mimo ideálneho rozsahu"
        }
        return nil
    }
}
