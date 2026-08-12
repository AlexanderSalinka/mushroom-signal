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
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            infoBand(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
            infoBand(icon: DropletShape(), color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals.prefix(4), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            weatherTileRow
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals.prefix(4), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false, inlineLatin: true)
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
                    ForEach(Array(entry.signals.dropFirst(3).prefix(6).enumerated()), id: \.element.species.id) { index, signal in
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

    private var rainHeadline: String {
        if let event = upcomingRainEvent {
            return "O \(daysBetween(entry.date, event.date)) dní · \(String(format: "%.0f", event.precipitationMm)) mm"
        }
        if let last = lastRainfall {
            return "Naposledy pred \(daysBetween(last.date, entry.date)) dňami"
        }
        return "Bez výraznejšieho dažďa"
    }

    private var rainSubline: String? {
        guard let last = lastRainfall else { return nil }
        if upcomingRainEvent != nil {
            return "Naposledy pred \(daysBetween(last.date, entry.date)) dňami · \(String(format: "%.0f", last.precipitationMm)) mm"
        }
        return "\(String(format: "%.0f", last.precipitationMm)) mm"
    }

    /// `.systemSmall`'s weather band — circle-badge-plus-text, full-width. See this task's
    /// note above: this is this plan's own synthesis, not spec-verbatim code.
    private func infoBand(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
        HStack(spacing: DesignSystem.spacingSmall) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 26, height: 26)
                icon
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
            }
            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                Text(headline)
                    .font(.system(size: DesignSystem.captionSize * 0.8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                if let subline {
                    Text(subline)
                        .font(.system(size: DesignSystem.captionSize * 0.6))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
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
            if let subline {
                Text(subline)
                    .font(.system(size: DesignSystem.captionSize * 0.5))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                    .multilineTextAlignment(.center)
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

    @ViewBuilder
    private var emptyStateIfNeeded: some View {
        if entry.signals.isEmpty {
            Text("Žiadne údaje")
                .font(.system(size: DesignSystem.bodySize))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
        }
    }

    /// - Parameter inlineLatin: When true (medium layout only), the latin name is appended inline after
    ///   the common name on the same line, using medium's extra width instead of a second line of height.
    ///   Mutually exclusive with `showLatin` (large's two-line form) in practice, but not enforced structurally.
    private func row(for signal: SpeciesSignal, nameFont: Font, showLatin: Bool, inlineLatin: Bool = false) -> some View {
        let clampedScore = max(0, min(4, signal.score))
        let hasWarning = signal.species.edibility != .edible
        let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
        let nameText = Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
            .font(nameFont)
            .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
        let latinText = Text(" · " + signal.species.latinName)
            .font(.system(size: DesignSystem.captionSize).italic())
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
        return HStack {
            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
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
                            .font(.system(size: DesignSystem.captionSize).italic())
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer()
            Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
                .font(.system(size: DesignSystem.captionSize))
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
