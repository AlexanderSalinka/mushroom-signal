import Foundation

/// Resolves `MushroomSignalHeroView`'s 4-way state — one shared priority ladder over
/// signals already computed by `AppState.refresh()`/`SignalPipeline` and the raw
/// forward-looking detectors. Pure, no I/O, so it's fully unit-testable against fixture
/// data the same way `FlushTriggerDetector`/`UpcomingRainDetector`/`NearMissRainInsight`
/// already are.
public enum MushroomSignalHeroState: Equatable, Sendable {
    case flushHappening
    case rainIncoming(RainEvent)
    case nearMiss(NearMissRainInsight.Case)
    case noRain

    /// - Parameter signals: today's ranked signals (`AppState.signals` in the app) — every
    ///   entry shares the same `flushTriggered` value for a given refresh cycle, so reading
    ///   it here avoids a second, independently-fetched call to `FlushTriggerDetector`.
    public static func resolve(signals: [SpeciesSignal], dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> MushroomSignalHeroState {
        let flushTriggered = signals.contains { $0.flushTriggered }
        let hasMaxedOutSpecies = signals.contains { $0.score == 4 }
        if flushTriggered && hasMaxedOutSpecies {
            return .flushHappening
        }
        if let event = UpcomingRainDetector.nextTriggerEvent(in: dailyWeather, asOf: today, calendar: calendar) {
            return .rainIncoming(event)
        }
        if let nearMiss = NearMissRainInsight.describe(in: dailyWeather, asOf: today, calendar: calendar) {
            return .nearMiss(nearMiss)
        }
        return .noRain
    }
}
