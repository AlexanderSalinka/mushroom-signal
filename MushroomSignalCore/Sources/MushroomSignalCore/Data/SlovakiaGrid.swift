import Foundation

/// Generates an evenly-spaced sample grid over Slovakia's bounding box, trimmed by a rough
/// diamond-shaped filter approximating the country's silhouette. Not survey-grade — these points
/// only drive a heat-map visualization, not an authoritative boundary claim (see v2 spec, Out of Scope).
public enum SlovakiaGrid {
    /// Upper bound widened from 49.6 to 49.65 on 2026-08-12 when RegionBoundaries switched
    /// to real ZBGIS government boundary data — Slovakia's true northernmost extent
    /// (~49.6137, in Žilinský kraj) sits just past the old hand-approximated data's range.
    /// Confirmed this doesn't change generate()'s actual grid points: the 0.8° latitudeStep
    /// still lands its last row at 49.3 either way (49.3 + 0.8 = 50.1, past both the old and
    /// new upper bound) — only the declared range constant changes, not the heat-map grid.
    public static let latitudeRange: ClosedRange<Double> = 47.7...49.65
    public static let longitudeRange: ClosedRange<Double> = 16.8...22.6

    private static let latitudeStep = 0.8
    private static let longitudeStep = 1.2
    /// Sum of normalized distance-from-center along each axis must stay within this to be kept —
    /// trims the bounding box's four corners, which fall outside Slovakia's actual silhouette.
    private static let diamondThreshold = 1.4

    public static func generate() -> [GridPoint] {
        let latMid = (latitudeRange.lowerBound + latitudeRange.upperBound) / 2
        let lonMid = (longitudeRange.lowerBound + longitudeRange.upperBound) / 2
        let latSpan = (latitudeRange.upperBound - latitudeRange.lowerBound) / 2
        let lonSpan = (longitudeRange.upperBound - longitudeRange.lowerBound) / 2

        var points: [GridPoint] = []
        var index = 0
        var lat = latitudeRange.lowerBound
        while lat <= latitudeRange.upperBound + 1e-9 {
            var lon = longitudeRange.lowerBound
            while lon <= longitudeRange.upperBound + 1e-9 {
                let normalizedLat = abs(lat - latMid) / latSpan
                let normalizedLon = abs(lon - lonMid) / lonSpan
                if normalizedLat + normalizedLon <= diamondThreshold {
                    points.append(GridPoint(id: "grid-\(String(format: "%02d", index))", latitude: lat, longitude: lon))
                    index += 1
                }
                lon += longitudeStep
            }
            lat += latitudeStep
        }
        return points
    }
}
