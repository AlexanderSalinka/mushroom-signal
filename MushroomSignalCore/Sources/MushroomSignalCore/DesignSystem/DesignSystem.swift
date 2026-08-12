import SwiftUI

public enum DesignSystem {
    public static let goldenRatio: Double = 1.618

    private static let spacingUnit: Double = 8
    public static let spacingSmall: Double = spacingUnit
    public static let spacingMedium: Double = spacingSmall * goldenRatio
    public static let spacingLarge: Double = spacingMedium * goldenRatio
    public static let spacingExtraLarge: Double = spacingLarge * goldenRatio
    /// A tighter-than-`spacingSmall` gap for compact stacked text (e.g. a name directly above its subtitle).
    /// Below the smallest deliberate step in the golden-ratio scale, so it's defined as a fraction of
    /// `spacingSmall` rather than extending the scale downward.
    public static let spacingTight: Double = spacingSmall / 4

    // Floor raised to 20pt app-wide (including the widget) 2026-08-08 — "too small to
    // read" was the exact complaint. Mechanically reapplying goldenRatio's full multiplicative
    // compounding from a 20pt floor would push heroSize to ~85pt (20 * 1.618^3), which is
    // absurd for a widget's hero row. This scale is a gentler graduated progression that
    // clears the floor without that blowup — deliberately not golden-ratio-derived.
    public static let captionSize: Double = 20
    public static let bodySize: Double = 24
    public static let titleSize: Double = 28
    public static let heroSize: Double = 36

    public static let cardCornerRadius: Double = 24
    public static let thumbnailHeight: Double = 70
    /// Minimum column width for the adaptive species-card grid (Zoznam, Mapa library) — a
    /// starting point for "eye-catching but not too big," not an enforced exact size. See
    /// the 2026-08-08 UI redesign spec §1.
    public static let speciesCardMinWidth: Double = 340
    /// Fixed photo-area height for `SpeciesCardView` — a fixed height (not an aspect-ratio
    /// modifier on the container) is required here: the card sits in a `LazyVGrid` row with
    /// no vertical size constraint, and `.aspectRatio(_, contentMode: .fill)` on an
    /// unconstrained container grows without bound instead of capping to a card-sized photo
    /// area. ~4:3 against `speciesCardMinWidth`.
    public static let speciesCardPhotoHeight: Double = 255
    public static let borderWidth: Double = 2
    public static let iconButtonPadding: Double = 4
    /// InteractiveMapView's starting height before the user drags `MapResizeHandle`.
    public static let mapDefaultHeight: Double = 400
    /// Floor for InteractiveMapView's height so its legend/loading overlay stays legible even if the
    /// window is resized right down to ContentView's declared minHeight.
    public static let mapMinimumHeight: Double = 220
    /// Ceiling for InteractiveMapView's drag-resized height — generous enough that the map can be
    /// dragged roughly square against a typical window width, not just its original fixed rectangle.
    public static let mapMaximumHeight: Double = 900
    /// SpeciesDetailView's horizontal photo gallery cell size (~4:3, sized for a comfortable
    /// horizontal-scroll thumbnail — distinct from the smaller list-row `thumbnailHeight`).
    public static let detailPhotoWidth: Double = 220
    public static let detailPhotoHeight: Double = 160
    /// InteractiveMapView's legend swatch diameter.
    public static let legendDotSize: Double = 8
    /// Score-dot glyph size inside a map marker — a decorative map-icon scale, matching the
    /// precedent set by `legendDotSize`. Not subject to the 20pt body-text floor, which governs
    /// readable text, not small status glyphs.
    public static let mapMarkerDotSize: Double = 6
    /// Height of the trend/weather charts (SpeciesDetailView's score trend, Predpoveď's daily
    /// weather strip) — shared so both charts read as one visual family.
    public static let trendChartHeight: Double = 120
    /// Predpoveď's numbered rank badge (top-3 picks) — sized with headroom for a bold caption-size
    /// digit inside a circle, not just the digit's own bounding box.
    public static let rankBadgeSize: Double = 26
    /// Corner radius for Predpoveď's daily weather bar chart marks.
    public static let chartBarCornerRadius: Double = 7
    /// Predpoveď's season-calendar chip — small color-coded swatch dot before each species name.
    public static let chipDotSize: Double = 8
    /// Predpoveď's season-calendar chip — fully rounded pill shape, matching the approved mockup.
    public static let chipCornerRadius: Double = 100
    /// Locked opacity multiplier on `CanopyLightView`'s light-blob layer — approved via
    /// interactive mockup calibration, 2026-08-11. Not user-adjustable in the shipped app.
    public static let canopyLightIntensity: Double = 0.66
    /// Opacity of the procedural grain texture applied to `forestMid`/`forestDeep` card
    /// fills — a whisper of bark/leaf texture, never behind running text or chart marks.
    public static let grainOpacity: Double = 0.05
    /// Opacity of `ForestDivider`'s bark-toned gradient line.
    public static let forestDividerOpacity: Double = 0.7
    /// Fixed size (both dimensions) of `CompactSpeciesCardView` — deliberately NOT part of
    /// an adaptive grid; the grid's column *count* reflows on window resize, this size does
    /// not. Picked from the mockup's ~110-130pt range.
    public static let compactCardSize: Double = 120
    /// `CompactSpeciesCardView`'s rank-badge / sunrise-badge circle diameter.
    public static let compactCardBadgeSize: Double = 18
    /// Height of each row (heat, rain) in Predpoveď's simplified two-row daily chart.
    public static let rainHeatChartRowHeight: Double = 56
    /// `ForestPanel`'s corner radius — the frosted-glass section container wrapping each
    /// Predpoveď section (chart, top picks, rain alert, season calendar).
    public static let panelCornerRadius: Double = 18
    /// `ForestPanel`'s translucent fill opacity, over `Colors.forestDeep`.
    public static let panelFillOpacity: Double = 0.55
    /// `ForestPanel`'s hairline border opacity, over `Colors.cloud`.
    public static let panelBorderOpacity: Double = 0.08
    /// `ForestPanel`'s drop shadow radius, giving it depth against the page background.
    public static let panelShadowRadius: Double = 12
    /// `WeatherRainChartView`'s temperature panel height (line chart, y-axis only, no x-axis —
    /// the rain panel below carries the shared date axis for both).
    public static let chartTempPanelHeight: Double = 90
    /// `WeatherRainChartView`'s rain panel height — includes its own y-axis and the shared
    /// x-axis band for both panels (the full chart-plus-axis height, not just the bar area).
    public static let chartRainPanelHeight: Double = 72
    /// `WeatherRainChartView`'s x-axis day-of-month tick label size. Chart chrome, not running
    /// body text — not subject to the 20pt text floor, same precedent as `mapMarkerDotSize`'s
    /// documented exception above.
    public static let chartAxisLabelSize: Double = 9
    /// Minimum width of each full-width season-calendar row (`seasonRow`) — mobile-phone width
    /// at minimum, so a species' full common name is never truncated.
    public static let seasonRowMinWidth: Double = 375
    /// Corner radius for the full-width season-calendar rows (replaces the old pill-shaped
    /// `chipCornerRadius` chips, which were too small to fit full names).
    public static let seasonRowCornerRadius: Double = 12
    /// `MushroomSignalHeroView`'s icon badge diameter for loud states (flush-happening,
    /// rain-incoming) — a real focal point, ~2x the 30pt inline droplet badge it replaces.
    public static let heroIconBadgeSize: Double = 64
    /// `MushroomSignalHeroView`'s icon glyph size inside `heroIconBadgeSize`, loud states —
    /// ~53% of the badge, matching the glyph-to-badge ratio the replaced view already used
    /// (15pt glyph inside a 30pt badge).
    public static let heroIconGlyphSize: Double = 34
    /// `MushroomSignalHeroView`'s icon badge diameter for quiet states (near-miss, no-rain) —
    /// deliberately smaller than the loud badge, but still well above the 20pt text floor so
    /// "quiet" never reads as an unfinished/omitted state.
    public static let heroIconBadgeSizeQuiet: Double = 40
    /// `MushroomSignalHeroView`'s icon glyph size inside `heroIconBadgeSizeQuiet`, quiet
    /// states — same ~53% ratio as the loud badge/glyph pair.
    public static let heroIconGlyphSizeQuiet: Double = 21
    /// `MushroomSignalHeroView`'s mini temp-line panel height (loud states only) — ~40% of
    /// `chartTempPanelHeight`, condensed for a hero-panel preview, not a full chart.
    public static let heroSparklineTempHeight: Double = 36
    /// `MushroomSignalHeroView`'s mini rain-bars panel height (loud states only) — ~40% of
    /// `chartRainPanelHeight`, same condensation ratio as `heroSparklineTempHeight`.
    public static let heroSparklineRainHeight: Double = 28

    public enum Colors {
        public static let forestDeep = Color(red: 0.11, green: 0.16, blue: 0.11)
        public static let forestMid = Color(red: 0.18, green: 0.25, blue: 0.16)
        public static let bark = Color(red: 0.29, green: 0.20, blue: 0.13)
        public static let water = Color(red: 0.30, green: 0.48, blue: 0.52)
        public static let cloud = Color(red: 0.94, green: 0.92, blue: 0.87)
        public static let mossAccent = Color(red: 0.42, green: 0.56, blue: 0.30)
        public static let danger = Color(red: 0.72, green: 0.24, blue: 0.20)
        public static let caution = Color(red: 0.85, green: 0.60, blue: 0.13)
        public static let speciesPalette: [Color] = [
            Color(red: 0.90, green: 0.49, blue: 0.13), // amber
            Color(red: 0.36, green: 0.61, blue: 0.84), // sky blue
            Color(red: 0.80, green: 0.36, blue: 0.62), // magenta
            Color(red: 0.95, green: 0.82, blue: 0.25), // gold
            Color(red: 0.42, green: 0.75, blue: 0.70), // teal
            Color(red: 0.65, green: 0.44, blue: 0.86), // violet
            Color(red: 0.85, green: 0.35, blue: 0.32), // coral red
            Color(red: 0.55, green: 0.70, blue: 0.30)  // lime
        ]

        public static let cardBackground = LinearGradient(
            colors: [forestMid, forestDeep],
            startPoint: .top,
            endPoint: .bottom
        )

        /// One distinct color per kraj (matches `RegionDatabase.all`'s order), for the map's
        /// always-visible border outlines — lets regions be told apart by outline color alone,
        /// independent of `speciesPalette` which is a separate concept (species, not regions).
        public static let regionPalette: [Color] = [
            Color(red: 0.85, green: 0.45, blue: 0.40), // bratislavsky - terracotta
            Color(red: 0.90, green: 0.70, blue: 0.30), // trnavsky - amber
            Color(red: 0.55, green: 0.75, blue: 0.45), // trenciansky - sage
            Color(red: 0.40, green: 0.65, blue: 0.60), // nitriansky - teal
            Color(red: 0.45, green: 0.55, blue: 0.80), // zilinsky - periwinkle
            Color(red: 0.70, green: 0.50, blue: 0.80), // banskobystricky - lavender
            Color(red: 0.85, green: 0.55, blue: 0.65), // presovsky - rose
            Color(red: 0.55, green: 0.60, blue: 0.35)  // kosicky - olive
        ]
    }

    /// The Slovak warning label for a species' edibility, or nil when no warning applies.
    public static func warningLabelSk(for edibility: Edibility) -> String? {
        switch edibility {
        case .edible: return nil
        case .caution: return "⚠️ Opatrne"
        case .poisonous: return "⚠️ Jedovatá"
        }
    }

    /// The color a warning label/highlight should use for a species' edibility.
    public static func warningColor(for edibility: Edibility) -> Color {
        switch edibility {
        case .edible: return Colors.cloud
        case .caution: return Colors.caution
        case .poisonous: return Colors.danger
        }
    }
}
