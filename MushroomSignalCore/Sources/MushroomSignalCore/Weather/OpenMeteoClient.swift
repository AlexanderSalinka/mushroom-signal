import Foundation

public enum WeatherClientError: Error, Equatable {
    case invalidResponse
    case emptyDailyData
}

public struct OpenMeteoClient: WeatherClient {
    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared, baseURL: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(region.latitude)),
            URLQueryItem(name: "longitude", value: String(region.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_mean,precipitation_sum"),
            URLQueryItem(name: "past_days", value: "10"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let temps = decoded.daily.temperature2mMean.compactMap { $0 }
        let precipitation = decoded.daily.precipitationSum.compactMap { $0 }
        guard !temps.isEmpty, !precipitation.isEmpty else {
            throw WeatherClientError.emptyDailyData
        }

        let averageTemp = temps.reduce(0, +) / Double(temps.count)
        let totalPrecipitation = precipitation.reduce(0, +)

        return WeatherSnapshot(
            regionId: region.id,
            averageTempLast10DaysC: averageTemp,
            totalPrecipitationLast10DaysMm: totalPrecipitation,
            fetchedAt: Date()
        )
    }

    public func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        guard !points.isEmpty else { return [:] }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: points.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: points.map { String($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "daily", value: "temperature_2m_mean,precipitation_sum"),
            URLQueryItem(name: "past_days", value: "10"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode([OpenMeteoResponse].self, from: data)
        guard decoded.count == points.count else {
            throw WeatherClientError.invalidResponse
        }

        var result: [String: WeatherSnapshot] = [:]
        for (point, pointResponse) in zip(points, decoded) {
            let temps = pointResponse.daily.temperature2mMean.compactMap { $0 }
            let precipitation = pointResponse.daily.precipitationSum.compactMap { $0 }
            guard !temps.isEmpty, !precipitation.isEmpty else { continue }
            result[point.id] = WeatherSnapshot(
                regionId: point.id,
                averageTempLast10DaysC: temps.reduce(0, +) / Double(temps.count),
                totalPrecipitationLast10DaysMm: precipitation.reduce(0, +),
                fetchedAt: Date()
            )
        }
        return result
    }
}

struct OpenMeteoResponse: Codable {
    struct Daily: Codable {
        let temperature2mMean: [Double?]
        let precipitationSum: [Double?]

        enum CodingKeys: String, CodingKey {
            case temperature2mMean = "temperature_2m_mean"
            case precipitationSum = "precipitation_sum"
        }
    }
    let daily: Daily
}
