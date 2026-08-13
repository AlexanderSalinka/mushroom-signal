// MushroomSignalWidget/ShortlistWidgetView.swift
import SwiftUI
import WidgetKit
import MushroomSignalCore

struct ShortlistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShortlistEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            case .systemLarge:
                largeBody
            default:
                smallBody
            }
        }
        .padding(DesignSystem.spacingMedium)
        .containerBackground(for: .widget) {
            DesignSystem.Colors.cardBackground
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            compactRegionHeader
            infoBand(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
            infoBand(icon: DropletShape(), color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(entry.signals.prefix(4), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.captionSize * 0.5, weight: .semibold), showLatin: false)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            compactRegionHeader
            compactWeatherTileRow
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entry.signals.prefix(4), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.captionSize * 0.52, weight: .semibold), showLatin: false, inlineLatin: true)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
            regionHeader
            weatherTileRow
            if entry.signals.isEmpty {
                emptyStateIfNeeded
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(entry.signals.prefix(3).enumerated()), id: \.element.species.id) { index, signal in
                        podiumSquare(rank: index + 1, signal: signal, isFirst: index == 0)
                    }
                }
                VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                    ForEach(Array(entry.signals.dropFirst(3).prefix(3).enumerated()), id: \.element.species.id) { index, signal in
                        rankedRow(rank: index + 4, signal: signal)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sk_SK")
        formatter.dateFormat = "d. MMMM · HH:mm"
        return formatter
    }()

    private var regionHeader: some View {
        VStack(spacing: 1) {
            Text(entry.region.nameSk)
                .font(.system(size: DesignSystem.captionSize * 0.65, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.85))
            Text(Self.headerDateFormatter.string(from: entry.date))
                .font(.system(size: DesignSystem.captionSize * 0.55))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    /// `.systemSmall`/`.systemMedium`-only compact header: single line (name + date combined),
    /// used instead of `regionHeader` because the real ~155pt content budget for both families
    /// can't fit two full-height header lines plus everything else. `.systemLarge` keeps the
    /// two-line `regionHeader` above, untouched.
    private var compactRegionHeader: some View {
        Text("\(entry.region.nameSk) · \(Self.headerDateFormatter.string(from: entry.date))")
            .font(.system(size: DesignSystem.captionSize * 0.42, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    private var sevenDayAverage: WeatherSnapshot? {
        WeatherSnapshot.derive(regionId: entry.region.id, from: entry.dailyWeather, windowDays: 7, asOf: entry.date)
    }

    private var todayWeather: DailyWeather? {
        entry.dailyWeather.first { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
    }

    private var temperatureHeadline: String {
        guard let todayWeather else { return "—" }
        return "\(Int(todayWeather.minTempC.rounded()))° / \(Int(todayWeather.maxTempC.rounded()))°"
    }

    private var temperatureSubline: String? {
        guard let sevenDayAverage else { return nil }
        return "Týždenný priemer: \(Int(sevenDayAverage.averageTempLast10DaysC.rounded()))°C"
    }

    private var upcomingRainEvent: RainEvent? {
        UpcomingRainDetector.nextTriggerEvent(in: entry.dailyWeather, asOf: entry.date)
    }

    private var lastRainfall: (date: Date, precipitationMm: Double)? {
        MostRecentRainfall.find(in: entry.dailyWeather, asOf: entry.date)
    }

    private func daysBetween(_ from: Date, _ to: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from), to: Calendar.current.startOfDay(for: to)).day ?? 1)
    }

    /// Unclamped day difference — unlike `daysBetween(_:_:)` (which floors at 1 and thus can
    /// never report "today"), this can return 0. Feeds `slovakDaysUntil`/`slovakDaysAgo` below,
    /// which need the real same-day case to say "dnes" instead of "1 day ago/until".
    private func rawDaysBetween(_ from: Date, _ to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from), to: Calendar.current.startOfDay(for: to)).day ?? 0
    }

    /// Slovak "in N days" phrasing, with correct grammatical case for the day count:
    /// 0 → "dnes" (today), 1 → singular "deň", 2–4 → paucal "dni", 5+ → plural "dní".
    private func slovakDaysUntil(_ days: Int) -> String {
        switch days {
        case ..<1: return "dnes"
        case 1: return "O 1 deň"
        case 2, 3, 4: return "O \(days) dni"
        default: return "O \(days) dní"
        }
    }

    /// Slovak "N days ago" phrasing, with correct grammatical case for the day count:
    /// 0 → "dnes" (today), 1 → singular "dňom", 2+ → "dňami".
    private func slovakDaysAgo(_ days: Int) -> String {
        switch days {
        case ..<1: return "dnes"
        case 1: return "pred 1 dňom"
        default: return "pred \(days) dňami"
        }
    }

    private var rainHeadline: String {
        if let event = upcomingRainEvent {
            return "\(slovakDaysUntil(rawDaysBetween(entry.date, event.date))) · \(String(format: "%.0f", event.precipitationMm)) mm"
        }
        if let last = lastRainfall {
            return "Naposledy \(slovakDaysAgo(rawDaysBetween(last.date, entry.date)))"
        }
        return "Bez výraznejšieho dažďa"
    }

    private var rainSubline: String? {
        guard let last = lastRainfall else { return nil }
        if upcomingRainEvent != nil {
            return "Naposledy \(slovakDaysAgo(rawDaysBetween(last.date, entry.date))) · \(String(format: "%.0f", last.precipitationMm)) mm"
        }
        return "\(String(format: "%.0f", last.precipitationMm)) mm"
    }

    /// `.systemSmall`'s weather band — circle-badge-plus-text, full-width. See this task's
    /// note above: this is this plan's own synthesis, not spec-verbatim code.
    ///
    /// Sized specifically for `.systemSmall`'s ~155pt content budget (task-3 fix round,
    /// 2026-08-13) — exclusively used by `smallBody`, so shrinking it here cannot affect any
    /// other family.
    private func infoBand(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 14, height: 14)
                icon
                    .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(headline)
                    .font(.system(size: DesignSystem.captionSize * 0.46, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                if let subline {
                    Text(subline)
                        .font(.system(size: DesignSystem.captionSize * 0.34))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.3))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.3)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }

    private func squareTile(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
        VStack(spacing: 1) {
            icon
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color.opacity(0.25)))
            Text(headline)
                .font(.system(size: DesignSystem.captionSize * 0.65, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud)
                .lineLimit(1)
            if let subline {
                Text(subline)
                    .font(.system(size: DesignSystem.captionSize * 0.5))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
                .stroke(color.opacity(0.45), lineWidth: 1)
        )
    }

    private var weatherTileRow: some View {
        HStack(spacing: 6) {
            squareTile(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
            squareTile(icon: DropletShape(), color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
        }
    }

    /// `.systemMedium`-only smaller sibling of `squareTile`/`weatherTileRow` (task-3 fix round,
    /// 2026-08-13). `squareTile`/`weatherTileRow` above are also used by `.systemLarge` and are
    /// left completely untouched; this is a separate pair of helpers so shrinking medium's tiles
    /// cannot affect large's rendering.
    private func compactSquareTile(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
        VStack(spacing: 0) {
            icon
                .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                .frame(width: 8, height: 8)
                .frame(width: 15, height: 15)
                .background(Circle().fill(color.opacity(0.25)))
            Text(headline)
                .font(.system(size: DesignSystem.captionSize * 0.46, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud)
            if let subline {
                Text(subline)
                    .font(.system(size: DesignSystem.captionSize * 0.36))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.3))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.3)
                .stroke(color.opacity(0.45), lineWidth: 1)
        )
    }

    private var compactWeatherTileRow: some View {
        HStack(spacing: 4) {
            compactSquareTile(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
            compactSquareTile(icon: DropletShape(), color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
        }
    }

    @ViewBuilder
    private var emptyStateIfNeeded: some View {
        if entry.signals.isEmpty {
            let size: Double = {
                switch family {
                case .systemSmall, .systemMedium:
                    return DesignSystem.captionSize * 0.5
                default:
                    return DesignSystem.bodySize
                }
            }()
            Text("Žiadne údaje")
                .font(.system(size: size))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
        }
    }

    /// - Parameter inlineLatin: When true (medium layout only), the latin name is appended inline after
    ///   the common name on the same line, using medium's extra width instead of a second line of height.
    ///   Mutually exclusive with `showLatin` (large's two-line form) in practice, but not enforced structurally.
    ///
    /// Only ever called from `smallBody`/`mediumBody` (large uses `podiumSquare`/`rankedRow`
    /// instead) — its internal caption-sized text (`latinText`, the score dots, and the dead
    /// `showLatin` branch, unreachable since neither live call site passes `showLatin: true`)
    /// was shrunk in the task-3 fix round, 2026-08-13, alongside the `nameFont` callers already
    /// pass in. This cannot affect `.systemLarge`.
    private func row(for signal: SpeciesSignal, nameFont: Font, showLatin: Bool, inlineLatin: Bool = false) -> some View {
        let clampedScore = max(0, min(4, signal.score))
        let hasWarning = signal.species.edibility != .edible
        let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
        let nameText = Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
            .font(nameFont)
            .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
        let latinText = Text(" · " + signal.species.latinName)
            .font(.system(size: DesignSystem.captionSize * 0.55).italic())
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
        return HStack {
            VStack(alignment: .leading, spacing: 0) {
                if inlineLatin {
                    (nameText + latinText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    nameText
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if showLatin {
                        Text(signal.species.latinName)
                            .font(.system(size: DesignSystem.captionSize * 0.55).italic())
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer()
            Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
                .font(.system(size: DesignSystem.captionSize * 0.55))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }

    private func podiumSquare(rank: Int, signal: SpeciesSignal, isFirst: Bool) -> some View {
        let hasWarning = signal.species.edibility != .edible
        let color = hasWarning ? DesignSystem.warningColor(for: signal.species.edibility) : DesignSystem.Colors.mossAccent
        return VStack(spacing: 2) {
            MushroomShape()
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: isFirst ? 30 : 22, height: isFirst ? 30 : 22)
            Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                .font(.system(size: isFirst ? DesignSystem.captionSize * 0.7 : DesignSystem.captionSize * 0.6, weight: .bold))
                .foregroundStyle(hasWarning ? color : DesignSystem.Colors.cloud)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(String(repeating: "●", count: max(0, min(4, signal.score))) + String(repeating: "○", count: 4 - max(0, min(4, signal.score))))
                .font(.system(size: DesignSystem.captionSize * 0.5))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background((hasWarning ? color : DesignSystem.Colors.mossAccent).opacity(isFirst ? 0.26 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
                .stroke((hasWarning ? color : DesignSystem.Colors.mossAccent).opacity(isFirst ? 0.6 : 0.4), lineWidth: 1)
        )
    }

    private func rankedRow(rank: Int, signal: SpeciesSignal) -> some View {
        let hasWarning = signal.species.edibility != .edible
        let color = hasWarning ? DesignSystem.warningColor(for: signal.species.edibility) : DesignSystem.Colors.cloud
        return HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: DesignSystem.captionSize * 0.55))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.4))
                .frame(width: 14, alignment: .trailing)
            Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                .font(.system(size: DesignSystem.captionSize * 0.7, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer()
            Text(String(repeating: "●", count: max(0, min(4, signal.score))) + String(repeating: "○", count: 4 - max(0, min(4, signal.score))))
                .font(.system(size: DesignSystem.captionSize * 0.55))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }
}

private func previewSignal(name: String, latin: String, edibility: Edibility, score: Int) -> SpeciesSignal {
    SpeciesSignal(
        species: Species(
            id: name,
            commonNameSk: name,
            latinName: latin,
            edibility: edibility,
            fruitingMonths: [8, 9, 10],
            idealTempMinC: 8,
            idealTempMaxC: 18,
            idealHumidityMinPercent: 60,
            idealHumidityMaxPercent: 90,
            rainfallSensitivity: .medium,
            habitat: "listnatý les",
            regionalAffinity: [RegionDatabase.all[4].id]
        ),
        score: score,
        reason: nil,
        flushTriggered: false
    )
}

private func previewDailyWeather() -> [DailyWeather] {
    let now = Date()
    var days: [DailyWeather] = (-9...0).map { offset in
        DailyWeather(
            date: now.addingTimeInterval(Double(offset) * 86400),
            meanTempC: 18,
            maxTempC: offset == -3 ? 22 : 20,
            minTempC: 12,
            precipitationMm: offset == -3 ? 6 : 0,
            humidityPercent: 68
        )
    }
    // A forecast day 2 days out that qualifies FlushTriggerDetector's threshold
    // (maxTempC >= 26, precipitationMm >= 5) — exercises the upcoming-rain headline/subline.
    days.append(DailyWeather(date: now.addingTimeInterval(2 * 86400), meanTempC: 24, maxTempC: 27, minTempC: 19, precipitationMm: 8, humidityPercent: 75))
    return days
}

#Preview("Small", as: .systemSmall) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: previewDailyWeather())
}

#Preview("Medium", as: .systemMedium) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: previewDailyWeather())
}

#Preview("Large", as: .systemLarge) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 4),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Plávka zelenkastá", latin: "Russula virescens", edibility: .caution, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: previewDailyWeather())
}
