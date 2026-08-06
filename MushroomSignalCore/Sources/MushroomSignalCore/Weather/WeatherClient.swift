import Foundation

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
}
