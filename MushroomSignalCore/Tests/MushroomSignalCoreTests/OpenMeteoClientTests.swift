import XCTest
@testable import MushroomSignalCore

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OpenMeteoClientTests: XCTestCase {
    private func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let region = Region(id: "zilinsky", nameSk: "Žilinský kraj", latitude: 49.2231, longitude: 18.7394)

    func testFetchSnapshotParsesAverageTempAndTotalPrecipitation() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [10.0, 12.0, 14.0], "precipitation_sum": [0.0, 5.0, 3.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let snapshot = try await client.fetchSnapshot(for: region)

        XCTAssertEqual(snapshot.averageTempLast10DaysC, 12.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalPrecipitationLast10DaysMm, 8.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.regionId, "zilinsky")
    }

    func testFetchSnapshotIgnoresNullDailyValues() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [10.0, null, 14.0], "precipitation_sum": [null, 5.0, 3.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let snapshot = try await client.fetchSnapshot(for: region)

        XCTAssertEqual(snapshot.averageTempLast10DaysC, 12.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalPrecipitationLast10DaysMm, 8.0, accuracy: 0.001)
    }

    func testFetchSnapshotThrowsOnNonOKStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let client = OpenMeteoClient(session: makeMockedSession())

        do {
            _ = try await client.fetchSnapshot(for: region)
            XCTFail("Expected invalidResponse error")
        } catch WeatherClientError.invalidResponse {
            // expected
        }
    }

    func testFetchSnapshotThrowsOnEmptyDailyData() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [], "precipitation_sum": [] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())

        do {
            _ = try await client.fetchSnapshot(for: region)
            XCTFail("Expected emptyDailyData error")
        } catch WeatherClientError.emptyDailyData {
            // expected
        }
    }

    func testFetchSnapshotsDecodesMultiLocationArrayInOrder() async throws {
        let points = [
            GridPoint(id: "grid-00", latitude: 48.1, longitude: 17.1),
            GridPoint(id: "grid-01", latitude: 49.2, longitude: 18.7)
        ]
        let json = """
        [
          { "daily": { "temperature_2m_mean": [10.0, 12.0], "precipitation_sum": [1.0, 3.0] } },
          { "daily": { "temperature_2m_mean": [20.0, 22.0], "precipitation_sum": [5.0, 5.0] } }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchSnapshots(for: points)

        XCTAssertEqual(result.count, 2)
        guard let snapshot0 = result["grid-00"] else { XCTFail("Missing grid-00"); return }
        XCTAssertEqual(snapshot0.averageTempLast10DaysC, 11.0, accuracy: 0.001)
        XCTAssertEqual(snapshot0.totalPrecipitationLast10DaysMm, 4.0, accuracy: 0.001)
        guard let snapshot1 = result["grid-01"] else { XCTFail("Missing grid-01"); return }
        XCTAssertEqual(snapshot1.averageTempLast10DaysC, 21.0, accuracy: 0.001)
    }

    func testFetchSnapshotsOmitsPointsWithEmptyDailyData() async throws {
        let points = [
            GridPoint(id: "grid-00", latitude: 48.1, longitude: 17.1),
            GridPoint(id: "grid-01", latitude: 49.2, longitude: 18.7)
        ]
        let json = """
        [
          { "daily": { "temperature_2m_mean": [], "precipitation_sum": [] } },
          { "daily": { "temperature_2m_mean": [20.0], "precipitation_sum": [5.0] } }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchSnapshots(for: points)

        XCTAssertNil(result["grid-00"])
        XCTAssertNotNil(result["grid-01"])
    }

    func testFetchSnapshotsReturnsEmptyForEmptyInput() async throws {
        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchSnapshots(for: [])
        XCTAssertTrue(result.isEmpty)
    }
}
