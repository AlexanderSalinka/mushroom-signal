import Foundation

public enum NotificationThreshold {
    /// True only on an upward crossing (previous score below threshold, new score at/above
    /// it) — never fires on a refresh where the score was already at/above threshold, and
    /// never fires on the first-ever observation (nil previous score), which instead
    /// establishes a silent baseline.
    public static func shouldNotify(previousScore: Int?, newScore: Int, threshold: Int) -> Bool {
        guard let previousScore else { return false }
        return previousScore < threshold && newScore >= threshold
    }
}
