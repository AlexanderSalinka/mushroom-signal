import SwiftUI

/// Maps active species to map colors in the order they were toggled on, cycling the curated
/// palette if more species are active than there are distinct colors (v2 spec §2).
public enum SpeciesColorAssigner {
    public static func colors(forActiveSpeciesInToggleOrder speciesIDs: [String]) -> [String: Color] {
        let palette = DesignSystem.Colors.speciesPalette
        guard !palette.isEmpty else { return [:] }
        var result: [String: Color] = [:]
        for (index, id) in speciesIDs.enumerated() {
            result[id] = palette[index % palette.count]
        }
        return result
    }
}
