import Foundation

/// Approximate polygon boundaries for Slovakia's 8 kraje, for the map's per-region heat
/// overlay. Explicitly not survey-grade — hand-approximated during the 2026-08-08 UI
/// redesign, sanctioned by Alexander for this alpha pass (see CLAUDE.md's Project
/// Conventions). Coordinates are (latitude, longitude) pairs forming each kraj's rough
/// outline, ordered to trace a simple (non-self-intersecting) polygon.
public enum RegionBoundaries {
    public static func polygon(for regionId: String) -> [(latitude: Double, longitude: Double)]? {
        coordinates[regionId]
    }

    private static let coordinates: [String: [(latitude: Double, longitude: Double)]] = [
        "bratislavsky": [
            (48.00, 16.85), (48.30, 16.95), (48.30, 17.25), (48.05, 17.30), (47.90, 17.05)
        ],
        "trnavsky": [
            (47.75, 17.10), (48.05, 17.05), (48.30, 17.25), (48.30, 17.60), (48.05, 17.95),
            (47.75, 17.75), (47.70, 17.35)
        ],
        "trenciansky": [
            (48.60, 17.35), (48.95, 17.55), (49.25, 18.05), (49.10, 18.55), (48.75, 18.45),
            (48.55, 17.95), (48.50, 17.55)
        ],
        "nitriansky": [
            (47.70, 17.35), (48.05, 17.95), (48.30, 17.60), (48.55, 17.95), (48.50, 18.55),
            (48.20, 18.85), (47.80, 18.60), (47.70, 18.10)
        ],
        "zilinsky": [
            (48.95, 17.55), (49.25, 18.05), (49.60, 18.35), (49.55, 19.30), (49.20, 19.60),
            (48.95, 19.15), (48.75, 18.45), (49.10, 18.55)
        ],
        "banskobystricky": [
            (48.20, 18.85), (48.50, 18.55), (48.75, 18.45), (48.95, 19.15), (49.20, 19.60),
            (48.85, 20.25), (48.35, 20.05), (48.05, 19.50), (47.95, 18.95)
        ],
        "presovsky": [
            (48.85, 20.25), (49.20, 19.60), (49.55, 19.30), (49.60, 21.00), (49.50, 22.55),
            (48.95, 22.20), (48.60, 21.30), (48.65, 20.55)
        ],
        "kosicky": [
            (48.35, 20.05), (48.85, 20.25), (48.60, 21.30), (48.95, 22.20), (48.55, 22.55),
            (48.20, 21.90), (48.00, 21.00), (48.10, 20.35)
        ]
    ]
}
