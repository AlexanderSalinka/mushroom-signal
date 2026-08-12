import Foundation

/// Polygon boundaries for Slovakia's 8 kraje, for the map's per-region heat overlay.
/// Traced from Slovakia's official ZBGIS geographic database (Office of Geodesy,
/// Cartography and Cadastre of the Slovak Republic, geoportal.sk), which explicitly
/// states its data is free for all use including commercial — obtained via a third-party
/// GeoJSON repackaging (github.com/drakh/slovakia-gps-data) rather than the primary
/// source directly, since that mirror's format was immediately usable; the primary
/// source's own WFS/download service is the path to a cleaner first-party copy if this
/// is ever needed before a public release. Topology-preserving-simplified from the raw
/// 607-1905 points per region down to 168-384 (Douglas-Peucker, tolerance 0.004°,
/// ~400-450m at Slovakia's latitude) — every point shared between two adjacent regions'
/// original boundaries is simplified exactly once and spliced into both regions
/// identically, so borders still touch exactly after simplification (same guarantee the
/// prior hand-approximated data made, verified the same way: programmatically, not just
/// visually). Replaces the 2026-08-08 hand-drawn approximation entirely (kept in git
/// history) — see docs/superpowers/specs/2026-08-12-real-region-boundaries-design.md.
public enum RegionBoundaries {
    public static func polygon(for regionId: String) -> [(latitude: Double, longitude: Double)]? {
        coordinates[regionId]
    }

    private struct BoundaryPoint: Codable {
        let latitude: Double
        let longitude: Double
    }

    private static let coordinates: [String: [(latitude: Double, longitude: Double)]] = {
        guard let url = Bundle.module.url(forResource: "region-boundaries", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [BoundaryPoint]].self, from: data) else {
            return [:]
        }
        return decoded.mapValues { points in
            points.map { (latitude: $0.latitude, longitude: $0.longitude) }
        }
    }()
}
