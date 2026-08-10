import MushroomSignalCore

actor StubWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}

    private var snapshots: [WeatherSnapshot?]
    private var callIndex = 0
    private let gridSnapshots: [String: WeatherSnapshot]
    private let gridShouldThrow: Bool
    private let dailyWeather: [DailyWeather]
    private let dailyShouldThrow: Bool

    init(snapshots: [WeatherSnapshot?], gridSnapshots: [String: WeatherSnapshot] = [:], gridShouldThrow: Bool = false, dailyWeather: [DailyWeather] = [], dailyShouldThrow: Bool = false) {
        self.snapshots = snapshots
        self.gridSnapshots = gridSnapshots
        self.gridShouldThrow = gridShouldThrow
        self.dailyWeather = dailyWeather
        self.dailyShouldThrow = dailyShouldThrow
    }

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        let index = min(callIndex, snapshots.count - 1)
        callIndex += 1
        guard let snapshot = snapshots[index] else { throw StubError() }
        return snapshot
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        if gridShouldThrow { throw StubError() }
        return gridSnapshots
    }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        if dailyShouldThrow { throw StubError() }
        return dailyWeather
    }
}

actor DelayedWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}
    private var callCount = 0

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(200))
            throw StubError()
        }
        return WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        [:]
    }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        []
    }
}
