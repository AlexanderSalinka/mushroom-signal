import MushroomSignalCore

actor StubWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}

    private var snapshots: [WeatherSnapshot?]
    private var callIndex = 0
    private let gridSnapshots: [String: WeatherSnapshot]
    private let gridShouldThrow: Bool
    private let dailyWeather: [DailyWeather]
    private let dailyShouldThrow: Bool
    private var dailyWeatherSequence: [[DailyWeather]?]?
    private var dailyCallIndex = 0

    init(snapshots: [WeatherSnapshot?], gridSnapshots: [String: WeatherSnapshot] = [:], gridShouldThrow: Bool = false, dailyWeather: [DailyWeather] = [], dailyShouldThrow: Bool = false, dailyWeatherSequence: [[DailyWeather]?]? = nil) {
        self.snapshots = snapshots
        self.gridSnapshots = gridSnapshots
        self.gridShouldThrow = gridShouldThrow
        self.dailyWeather = dailyWeather
        self.dailyShouldThrow = dailyShouldThrow
        self.dailyWeatherSequence = dailyWeatherSequence
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
        if let sequence = dailyWeatherSequence {
            let index = min(dailyCallIndex, sequence.count - 1)
            dailyCallIndex += 1
            guard let result = sequence[index] else { throw StubError() }
            return result
        }
        if dailyShouldThrow { throw StubError() }
        return dailyWeather
    }
}

actor DelayedWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}
    private var callCount = 0

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        throw StubError()
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        [:]
    }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(200))
            throw StubError()
        }
        return [DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 2, humidityPercent: 75)]
    }
}
