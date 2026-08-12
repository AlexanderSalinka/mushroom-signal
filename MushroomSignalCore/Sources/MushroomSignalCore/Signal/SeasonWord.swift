import Foundation

/// Maps a calendar month to its Slovak season word — used by `MushroomSignalHeroView`'s
/// context row (`region · month · season`). No existing code in this app produces this
/// mapping; `seasonCalendarSection` only ever needed the raw month number to filter
/// `fruitingMonths`, never a season name.
public enum SeasonWord {
    /// Slovak meteorological seasons: December-February winter, March-May spring, and so
    /// on — matches how Slovak weather/foraging content usually talks about seasons.
    public static func forMonth(_ month: Int) -> String {
        switch month {
        case 12, 1, 2: return "zima"
        case 3, 4, 5: return "jar"
        case 6, 7, 8: return "leto"
        case 9, 10, 11: return "jeseň"
        default: return "zima"
        }
    }
}
