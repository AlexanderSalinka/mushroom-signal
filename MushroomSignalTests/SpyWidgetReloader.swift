@testable import MushroomSignal

actor SpyWidgetReloader: WidgetReloading {
    private(set) var reloadCount = 0

    func reloadAllTimelines() async {
        reloadCount += 1
    }
}
