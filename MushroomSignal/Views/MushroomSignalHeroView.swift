// MushroomSignal/Views/MushroomSignalHeroView.swift
import SwiftUI
import AppKit
import MushroomSignalCore

/// Replaces the old plain-text rain-incoming section — one prominent panel combining the
/// temperature+rain trigger state, a mini chart (loud states only), and region/season
/// context. See docs/superpowers/specs/2026-08-12-mushroom-signal-hero-widget-design.md.
struct MushroomSignalHeroView: View {
    let signals: [SpeciesSignal]
    let dailyWeather: [DailyWeather]
    let region: Region
    let today: Date

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sk_SK")
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var state: MushroomSignalHeroState {
        MushroomSignalHeroState.resolve(signals: signals, dailyWeather: dailyWeather, asOf: today)
    }

    private func isLoud(_ state: MushroomSignalHeroState) -> Bool {
        switch state {
        case .flushHappening, .rainIncoming: return true
        case .nearMiss, .noRain: return false
        }
    }

    private func slovakDayWord(_ count: Int) -> String {
        switch count {
        case 1: return "deň"
        case 2...4: return "dni"
        default: return "dní"
        }
    }

    private func slovakSpeciesWord(_ count: Int) -> String {
        switch count {
        case 1: return "druh"
        case 2...4: return "druhy"
        default: return "druhov"
        }
    }

    private func daysUntil(_ date: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today), to: Calendar.current.startOfDay(for: date)).day ?? 1)
    }

    private func headline(for state: MushroomSignalHeroState) -> String {
        switch state {
        case .flushHappening: return "Huby práve rastú"
        case .rainIncoming: return "Blíži sa dážď"
        case .nearMiss: return "Takmer to vyšlo"
        case .noRain: return "Žiadny výraznejší dážď"
        }
    }

    private func subline(for state: MushroomSignalHeroState) -> String {
        switch state {
        case .flushHappening:
            let count = signals.filter { $0.score == 4 }.count
            return "\(count) \(slovakSpeciesWord(count)) na 100 % — posledné dni priniesli ideálne teplo aj dážď."
        case .rainIncoming(let event):
            let days = daysUntil(event.date)
            return "O \(days) \(slovakDayWord(days)) · \(String(format: "%.0f", event.precipitationMm)) mm dažďa a \(Int(event.maxTempC.rounded()))°C"
        case .nearMiss(let insight):
            switch insight {
            case .rainWithoutHeat(let date, let precipitationMm, _):
                let days = daysUntil(date)
                return "O \(days) \(slovakDayWord(days)) mierny dážď (\(String(format: "%.0f", precipitationMm)) mm), ale bez dostatočného tepla."
            case .heatWithoutRain(let date, _, let maxTempC):
                let days = daysUntil(date)
                return "O \(days) \(slovakDayWord(days)) teplo (\(Int(maxTempC.rounded()))°C), ale bez výraznejšieho dažďa."
            }
        case .noRain:
            return "V predpovedi zatiaľ nie je dážď spĺňajúci podmienky pre novú vlnu."
        }
    }

    private var contextRow: String {
        let month = Calendar.current.component(.month, from: today)
        let monthName = Self.monthFormatter.string(from: today)
        return "\(region.nameSk) · \(monthName) · \(SeasonWord.forMonth(month))"
    }

    var body: some View {
        let currentState = state
        return VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            HStack(alignment: .top, spacing: DesignSystem.spacingSmall) {
                badge(for: currentState)
                VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                    Text(headline(for: currentState))
                        .font(.system(size: DesignSystem.titleSize, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                    Text(subline(for: currentState))
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                }
            }
            if isLoud(currentState) {
                MushroomSignalHeroMiniChart(dailyWeather: dailyWeather, today: today)
            }
            Text(contextRow)
                .font(.system(size: DesignSystem.captionSize))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
        }
    }

    @ViewBuilder
    private func badge(for state: MushroomSignalHeroState) -> some View {
        switch state {
        case .flushHappening:
            FlushHappeningBadge(reduceMotion: reduceMotion)
        case .rainIncoming:
            RainIncomingBadge()
        case .nearMiss:
            NearMissBadge()
        case .noRain:
            NoRainBadge()
        }
    }
}

/// Loud, animated: three mushroom caps with a staggered spring entrance, settling into a
/// slow breathing idle loop. See the "Animation design" note in the plan for why
/// `hasEntered` and `isBreathing` are two separate `@State` flags.
private struct FlushHappeningBadge: View {
    let reduceMotion: Bool
    @State private var hasEntered = false
    @State private var isBreathing = false

    private let caps: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (0.28, 0.62, 0.34, 0.0),
        (0.5, 0.7, 0.42, 0.16),
        (0.72, 0.58, 0.3, 0.32)
    ]

    private var breathingScale: CGFloat { isBreathing ? 1.06 : 1.0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.mossAccent.opacity(0.22))
                .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)

            GrowthRaysShape()
                .stroke(DesignSystem.Colors.mossAccent.opacity(0.5), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: DesignSystem.heroIconGlyphSize, height: DesignSystem.heroIconGlyphSize * 0.4)
                .offset(y: DesignSystem.heroIconGlyphSize * 0.32)
                .opacity(isBreathing ? 0.85 : 0.5)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: isBreathing)

            ZStack {
                ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                    MushroomCapShape()
                        .stroke(DesignSystem.Colors.mossAccent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: DesignSystem.heroIconGlyphSize * cap.size, height: DesignSystem.heroIconGlyphSize * cap.size)
                        .scaleEffect(x: 1.0, y: hasEntered ? 1.0 : 0.15, anchor: .bottom)
                        .scaleEffect(breathingScale, anchor: .bottom)
                        .position(x: DesignSystem.heroIconGlyphSize * cap.x, y: DesignSystem.heroIconGlyphSize * cap.y)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.62).delay(cap.delay),
                            value: hasEntered
                        )
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true),
                            value: isBreathing
                        )
                }
            }
            .frame(width: DesignSystem.heroIconGlyphSize, height: DesignSystem.heroIconGlyphSize)
        }
        .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)
        .onAppear {
            hasEntered = true
        }
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(1.07))
            guard !Task.isCancelled else { return }
            isBreathing = true
        }
        .onDisappear {
            hasEntered = false
            isBreathing = false
        }
    }
}

/// Loud, static: droplet with two short motion lines, unchanged `DropletShape` sized up.
private struct RainIncomingBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.water.opacity(0.22))
                .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)
            DropletShape()
                .stroke(DesignSystem.Colors.water, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.heroIconGlyphSize, height: DesignSystem.heroIconGlyphSize)
            ForEach([CGFloat(-1), 1], id: \.self) { side in
                Rectangle()
                    .fill(DesignSystem.Colors.water.opacity(0.6))
                    .frame(width: 1.4, height: DesignSystem.heroIconGlyphSize * 0.3)
                    .rotationEffect(.degrees(20))
                    .offset(x: side * DesignSystem.heroIconGlyphSize * 0.42, y: -DesignSystem.heroIconGlyphSize * 0.32)
            }
        }
        .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)
    }
}

/// Quiet: sunrise arc (reused from the flush-trigger glyph language) with a faint dashed
/// droplet beneath, smaller badge, caution/amber.
private struct NearMissBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.caution.opacity(0.18))
                .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
            SunriseShape()
                .stroke(DesignSystem.Colors.caution, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.heroIconGlyphSizeQuiet, height: DesignSystem.heroIconGlyphSizeQuiet)
                .offset(y: -DesignSystem.heroIconGlyphSizeQuiet * 0.14)
            DropletShape()
                .stroke(DesignSystem.Colors.caution.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [2, 2]))
                .frame(width: DesignSystem.heroIconGlyphSizeQuiet * 0.55, height: DesignSystem.heroIconGlyphSizeQuiet * 0.55)
                .offset(y: DesignSystem.heroIconGlyphSizeQuiet * 0.4)
        }
        .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
    }
}

/// Quiet: plain flat outline cloud, muted, low opacity, no droplet.
private struct NoRainBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.cloud.opacity(0.1))
                .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
            CloudOutlineShape()
                .stroke(DesignSystem.Colors.cloud.opacity(0.5), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.heroIconGlyphSizeQuiet, height: DesignSystem.heroIconGlyphSizeQuiet)
        }
        .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
    }
}
