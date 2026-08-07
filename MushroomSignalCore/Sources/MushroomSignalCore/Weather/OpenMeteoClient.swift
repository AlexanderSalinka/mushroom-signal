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
            URLQueryItem(name: "daily", value: "temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum"),
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
        let humidity = decoded.daily.relativeHumidity2mMean.compactMap { $0 }
        let precipitation = decoded.daily.precipitationSum.compactMap { $0 }
        guard !temps.isEmpty, !humidity.isEmpty, !precipitation.isEmpty else {
            throw WeatherClientError.emptyDailyData
        }

        let averageTemp = temps.reduce(0, +) / Double(temps.count)
        let averageHumidity = humidity.reduce(0, +) / Double(humidity.count)
        let totalPrecipitation = precipitation.reduce(0, +)

        return WeatherSnapshot(
            regionId: region.id,
            averageTempLast10DaysC: averageTemp,
            averageHumidityLast10DaysPercent: averageHumidity,
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
            URLQueryItem(name: "daily", value: "temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum"),
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
            let humidity = pointResponse.daily.relativeHumidity2mMean.compactMap { $0 }
            let precipitation = pointResponse.daily.precipitationSum.compactMap { $0 }
            guard !temps.isEmpty, !humidity.isEmpty, !precipitation.isEmpty else { continue }
            result[point.id] = WeatherSnapshot(
                regionId: point.id,
                averageTempLast10DaysC: temps.reduce(0, +) / Double(temps.count),
                averageHumidityLast10DaysPercent: humidity.reduce(0, +) / Double(humidity.count),
                totalPrecipitationLast10DaysMm: precipitation.reduce(0, +),
                fetchedAt: Date()
            )
        }
        return result
    }

    public func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(region.latitude)),
            URLQueryItem(name: "longitude", value: String(region.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_mean,precipitation_sum"),
            URLQueryItem(name: "past_days", value: String(pastDays)),
            URLQueryItem(name: "forecast_days", value: "0"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoDailyResponse.self, from: data)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var result: [DailyWeather] = []
        for index in decoded.daily.time.indices {
            guard let date = dateFormatter.date(from: decoded.daily.time[index]),
                  let maxTemp = decoded.daily.temperature2mMax[index],
                  let meanTemp = decoded.daily.temperature2mMean[index],
                  let precipitation = decoded.daily.precipitationSum[index] else { continue }
            result.append(DailyWeather(date: date, meanTempC: meanTemp, maxTempC: maxTemp, precipitationMm: precipitation))
        }
        return result
    }
}

struct OpenMeteoResponse: Codable {
    struct Daily: Codable {
        let temperature2mMean: [Double?]
        let relativeHumidity2mMean: [Double?]
        let precipitationSum: [Double?]

        enum CodingKeys: String, CodingKey {
            case temperature2mMean = "temperature_2m_mean"
            case relativeHumidity2mMean = "relative_humidity_2m_mean"
            case precipitationSum = "precipitation_sum"
        }
    }
    let daily: Daily
}

struct OpenMeteoDailyResponse: Codable {
    struct Daily: Codable {
        let time: [String]
        let temperature2mMax: [Double?]
        let temperature2mMean: [Double?]
        let precipitationSum: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMean = "temperature_2m_mean"
            case precipitationSum = "precipitation_sum"
        }
    }
    let daily: Daily
}
