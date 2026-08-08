import Foundation

public enum PhotoCacheError: Error, Equatable {
    case invalidResponse
}

/// Downloads a photo once and persists it to local disk; subsequent requests for the same
/// URL are served from disk with no network call. Photos are static content (a species'
/// representative photo doesn't change), so there is no expiry — this is a permanent cache,
/// not a time-limited one. Matches this app's zero-backend, local-only architecture.
public struct PhotoCache: Sendable {
    private let session: URLSession
    private let cacheDirectory: URL

    public init(session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.session = session
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheDirectory = base.appendingPathComponent("SpeciesPhotos", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    public func cachedImageData(for url: URL) async throws -> Data {
        let cacheFileURL = cacheDirectory.appendingPathComponent(cacheKey(for: url))

        if let cached = try? Data(contentsOf: cacheFileURL) {
            return cached
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PhotoCacheError.invalidResponse
        }

        try? data.write(to: cacheFileURL)
        return data
    }

    private func cacheKey(for url: URL) -> String {
        let lastComponent = url.lastPathComponent.isEmpty ? "photo" : url.lastPathComponent
        var hasher = Hasher()
        hasher.combine(url.absoluteString)
        let digest = String(format: "%08x", UInt32(bitPattern: Int32(truncatingIfNeeded: hasher.finalize())))
        return "\(digest)-\(lastComponent)"
    }
}
