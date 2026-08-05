import Foundation

public enum SignalAlgorithm {
    public static func computeSignal(species: Species, weather: WeatherSnapshot, month: Int) -> SpeciesSignal {
        let calendarScore = calendarFit(species: species, month: month)

        guard calendarScore > 0 else {
            return SpeciesSignal(species: species, score: 0, reason: "mimo hlavnej sezóny")
        }

        let tempScore = temperatureFit(species: species, weather: weather)
        let rainScore = rainfallFit(species: species, weather: weather)
        let weatherScore = tempScore + rainScore

        let total = calendarScore == 1.0 ? 1.0 + weatherScore : weatherScore
        let score = Int(total.rounded())

        let reason = reasonText(species: species, tempScore: tempScore, rainScore: rainScore)

        return SpeciesSignal(species: species, score: min(3, max(0, score)), reason: reason)
    }

    static func calendarFit(species: Species, month: Int) -> Double {
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

    static func rainfallFit(species: Species, weather: WeatherSnapshot) -> Double {
        let precipitation = weather.totalPrecipitationLast10DaysMm
        switch species.rainfallSensitivity {
        case .high:
            if precipitation >= 20 { return 1.0 }
            if precipitation >= 8 { return 0.5 }
            return 0.0
        case .medium:
            if precipitation >= 10 { return 1.0 }
            if precipitation >= 3 { return 0.5 }
            return 0.0
        case .low:
            return precipitation >= 5 ? 1.0 : 0.5
        }
    }

    static func reasonText(species: Species, tempScore: Double, rainScore: Double) -> String? {
        if rainScore < 1.0 && species.rainfallSensitivity != .low {
            return "málo zrážok v poslednej dobe"
        }
        if tempScore < 1.0 {
            return "teplota mimo ideálneho rozsahu"
        }
        return nil
    }
}
